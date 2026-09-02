# Independent review — arcfox LineageOS bringup (2026-08-07)

Reviewer pass over `HANDOFF.md`, `FINDINGS.md`, `design-doc.md`, the scripts,
and the actual tree/artifact state on disk (`~/android/arcfox`,
`~/android/firmware/W1UXS36H`). Verdict first, then findings, then proposed
scenarios in the order I would run them.

## Executive summary

The work is in genuinely good shape. In one day the project went from "nothing
boots, no logs, no diagnosis" to: a proven-good boot chain (boot, init_boot,
vbmeta, vbmeta_system, vendor_boot, dtbo, both dlkm partitions — all built and
all verified by bisection against stock), a working root-shell recovery (TWRP),
a repeatable ~4-minute test cycle, and the failure isolated to the *content* of
the built `vendor.img`/system-side images. The methodology that got there —
structural diffs against stock artifacts instead of theorising — is exactly
right and should remain the rule.

**However, the review found one conclusion in HANDOFF.md that is unsound and is
very likely masking the actual remaining boot blocker:**

> "SELinux policy load failure — TESTED AND RULED OUT"

That test does not rule out SELinux, and the on-disk evidence points squarely
at the missing device sepolicy as the top suspect for the current failure. See
Finding 1. The proposed scenarios below are ordered around that: first make
the failing boot observable (cheap, permanent payoff), then fix sepolicy the
way every shipping device does, then re-bisect with instruments that work.

---

## What has been accomplished (verified, not just claimed)

- **Build works end to end**: signed 1.03 GiB A/B OTA zip, superimage via
  `lpmake` matching stock geometry byte-for-byte where it matters (metadata
  10.2, virtual_ab_device flag, dlkm extents identical to stock).
- **Boot chain proven good by bisection**: our boot + init_boot + vbmeta +
  vbmeta_system with *stock* super boots stock Android. This is the single
  most valuable result in the project — it converts every future failure into
  "content of our images", a finite search space.
- **Five real bugs found and fixed**, each by artifact diffing: recovery
  kernel_size, init_boot header v0 (inert `BOARD_INIT_BOOT_HEADER_VERSION`),
  super missing dlkm partitions, vbmeta_system never built (inert rollback
  vars), `/vendor/etc/fstab.qcom` never installed.
- **Kernel axis closed properly**: a second coherent kernel set produced
  identical behaviour; no time was wasted assembling the kleaf workspace.
- **Diagnostics mapped exhaustively**: logfs bootloader log (proves clean
  kernel handoff), pstore/ramoops dead ends documented with evidence, TWRP as
  the standing root-shell instrument, the metadata-magic indicator with its
  honest caveats.
- **HAL restoration executed at scale**: 62 missing HAL binaries traced to the
  zeekr-intersection mistake, 340 manifest entries added, dependency loop
  automated (`resolve-hal-deps.sh` at ~11s/round).
- **Documentation quality is exceptional.** Dead theories are buried with
  evidence, retractions are retracted when wrong, and every trap has a
  written escape route. Any competent person could resume from HANDOFF.md.

## Methodology assessment

The "compare, don't theorise" discipline documented at the end of HANDOFF.md is
validated by the project's own scorecard (5 bugs found by diffing, 0 by
theory). Two process weaknesses:

1. **Negative results were sometimes generalised beyond their test
   conditions.** The permissive test (Finding 1) and the early bisect rows
   (Finding 3) were both run on tree states that have since changed
   materially, but their conclusions are carried forward as settled.
2. **The boot itself was never instrumented from the inside.** Enormous effort
   went into ramoops/pstore (bootloader-owned, defeated), while the project
   *owns* `system.img` and its `init.rc` — a userspace logger service was
   never tried. Finding 4.

---

## Findings

### Finding 1 (critical): "SELinux ruled out" is unsound — zero device sepolicy is the prime suspect

The exoneration rests on `androidboot.selinux=permissive` not changing the
outcome. Two problems:

**a) Permissive mode does not make unlabeled services startable.** Permissive
only disables *denial enforcement*. Init separately refuses to start any
service whose executable has no SELinux domain transition defined — the
`"File ... (labeled u:object_r:vendor_file:s0) has incorrect label or no
domain transition"` / `"service ... does not have a SELinux domain defined"`
class of error. That check is about missing *policy*, not about enforcement,
and a permissive cmdline does not fix it.

**b) The test predates the HAL restoration.** It was run when vendor shipped
15 HAL binaries; the current build ships 68. The current ~320s failure mode
has never been tested under permissive at all.

Measured on disk right now:

| artifact | ours | stock |
|---|---|---|
| `vendor/etc/selinux/vendor_sepolicy.cil` | 209,852 B (AOSP skeleton) | 1,380,804 B |
| `vendor/etc/selinux/vendor_file_contexts` | 209 lines | 1,452 lines |
| `plat_sepolicy_vers.txt` | 202504 | 34.0 |
| `BOARD_VENDOR_SEPOLICY_DIRS` | **not set — zero device policy** | n/a |

Consequence: essentially **every one of the 68 restored vendor HAL services is
labeled `vendor_file` with no domain, so init refuses to launch all of them.**
No keymint/gatekeeper → vold cannot set up metadata/data encryption. No boot
HAL, no health, no USB HAL (also explains no adb during the hang).

This single defect coherently explains the current signature — and note the
HAL restoration *cannot have worked* without it, so "HAL restoration complete,
still fails" was the expected outcome, not evidence against the HAL theory.

### Finding 2: the ~320s-then-bootloader signature matches init's critical-service budget

A `critical` service (servicemanager, vold, etc.) that crashes/fails 4 times
within a 4-minute window makes init reboot to the bootloader with reason
`reboot,critical-service-crashed:<name>`. 320 s ≈ that window plus boot
overhead. If correct, two things follow:

- Second-stage init **is running** in the all-ours build; first-stage mount is
  no longer the problem (consistent with the fstab/dlkm fixes landing).
- **The failing service's name is likely recorded** in the reboot reason —
  possibly retrievable without any new build (see Scenario 0).

### Finding 3: the bisect table contradicts "vendor.img is the culprit" — and it's glossed over

The ~14:20 section declares vendor.img the culprit because
stock-system + our-vendor fails. But the earlier bisect table also records:

> ours system+system_ext+product, stock vendor → **fails** (meaningful: valid Treble pair)

If both halves fail independently, either there are ≥2 content bugs, or —
more likely given Finding 1 — a **common-mode failure** breaks both
directions (each mixed pairing has a broken sepolicy story: our system brings
plat 202504 against stock vendor's 34.0 CILs; our vendor brings a skeleton
policy against any system). The HANDOFF's own ~18:00 caveat about the
sepolicy confound applies to *both* rows of its bisect table, not just one.
That row was also run before vbmeta_system/fstab/dlkm fixes, so it needs a
retest before any conclusion of the form "the bug is inside vendor.img" is
trusted. Until then, treat "vendor is the culprit" as *"mixed supers fail;
all-ours fails ~320s later than they used to"* — which is all the data shows.

### Finding 4: the boot was never instrumented from userspace — the cheapest remaining instrument

We build `system.img`, so we own second-stage `init.rc`. A trivial debug
service (system side, where AOSP policy provides domains — e.g. run as
`u:r:shell:s0` on userdebug) can loop-dump `logcat -b all` and
`/proc/kmsg` to `/metadata/bootlog/` (f2fs, mounted early, readable from
TWRP) or `dd` them onto an empty scratch partition (`kpan`, `ramdump`).
If Finding 2 is right and init runs for ~5 minutes, this yields the full
logcat of the failure — ground truth for every subsequent decision, at the
cost of one rebuild. This should have been tried before the ramoops
excavation; do it now, first.

### Finding 5 (minor, collected)

- **sha1 hashtrees** flagged in HANDOFF but never diffed vs stock (`avbtool
  info_image`). AVB axis is closed from two directions, so low priority.
- **`pvmfw` descriptor** difference vs stock — untested, plausibly irrelevant
  (not in fstab; pKVM firmware). Leave.
- **`manifest_cliffs.xml` / `ro.boot.product.vendor.sku`** — correctly
  identified as post-boot work; make sure `init.qti.qcv.rc` and its
  dependency chain shipped with the restored init scripts, otherwise *no*
  SKU manifest gets selected and several HALs won't register even once it
  boots.
- **`inject-vendor-mountpoints.sh` is a footgun**: a manual step between
  `mka vendorimage` and super assembly that, if forgotten, reintroduces a
  known-fatal defect silently. Fold it into `build-super*.sh` (call it
  unconditionally) until the soong-proper fix exists.
- **The permissive cmdline is still in BoardConfig** per HANDOFF's own note
  ("diagnostic only — remove it"). Verify it's gone before any release build.
- **Memory note**: `fastboot devices` liveness gotcha is already in project
  memory — the flash scripts should probe `getvar` before the 200s super
  flashes (stale fastboot processes holding the device are mentioned in
  HANDOFF as a real incident).

---

## Proposed scenarios, in execution order

The ordering principle: **evidence before fixes, structural fixes before
bisection.** Scenario 0 costs minutes and may name the failing service
outright; Scenario 2 is the fix the evidence already points to.

### Scenario 0 — harvest the evidence the last failure already left (no rebuild, ~15 min)

1. Reproduce the all-ours ~320s failure once. When it drops to the
   bootloader, **immediately** boot TWRP and read:
   - `getprop ro.boot.bootreason` — if it says
     `reboot,critical-service-crashed:<name>`, the bug has a name and
     Finding 2 is confirmed.
   - `dd if=/dev/block/by-name/misc bs=1 count=4096 | strings` — misc is
     write-protected via fastboot but readable; init's reboot reason lands in
     the bootloader message block.
   - the `logfs` log for the *failed* session (two back per the numbering
     rule) **and the session after it** — the bootloader may echo the reset
     reason on the way back up.
   - the metadata magic (`dd ... skip=1024 count=4`) — never rechecked after
     the HAL restoration; if it now reads `10 20 f5 f2`, first-stage mount is
     officially past, narrowing everything to second-stage services.
2. During the ~320s hang, watch `lsusb` on the host once per second. Any
   enumeration (even `unauthorized`) is a bonus data point.

### Scenario 1 — instrument the boot from inside (one rebuild, permanent payoff)

Add a system-side debug service (userdebug, `seclabel u:r:shell:s0`,
`user root`) started `on post-fs` that loops
`logcat -b all -f /metadata/bootlog/logcat.txt` and periodically copies
`/proc/kmsg`; if `/metadata` turns out unavailable, `dd` to the empty `kpan`
or `ramdump` partition instead. Read results from TWRP after each failed
boot. From this point on, **no theory needs to be tested blind again** — this
retires the "every theory costs a flash cycle with no output" tax that made
the whole day expensive.

### Scenario 2 — ship a real vendor sepolicy (the structural fix; strong prior it's THE fix)

Two viable routes; A is recommended.

**Option A — wire the in-tree QCOM vendor policy (how shipping devices do it).**
`device/qcom/sepolicy_vndr` is already in the tree (sm8450/sm8550/sm8650 +
legacy-um), and it is what official LineageOS SM8635 devices (peridot —
same-generation platform, already used for kernel headers) build against.

```make
# BoardConfigCommon.mk
-include device/qcom/sepolicy_vndr/SEPolicy.mk
BOARD_VENDOR_SEPOLICY_DIRS += device/motorola/sm8635-common/sepolicy/vendor
```

Then a small device dir for Motorola-specific services, grown iteratively
from the Scenario-1 logs (labels for `bin/hw/*` binaries + domain/typetransition
per service — mechanical once logs name the refusals). Bonus: this tree
already contains the exact `vendor_sysfs_usb_controller` genfs labels for
`a600000.ssusb` that the recovery-USB investigation independently identified
as missing — one fix, two open problems (check the sm8650/ flavor covers the
same paths as legacy-um's kona/lahaina lines do).

Cross-check against peridot's device tree
(`LineageOS/android_device_xiaomi_peridot`) for how much device-side policy a
booting SM86xx LineageOS device actually needs — it is the closest official
reference for the SoC side, as zeekr is for the foldable side.

**Option B — GSI-style: ship stock's vendor sepolicy as prebuilts.**
Copy stock's entire `/vendor/etc/selinux/` (CILs, contexts,
`plat_sepolicy_vers.txt` = 34.0) into the vendor image as blobs. The system
image carries compat mappings for 34.0 (`system/sepolicy/prebuilts/api/34.0`
exists in-tree), so LineageOS-system-over-34.0-vendor is a supported Treble
configuration — it is literally how GSIs boot on stock vendors. Less build
plumbing than it sounds (they're just files in `proprietary-files.txt`), and
it maximally matches the stock blobs, but it forfeits the ability to *edit*
policy and the precompiled-policy fast path. Reasonable fallback if Option A
fights back.

With either option, rerun the permissive test *on the current build* while
at it — that datapoint is stale (Finding 1b).

### Scenario 3 — resolve the bisect contradiction with a GSI cross-check (no build needed)

Flash a known-good **AOSP GSI** (arm64-ab, user or userdebug) as `system`
over an otherwise stock super (via `build-super-mix.sh` with the GSI image
substituted), stock everything else:

- **GSI boots** → generic-system-over-stock-vendor is fine on this device;
  the old "ours system + stock vendor fails" row was an artifact of
  since-fixed bugs or the sepolicy confound; re-run that row with the current
  tree — if it now boots, Finding 3 dissolves and vendor really is the only
  remaining culprit.
- **GSI fails** → something outside our images (bootconfig, vbmeta_system
  interplay, device quirk) breaks *any* non-stock system, which redirects the
  whole investigation away from vendor content. Ten minutes, potentially
  saves days.

### Scenario 4 — vendor content bisection by repack (if Scenarios 0–3 haven't produced the answer)

Make the instrument trustworthy first, then bisect:

1. Repack **stock vendor content verbatim** as an our-built image (our AVB
   footer, our build's packaging) under stock system. Boots → packaging
   exonerated, pure content search. Fails → the bug is in how we *build*
   vendor images, an entirely different (and smaller) search space.
2. Then move stepwise from stock-content toward our-content in coarse groups
   (build.prop + prop overlays; etc/vintf; etc/selinux; etc/init set;
   bin+libs), ~4 min per cycle with `build-super-mix.sh`. Keep the ~18:00
   caveat in mind: once system and vendor sepolicy sources diverge within a
   mix, failures stop being attributable — which is one more reason Scenario
   2 should land first.

### Scenario 5 — after first boot: the deferred debts, in order

Not boot blockers, but schedule them so they don't surprise:

1. **Boot-control HAL registration + slot-success marking** — verify
   `slot-successful:a` goes `yes` after the first good boot, or every reboot
   burns retries until fallback.
2. **Parked regressions**: wifi-service/wpa_supplicant (Wi-Fi OFF),
   fingerprint FPC, face unlock, StrongBox — each parked with a documented
   reason; re-audit once logs exist.
3. **cliffs SKU manifest chain** (Finding 5) — fingerprint/touch/camera HALs
   won't register without it.
4. **Recovery USB** — likely fixed for free by Scenario 2 Option A's genfs
   labels + the existing zeekr-style rc; low priority while TWRP serves.
5. **`;DISABLE_CHECKELF` blobs (~10)** — replace with proper
   `.replace_needed`/`.add_needed` fixups peridot-style before publishing.
6. **Pre-publish**: `scrub-check.sh`, remove the permissive cmdline, re-enable
   erofs for shipping size.

---

## Risk notes

- The current loop is safe and proven: bootloader always reachable
  (Power+VolDown), `restore-stock.sh --full` recovers in ~90s, BCB escape
  documented, A/B retry reset known. Keep obeying the standing rules: TWRP
  30-second sanity check before full boots, `getvar` probe before long
  flashes, never `fastboot reboot recovery` without a BCB exit plan.
- Scenario 2 Option A can produce neverallow build breaks against LineageOS's
  newer plat policy; budget an iteration loop, and resist
  `SELINUX_IGNORE_NEVERALLOWS` except as a temporary diagnostic.
- One process rule going forward, learned from Findings 1/3: **when a tree
  changes materially (HAL set, sepolicy, partition set), previously "ruled
  out" axes revert to "untested".** Date-stamp exonerations with the tree
  state they were measured on — HANDOFF already does this well for positive
  results; extend it to the negative ones.

## Bottom line

The project is one well-understood defect class away from a plausible first
boot: everything structural is proven good, the failure is in userspace
service bring-up, and the tree ships **no vendor SELinux policy** while
depending on 68 vendor services that cannot start without one. Run Scenario 0
tonight (it may name the failing service without a single rebuild), land the
logger (Scenario 1), then fix sepolicy (Scenario 2). Bisection (Scenario 4)
is the fallback, not the plan.

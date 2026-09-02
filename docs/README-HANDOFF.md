# arcfox handoff

Everything needed to continue LineageOS bringup for the Motorola Razr 50 Ultra
(`arcfox`, `XT2451-3`, channel `reteu`) on the build machine.

Produced 2026-08-06 on the laptop. No git involved; this is a plain archive.

## Read this first: the captures are stale

Every measurement in `FINDINGS.md` and `contract-android14/` was taken from
**stock Android 14** (`U3UXS34.56-124-1-1`, vendor patch 2024-12-01).

**The phone has since been updated to Android 16.** So:

- Display addresses are *likely* unchanged, but unverified.
- The stock `device_state_configuration.xml` may have changed. It is the basis
  for the entire fold config, so this matters.
- Vendor API level moved from 34 to (expected) 36.
- The `hinge_posture` quantization ladder should be re-confirmed.

**First action on this machine:** plug in the phone, enable USB debugging,
re-accept the adb authorization prompt, then

```bash
./capture-contract.sh open
./capture-contract.sh half
./capture-contract.sh closed
```

and diff the results against `contract-android14/`. Treat `FINDINGS.md` as a
hypothesis until that diff is clean.

Also record and compare:

```bash
adb shell "getprop ro.build.fingerprint; getprop ro.board.api_level; uname -r"
```

## What is in here

| File | What it is |
|---|---|
| `FINDINGS.md` | The substantive work. Device identity, display addresses, the seven-state fold table, the quantized sensor ladder, two silent-failure traps, the zeekr gap analysis, firmware constraints. |
| `capture-contract.sh` | Re-runs the hardware contract capture. Read-only against the phone. |
| `scrub-check.sh` | Finds handset-identifying values before anything is shared. |
| `preflight.sh` | Verifies this machine can build LineageOS. **Run this early.** |
| `design-doc.md` | The office-hours design doc: approaches, premises, why this scope. |
| `learnings.jsonl` | Durable gotchas logged during the session. |
| `contract-android14/` | The Android 14 baseline captures, minus the 12.9MB of vendor-image pulls (those are Motorola's, re-extract locally if needed). |

## State of play

**Not blockers, verified:** bootloader unlocked; GKI 2.0 kernel so probably no
kernel compile; SM8635 officially supported in LineageOS via `peridot`; A/B plus
dynamic partitions; fold behavior fully characterized; full stock firmware
mirrored for rollback (though see the Android 16 caveat in `FINDINGS.md`).

**The one real blocker:** both `proprietary-files.txt` files in the existing
Motorola-Pineapple trees contain a single TODO comment. zeekr's equivalents are
496 and 1177 lines. Nothing is testable until that manifest exists.

## Work order

0. `./preflight.sh ~/android/arcfox` and fix anything marked BLOCK.
   Known missing on the laptop, likely here too: `repo`, `git-lfs`, `ccache`.
1. Re-capture the contract on Android 16 and diff (see above).
2. Author `proprietary-files.txt` for the device and common trees, then run
   `extract-files.py`.
3. Write `lineage.dependencies` in the common tree so the kernel and module
   repos are actually fetched. This forces a choice between
   `Motorola-Pineapple/android_kernel_motorola_sm8650` and
   `Kendrenogen-moto-sm8635-6-6/android_kernel_motorola_sm8635`; decide from
   evidence, not repo names.
4. `modules.load` / `modules.blocklist`, then attempt a `bootimage`.
5. `fold/` last, once something boots and the behavior can be observed. Four
   files. Do not copy zeekr's `display_layout_configuration.xml`; see the trap
   documented in `FINDINGS.md`.

## Reference repos

- `AmeChanRain/device_motorola_zeekr` — the working Razr 40 Ultra port. Use
  `lineage-22.2`, which is more complete than `23.0`.
- `AmeChanRain/device_motorola_sm8475-common` — its common tree.
- `Motorola-Pineapple/android_device_motorola_arcfox` — the stalled skeleton.
  Useful for identity only.
- `Kendrenogen-moto-sm8635/recovery_device_motorola_arcfox` — TWRP, `twrp-14`,
  stale since Dec 2024.

# arcfox — Flashing Runbook

**Read this before writing anything to the device.** Every rule below is here
because violating it cost a flash cycle, a wedged bootloader, or a silently
broken subsystem.

---

## Rule 1 — NEVER flash from fastbootd. Use the BOOTLOADER.

On arcfox, **fastbootd cannot open `super` at all.** It enumerates over USB and
answers `getvar`, so it looks healthy — but every logical partition, and `super`
itself, is unreadable:

```
$ fastboot getvar partition-size:super            # in fastbootd
getvar:partition-size:super   FAILED (remote: 'Could not open partition')
$ fastboot flash vendor_dlkm vendor_dlkm.img      # in fastbootd
Sending 'vendor_dlkm_a' (89400 KB)   OKAY [ 2.077s]
Writing 'vendor_dlkm_a'              FAILED (remote: 'No such file or directory')
```

Reproduced on two independent fresh entries (2026-08-29). The same `getvar` from
the **bootloader** returns `0x0000000632700000` (26,616,004,608 B) correctly.

`system_a`, `vendor_a`, `product_a`, `odm_a` fail identically — so a failure here
is **not** damage to the partition you were flashing. Nothing is written; the
command fails before the write stage.

**Enter the bootloader:**
```bash
adb reboot bootloader          # or: power off fully, hold Volume Down + Power
```
Do **not** use `adb reboot fastboot` — that is fastbootd.

## Rule 2 — Gate test before every flash

Two checks. Both must pass or **stop**:

```bash
FB=/opt/android-sdk/platform-tools/fastboot
$FB getvar is-userspace            # MUST be: no    (yes = fastbootd, wrong mode)
$FB getvar partition-size:super    # MUST be: 0x0000000632700000
```

`fastboot devices` proves only USB enumeration, never liveness — a wedged
bootloader still enumerates. Always probe with a real `getvar`.

## Rule 3 — Logical partitions are not individually flashable. Rebuild `super`.

`system`, `system_ext`, `product`, `vendor`, `vendor_dlkm`, `system_dlkm` live
inside `super`. Since fastbootd is unusable (Rule 1), the **only** way to change
any of them is to repack the whole `super` image:

```bash
cd $HOME/workspace/motorola-lineageos
./build-super-mix.sh all
```

⚠️ **Always `build-super-mix.sh all`, never `build-super.sh`.** The latter
hardcodes STOCK `system_dlkm`/`vendor_dlkm`; `modprobe` resolves
`/lib/modules/$(uname -r)/`, so stock modules built for another kernel never
load → `cfg80211: Unknown symbol rfkill_alloc` → no `qca_cld3` → **WiFi
completely dead**, with nothing in the failure naming dlkm or the kernel.

**Verify the `=== composition ===` block prints `OURS` six times** before
flashing. That check is the whole point of the script.

## Rule 4 — `fastboot flash super` MUST be backgrounded

The Bash tool's timeout is capped at 600 s regardless of what is passed. A
foreground call was SIGTERM'd mid-write: the bootloader wedged (enumerated, but
every `getvar` timed out) and recovery took a hardware power cycle
(Power + Volume Down, 15–20 s) plus a full re-flash.

```bash
setsid nohup $FB flash super "$OUT/super.img" >"$LOG" 2>&1 & disown
# then poll in SEPARATE, SHORT tool calls
```

⚠️ **Backgrounding is not enough — do not wait for it in the SAME tool call.**
Launching it detached and then looping `until grep -qE '^(OK|FAIL)' state; do
sleep 20; done` in that same call still hits the 600 s cap. On 2026-08-29 that
call was SIGTERM'd; the flash *process survived* but its USB transfer stalled
permanently at chunk 2 of 6, leaving `super` half-written and the bootloader
wedged (enumerated at 480 Mbps, every `getvar` timed out even at 45 s). Recovery
needed a hardware power cycle (Power + Volume Down, 15–20 s) and a full
re-flash. Launch in one call, then poll in later short calls.

⚠️ **`pkill -f flashsuper.sh` kills your own shell** — the pattern matches the
tool's own command line (exit 144). Use `pkill -f "[f]lashsuper.sh"`. Same
self-matching trap as `pgrep`.

⚠️ **If `flash super` stalls, retry with `-S 100M`.** On 2026-08-31 the default
sparse size (derived from `max-download-size` 0x10000000 = 256 MB, giving 6
chunks) stalled at **chunk 2 of 6 on three separate attempts**, twice with no
interference from the host at all. The USB link was negotiated at a healthy
480 Mbps each time, so it is not the classic degraded-cable signature.

```bash
$FB -S 100M flash super "$OUT/super.img"      # 47 smaller chunks
```

That completed in 106 s — the same wall-clock as a healthy default-size run, so
there is no speed penalty. Prefer it unconditionally for `super` on this device.
A stall is NOT evidence the image is bad; check whether the log is still growing
before concluding anything.

⚠️ **NEVER issue ANY fastboot command while a flash is in flight.** Not
`getvar`, not `reboot`. Only one fastboot session can hold the device; a second
command disrupts the transfer and wedges the bootloader exactly as an
interrupted flash does. On 2026-08-31 a `fastboot reboot` fired on a fixed
`sleep` timer — before the state file said `OK` — stalled `super` at chunk 2 of 6
and required a hardware power cycle plus a full re-flash. **Gate every
post-flash step on `grep -qE '^(OK|FAIL)' flashsuper.state`, never on elapsed
time.**

⚠️ **A live flash makes `getvar` answer "< waiting for any device >"** because
only one fastboot session can hold the device. That is NOT a wedge and NOT
corruption. Check `pgrep -f "[f]lashsuper.sh"` and whether the log is still
GROWING before concluding anything. A wedge looks different: `fastboot devices`
lists the device but `getvar` times out.

⚠️ `Finished. Total time: …` is **not** proof of success. A wedged mid-flash
prints it too, and leaves `super` corrupt (`Structure needs cleaning` / EUCLEAN
on later reads). Confirm by booting, not by the flasher's exit line.

## Rule 5 — Flash a COHERENT SET

Kernel, `vendor_ramdisk`, `vendor_dlkm` and `system_dlkm` modules must all come
from **one build**. A `.ko`'s `vermagic` string is not the ABI gate (symbol CRCs
are), but non-KMI vendor symbol CRCs *do* drift between kernel builds — mixing
is what kills WiFi/BT/data with no message naming the cause.

Check before flashing — every line must be the SAME version:

```bash
O=$HOME/android/arcfox/out/target/product/arcfox
strings -a $O/boot.img | grep -oE "Linux version 6\.1\.[-a-zA-Z0-9.]*" | head -1
modinfo $O/vendor_dlkm/lib/modules/*.ko            | grep "^vermagic" | sort -u
modinfo $O/system_dlkm/lib/modules/*/*.ko          | grep "^vermagic" | sort -u
modinfo $O/vendor_ramdisk/lib/modules/*.ko         | grep "^vermagic" | sort -u
```

⚠️ **If `boot.img` changes kernel, `vendor_boot` must be rebuilt and flashed
too.** The historical "vendor_boot stays stock by design" note was valid only
while we shipped the *prebuilt* GKI, whose vermagic matched stock's. Building
our own kernel voids it: stock's first-stage ramdisk modules then belong to a
different kernel.

Note `m bootimage vendor_dlkmimage system_dlkmimage` does **not** repack
`vendor_boot.img` — it will silently stay stale in `out/`. Check mtimes.

## Rule 6 — `fastboot -w` is not optional

Encryption keys change with the ROM. Skipping the userdata wipe bootloops with
`init_user0_failed`. This device is a test unit, not a daily driver — wiping is
fine, but say so before doing it.

---

## The procedure

```bash
FB=/opt/android-sdk/platform-tools/fastboot
O=$HOME/android/arcfox/out/target/product/arcfox
```

1. **Build** whatever changed, then repack super:
   `./build-super-mix.sh all` — confirm `OURS` ×6.
2. **Coherence check** (Rule 5) — all vermagic identical.
3. **Back up** — see below. `super` is NOT A/B; there is no second slot to fall
   back to.
4. `adb reboot bootloader`
5. **Gate test** (Rule 2) — `is-userspace: no`, super size correct.
6. Flash the boot chain:
   ```bash
   $FB flash boot        $O/boot.img
   $FB flash init_boot   $O/init_boot.img
   $FB flash vendor_boot $O/vendor_boot.img     # whenever the kernel changed
   ```
7. Flash super — **backgrounded** (Rule 4).
8. Flash vbmeta:
   ```bash
   $FB flash vbmeta        $O/vbmeta.img
   $FB flash vbmeta_system $O/vbmeta_system.img
   ```
   Do **not** pass `--disable-verity` / `--disable-verification`. They make
   fastboot rewrite the header, which fails here with a spurious
   `Failed to find AVB_MAGIC at offset: 0` and **silently skips the flash**.
   The build already sets `--flags 3`.
9. `$FB -w`
10. `$FB reboot` — first boot of a new ROM takes 5–10 minutes.

## Backups / escape hatches

| What | Where |
|---|---|
| Last-good images (`boot_a`, `vendor_boot_a`, `dtbo_a`, `vbmeta_a`, `super.img` 26,616,004,608 B) | `~/android/arcfox-backups/last-good-20260828/` |
| Stock logical-partition dump (`system_a`, `vendor_a`, `product_a`, `system_ext_a`, both dlkm, `super`) | `~/android/firmware/W1UXS36H/images/` |
| Full stock restore | `./restore-stock.sh --full` |

The stock dump has **no** `vendor_boot`/`boot`; those come only from the
`arcfox-backups` set. Do not overwrite that directory.

## Post-flash verification

```bash
A=/opt/android-sdk/platform-tools/adb        # /usr/bin/adb is BROKEN — do not use
$A wait-for-device; $A shell getprop sys.boot_completed
$A shell 'uname -r; lsmod | wc -l'
$A shell 'ls /system_dlkm/lib/modules/*/modules.load'   # MUST be a versioned dir
$A shell 'dumpsys wifi | head -3'
$A logcat -b all -d | grep -E "avc: +denied"            # two spaces, not one
```

⚠️ The stock loader `/vendor/bin/system_dlkm_modprobe.sh` tests
`${dir}/*/modules.load` — a **flat** `system_dlkm/lib/modules/` layout silently
loads nothing. The versioned subdirectory
(`lib/modules/android16-6.1/`) is mandatory; it requires both
`TARGET_KERNEL_VERSION` and `GKI_SUFFIX` to be set in `BoardConfigCommon.mk`.

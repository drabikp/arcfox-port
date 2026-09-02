# >>> READ `HANDOFF-NEXT.md` FIRST <<<
#
# This file remains the accurate chronological record and reference manual, but
# its STRATEGY is superseded. Summary of why:
#
#   Our device tree has 8 PRODUCT_PACKAGES entries and declares ZERO HAL
#   services built from source. The official LineageOS device for the SAME SoC
#   (peridot, Xiaomi SM8635, lineage-23.2 -- confirmed in LineageOS/hudson
#   lineage-build-targets) has 220 and builds most HALs from source, shipping
#   only 18 vendor/bin/hw blobs to our 73.
#
#   Copying 340 files out of stock's vendor to fill that gap is what produced
#   the AIDL version conflicts, the .replace_needed bumps, the VINTF mismatches
#   and the source-duplicate collisions documented below.
#
#   ALSO CORRECTED: zeekr is NOT an official LineageOS device (no wiki page, not
#   in lineage-build-targets). Sections below that call it "official" are wrong.
#   peridot is the authoritative reference for this SoC.
#
# ---------------------------------------------------------------------------

# arcfox — STATE OF PLAY (2026-08-07 07:40)

Read this first. `FINDINGS.md` has the full detail; this is where things stand
and what to do next.

## Bottom line

**The ROM builds and our LineageOS recovery RUNS ON THE PHONE.** Confirmed
visually: LineageOS Recovery **23.2 (20260807)** rendering on the inner display.
That is our build, executing on the hardware.

**Blocker:** recovery does not enumerate on USB, so `adb sideload` is impossible
and the ROM has never been installed.

**Phone is safe.** Currently on stock Android 16 unless left in recovery.
`./restore-stock.sh` has recovered it three times, ~90 seconds each.

## Exactly where we are

| Thing | State |
|---|---|
| ROM zip | `~/android/arcfox/out/target/product/arcfox/lineage-23.2-20260807-UNOFFICIAL-arcfox.zip` (1.03 GiB, signed, valid A/B OTA) |
| Device trees | `~/android/arcfox/device/motorola/{arcfox,sm8635-common}` |
| Vendor blobs | `~/android/arcfox/vendor/motorola/*` (~1100 files) |
| Firmware dump | `~/android/firmware/W1UXS36H/extracted` |
| Stock firmware | Windows partition, `ProgramData/RSA/Download/RomFiles/ARCFOX_G_W1UXS36H...` |
| **recovery.img** | **REBUILT 07:35 with USB fix — NOT YET FLASHED** |

## THE IMMEDIATE NEXT STEP

A freshly built `recovery.img` (07:35) contains a fix that has **not been tested
yet**. Flash it and see if USB comes up:

```sh
adb reboot bootloader                     # or power+voldown from off
fastboot flash recovery ~/android/arcfox/out/target/product/arcfox/recovery.img
fastboot reboot recovery
# on phone: Advanced -> Enable ADB
adb devices                               # <-- the whole question
```

If `adb devices` shows the device:

```sh
# on phone: Factory reset -> Format data     (mandatory, encryption keys change)
# on phone: Apply update -> Apply from ADB
adb sideload ~/android/arcfox/out/target/product/arcfox/lineage-23.2-20260807-UNOFFICIAL-arcfox.zip
```

The sideload writes system, vendor, product, system_ext, boot, init_boot and
vbmeta to the **inactive slot** and switches — including the `init_boot` that
fastboot always refused.

### What the USB fix is

`device/motorola/arcfox/rootdir/etc/init.recovery.qcom.rc`, installed to
`$(TARGET_COPY_OUT_RECOVERY)/root/` by `device.mk`.

AOSP's generic recovery init waits on `/sys/class/udc/${sys.usb.controller}`.
That property is normally set by Qualcomm's **vendor** init:

```
setprop vendor.usb.controller ${ro.boot.usbcontroller}
setprop sys.usb.controller    ${vendor.usb.controller}
```

Vendor init does not run in recovery, so the property is empty, the gadget is
never bound to a UDC, and USB stays dead. The script sets it explicitly.
Controller name from the stock `vendor/build.prop`:
**`vendor.usb.controller=a600000.dwc3`**.

### TESTED 07:45 — DID NOT WORK

The fixed recovery was flashed and booted, ADB enabled from its menu, and the
device **still does not enumerate on USB** (`lsusb` shows no 22b8 device).
So `init.recovery.qcom.rc` is either not being loaded or not sufficient.

Also observed: choosing **"Enter fastboot"** from our recovery gives *fastbootd*
(userspace), which uses the same broken gadget — also no USB. Only the
**bootloader-level** fastboot (Power + VolDown from off) enumerates.

Also observed: **the phone boots to recovery every time**, including via
`fastboot reboot` and "Reboot system now". Cause: the **BCB** (boot control
block) in the `misc` partition still holds the "boot-recovery" command written
by an earlier `fastboot reboot recovery`. Stock recovery clears it on exit; ours
does not. Fix from the bootloader:

```sh
fastboot erase misc      # safe: small command block, no user data
fastboot reboot
```

Remember this after every `fastboot reboot recovery` with our recovery — the
device will otherwise appear stuck in a recovery loop and look bricked when it
is not.

### 2026-08-07: measured on hardware, three dead theories buried

All read from the **running stock phone** (`adb shell getprop`):

```
ro.hardware            = qcom            <- filename init.recovery.qcom.rc IS correct
ro.boot.hardware       = qcom
ro.boot.usbcontroller  = a600000.dwc3    <- matches /sys/class/udc entry exactly
sys.usb.controller     = a600000.dwc3
ro.boot.usb.dwc3_msm   = <unset>         <- so stock's a600000.ssusb default applies
ro.boot.hardware.sku   = XT2451-3
```

`/sys/bus/platform/devices/` contains **both** `a600000.dwc3` and `a600000.ssusb`.
`/sys/class/udc/` contains exactly `a600000.dwc3`.

**DEAD THEORY 1 — wrong filename.** `ro.hardware` is `qcom`. Name was right.
**DEAD THEORY 2 — file missing from ramdisk.** It is present in both ours and stock.
**DEAD THEORY 3 — wrong controller name.** `a600000.dwc3` confirmed. Not `a800000`.

### The actual root cause chain (evidence, not guesswork)

**(a) `sys.usb.configfs` defaults to 0.** AOSP's generic recovery init.rc, line 13,
`on early-init`: `setprop sys.usb.configfs 0`. Every USB action is gated on it.
At 0 the LEGACY path runs: `write /sys/class/android_usb/android0/enable 1`.
`android_usb` is the old gadget driver and **does not exist on GKI 6.1** — the
writes fail silently and no gadget is ever bound. On a real Qualcomm device
*vendor init* flips this to 1; vendor init does not run in recovery.

**(b) The dwc3 controller must be switched to peripheral mode.** Stock does:
`write /sys/bus/platform/devices/${ro.boot.usb.dwc3_msm:-a600000.ssusb}/mode peripheral`

**(c) SELinux blocks (b), and probably the configfs writes too.** This is the
current blocker. Stock recovery's sepolicy contains genfs labels we do not have:

```
/devices/platform/soc/a600000.ssusb/mode
/devices/platform/soc/a600000.ssusb/a600000.dwc3/xhci-hcd.2.auto/usb
vendor_sysfs_usb_controller  vendor_sysfs_usb_node  vendor_sysfs_usb_device
vendor_sysfs_usbpd_device    vendor_sysfs_usb_c     vendor_sysfs_usb_supply
```

Ours has only `sysfs_usb`, `sysfs_usb_pd`, `sysfs_usb_data_enabled`.
Sizes: **ours 776,698 bytes vs stock 1,555,069** — we are missing the entire
vendor USB policy. Unlabeled sysfs defaults to type `sysfs`, which init is not
permitted to write.

Rewritten `init.recovery.qcom.rc` (done, modelled on stock, includes a
`sideload` handler AOSP lacks) got us (a) and (b) but **still did not enumerate** —
consistent with (c) being the remaining gate.

**NEXT: add genfs_contexts for the ssusb nodes to the device sepolicy** —
`device/motorola/sm8635-common/sepolicy/` — plus an allow rule for init, then
rebuild recovery. Stock's own labels above are the reference.

### Why this was expensive — read before debugging further

There is **no way to read logs off the device while USB is down**, so every
theory costs a full rebuild + flash + on-device menu cycle. Prefer offline
evidence: unpack stock `recovery.img` and diff it against ours. That is what
finally produced the real answer, and it costs nothing.

```sh
UNP=~/android/arcfox/system/tools/mkbootimg/unpack_bootimg.py
python3 $UNP --boot_img "$R/recovery.img" --out stockrec     # $R = RSA firmware dir
python3 $UNP --boot_img ~/android/arcfox/out/target/product/arcfox/recovery.img --out ourrec
for d in stockrec ourrec; do mkdir -p $d/fs && (cd $d/fs && lz4 -d -c ../ramdisk | cpio -idm); done
diff stockrec/fs/init.recovery.qcom.rc ourrec/fs/init.recovery.qcom.rc
strings stockrec/fs/sepolicy | grep -iE "ssusb|dwc3"
```

### CURRENT PLAN: install from the bootloader, skip recovery entirely

`./install-lineage-fastboot.sh` — recovery is **not required** to install the
ROM. Bootloader fastboot can write `super` directly (that is exactly what
`restore-stock.sh --full` does with stock's chunks), and `super` holds
system / vendor / product / system_ext.

```sh
cd ~/android/arcfox && source build/envsetup.sh && breakfast arcfox
mka superimage        # -> out/target/product/arcfox/super.img
```

Built 2026-08-07, **1,557,004,816 bytes** sparse. Verified with `lpdump` after
`simg2img`: metadata v10, 3 slots, groups `motorola_dynamic_partitions_{a,b}`,
partitions `system/system_ext/product/vendor` × `_a/_b`, total 26,616,004,608 —
matches `BOARD_SUPER_PARTITION_SIZE` exactly. (`lpdump` fails directly on the
sparse file with "invalid geometry magic" — convert with `simg2img` first.)

The script flashes a **coherent set** from one build: boot, init_boot, super,
vbmeta. That is the key difference from the two failed attempts, which mixed our
boot chain with stock's system — a guaranteed "No valid operating system found"
regardless of what vbmeta said. `vendor_boot`, `dtbo`, `vendor_dlkm`,
`system_dlkm` stay stock by design (prebuilt GKI kernel + Motorola's modules);
our vbmeta's `--flags 3` means that mix is not hash-checked.
`vbmeta_system.img` is not built — the script skips it.

It refuses to run under fastbootd via `getvar is-userspace`, because our
recovery's userspace fastboot has the same dead USB.

#### Run 1 result (2026-08-07 08:20) — partial

```
boot        OK
init_boot   FAILED    <- refused again, as always
super       OK  (34s) <- OUR system/vendor/product/system_ext ARE on the device now
vbmeta      FAILED    "Failed to find AVB_MAGIC at offset: 0"
userdata    erased
```

Device did not come up on USB within 90s after reboot.

**The vbmeta error is spurious.** `xxd` shows `AVB0` at offset 0 of our
`vbmeta.img`. The failure is caused by passing
`--disable-verity --disable-verification`; those flags are unnecessary because
the build already bakes the same thing in. Parsed headers:

```
        size    avb_ver  auth  aux   algo               flags
ours    65536   1.0      576   4736  2 (SHA256_RSA4096) 3   <- hashtree+verification disabled
stock   8192    1.0      320   5696  1 (SHA256_RSA2048) 0
```

So flash it plain: `fastboot flash vbmeta $OUT/vbmeta.img` (no extra flags).
Until that happens the device has **our super + our boot + STOCK vbmeta**, and
stock's vbmeta carries a hash descriptor for STOCK boot — a mismatch that on its
own explains a refusal to boot. Fix the script by dropping the two flags from
the vbmeta lines.

#### Run 2 result (2026-08-07 08:35) — vbmeta fixed, still no boot

`fastboot flash vbmeta vbmeta.img` **plain succeeded** (`Writing 'vbmeta_a' OKAY`),
confirming the `--disable-*` flags were the entire problem, not the image.

Slot A then held a fully coherent set: our boot + our super + our vbmeta.
Device still boots to LineageOS recovery.

**This is now a real diagnosis, not a guess.** Selecting "Reboot system now"
from recovery *does* clear the BCB (proven with stock recovery earlier). Landing
back in recovery after that exit therefore means the **system fails to boot and
the bootloader falls back to recovery** — it is no longer the BCB trap.

Remaining suspect, in order:
1. **`init_boot` is stock** — it has refused every flash attempt. On GKI it
   holds the generic ramdisk with first-stage init. Running our system under
   stock Motorola init is a genuine mismatch. THIS IS THE TOP SUSPECT.
2. `vendor_boot` is stock, and it carries the vendor ramdisk + fstab used for
   first-stage mount of our (differently laid out) super.

#### SOLVED 2026-08-07 08:45 — init_boot had a v0 header

Structural diff (`unpack_bootimg.py`), the same technique that cracked recovery:

```
                 header version    os_version    ramdisk
stock            4                 None          2098476
ours (bad)       0                 16.0.0        1700282
ours (FIXED)     4                 None          1700282
```

A v0 boot header on a GKI device — Motorola's bootloader rejects it outright.
That is why **every** `fastboot flash init_boot` failed while stock's succeeded.

Root cause: `BOARD_INIT_BOOT_HEADER_VERSION := 4` was **inert**. It only feeds
soong's filesystem generator. `build/make/core/Makefile:1582` builds init_boot
from `INTERNAL_INIT_BOOT_IMAGE_ARGS + INTERNAL_MKBOOTIMG_VERSION_ARGS +
BOARD_MKBOOTIMG_INIT_ARGS`, and **none** of those carry `--header_version`.

Fix in `sm8635-common/BoardConfigCommon.mk`:

```make
BOARD_MKBOOTIMG_INIT_ARGS += --header_version $(BOARD_INIT_BOOT_HEADER_VERSION) \
    --os_version 0 --os_patch_level 0
```

Rebuild with **`mka initbootimage`** (NOT `init_bootimage` — ninja target has no
underscore). ~1m15s. Verified header version 4, os_version None.

#### 2026-08-07 09:10 — init_boot fix WORKED, and the real boot blocker found

`fastboot flash init_boot` returned **OKAY** for the first time ever after the
header-v4 fix. That partition is solved.

**The BCB was cleared successfully** via stock recovery's menu exit, and the
bootloader then genuinely attempted to boot slot A. Proof, from `fastboot getvar`:

```
slot-retry-count:a   7   (before the attempt)
slot-retry-count:a   6   (after)
slot-unbootable:a    no
slot-successful:a    no
```

A consumed retry means the boot was ATTEMPTED and FAILED — this is no longer the
BCB trap. **Watch this counter.** At 0 the bootloader marks slot A unbootable.
`fastboot set_active a` resets it.

**ROOT CAUSE: our super.img is missing `vendor_dlkm` and `system_dlkm`.**

Stock's first-stage fstab, from `vendor_boot.img` →
`vendor_ramdisk00` → `first_stage_ramdisk/fstab.qcom`:

```
vendor_dlkm  /vendor_dlkm  erofs ro  wait,slotselect,avb=vbmeta,logical,first_stage_mount
system_dlkm  /system_dlkm  erofs ro  wait,slotselect,avb=vbmeta,logical,first_stage_mount
```

Both are **logical partitions inside super**, both `first_stage_mount`, both
`wait`, neither `nofail`. Our `BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST`
is only `system system_ext product vendor`, so `mka superimage` produced a super
without them — and `fastboot flash super` overwrote the whole partition,
**destroying stock's vendor_dlkm and system_dlkm**. First-stage init then dies
before console/adb/logging exists, which is exactly the silent failure observed.

This also breaks the whole design premise: we ship the prebuilt GKI kernel and
rely on Motorola's 287 vendor_dlkm + 60 system_dlkm driver modules. With those
partitions gone there are no drivers at all.

Extract stock's fstab yourself with:
```sh
python3 ~/android/arcfox/system/tools/mkbootimg/unpack_bootimg.py \
  --boot_img "$R/vendor_boot.img" --out vb
mkdir vb/fs && (cd vb/fs && lz4 -d -c ../vendor_ramdisk00 | cpio -idm)
cat vb/fs/first_stage_ramdisk/fstab.qcom
```

Note `system/system_ext/product` use `avb=vbmeta_system` and `vendor` uses
`avb=vbmeta`. We never build `vbmeta_system.img`; stock's (describing stock
hashes) is still on the device. Our vbmeta's `--flags 3` should make init skip
AVB entirely, but if boot still fails after the dlkm fix, this is suspect #2.

**THE FIX:** keep stock's `vendor_dlkm` and `system_dlkm` and include them in
our super. Extract them from stock's super, drop them into `$OUT`, add both to
`BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST`, rebuild `mka superimage`.

### 2026-08-07 09:00-10:00 — zeekr reference, two more real fixes, still no boot

#### The single most useful resource found: the OFFICIAL zeekr trees

`LineageOS/android_device_motorola_zeekr` and
`LineageOS/android_device_motorola_sm8475-common`, branch **lineage-22.2**
(no 23.x branch exists yet). Razr 40 Ultra — an officially supported Motorola
foldable. Fetch files raw:

```sh
B=https://raw.githubusercontent.com/LineageOS/android_device_motorola_sm8475-common/lineage-22.2
curl -s $B/BoardConfigCommon.mk
curl -s $B/recovery/root/init.recovery.qcom.rc
# list everything:
curl -s "https://api.github.com/repos/LineageOS/android_device_motorola_sm8475-common/git/trees/lineage-22.2?recursive=1"
```

**How much of it applies (asked and worth re-asking):** the *conventions*
transfer, the *contents* do not. zeekr is SM8475/waipio (SD 8+ Gen 1), arcfox is
SM8635/pineapple (8s Gen 3) — different kernel, blobs, HALs, display, fold
hardware. zeekr also BUILDS its kernel from source and BUILDS its own
vendor_dlkm, where we use the prebuilt GKI kernel + Motorola's stock modules.
zeekr is lineage-22.2 (Android 15) vs our 23.2 (Android 16). What does carry
over is Motorola/Qualcomm house style: `mot_dp_group` naming, vbmeta_system
chained at rollback location 2, `--flags 3`, group size = super − 4MB, and the
recovery-USB gap that exists on every QCOM device.

Notable zeekr settings we did not have:
```make
BOARD_MOT_DP_GROUP_PARTITION_LIST := product system system_ext vendor vendor_dlkm
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USES_METADATA_PARTITION := true
BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_MOVE_GSI_AVB_KEYS_TO_VENDOR_BOOT := true
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor
BOARD_MOT_DP_GROUP_SIZE := <SUPER_SIZE - 4MB>     # NOT super/2
```

#### FIX APPLIED: super.img now built with lpmake, including the dlkm partitions

`./build-super.sh` replaces `mka superimage`. It reuses Motorola's
`vendor_dlkm_a.img` and `system_dlkm_a.img` from
`~/android/firmware/W1UXS36H/images/` (already extracted) and matches stock
geometry exactly — verified by `lpdump`: metadata **10.2**, header flag
**virtual_ab_device**, dlkm extents identical to stock (63552 / 23144 sectors).
Groups are `mot_dp_group_a/b` at 26,611,810,304 each. Note that is NOT
`< SUPER/2`: that rule is for classic A/B. This is Virtual A/B, where only one
slot is materialised, so a group may span nearly the whole device — confirmed
against both stock's lpdump and zeekr's BoardConfig.

#### FIX APPLIED: vbmeta_system is now actually built

`BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX{,_LOCATION}` were already set but are
**inert on their own**. The line that generates the image is
`BOARD_AVB_VBMETA_SYSTEM := system system_ext product`, which we lacked — so no
`vbmeta_system.img` was ever produced and the device kept STOCK's, describing
stock's hashtrees. Stock's fstab mounts all three with `avb=vbmeta_system`.
Now added to `sm8635-common/BoardConfigCommon.mk`.

IMPORTANT: enabling this **regenerates system/system_ext/product/vendor** with
AVB footers, so `build-super.sh` MUST be re-run afterwards. Check timestamps.

#### Still not booting. Current state of slot A

boot (kernel byte-identical to stock, verified by md5), init_boot (header v4),
super (with dlkm + AVB footers), vbmeta, vbmeta_system — all ours, all flashed,
`metadata` and `userdata` erased. Result: hangs at Motorola logo, then drops to
bootloader, consuming one A/B retry each time.

#### A/B retry counter — how it works and how to reset it

```sh
fastboot getvar slot-retry-count:a     # 7 when fresh, decrements per failed boot
fastboot getvar slot-unbootable:a
fastboot --set-active=a                # resets count to 7, clears unbootable
```

A consumed retry PROVES the boot was attempted and failed (as opposed to a BCB
redirect, which consumes none). At 0 the bootloader marks slot A unbootable and
tries slot B, which is empty — that is NOT a brick, bootloader fastboot is
always reachable via Power+VolDown and `--set-active=a` restores it.

#### Recovery USB: THREE approaches tried, none worked

1. Just `setprop sys.usb.controller` — no.
2. Full stock-style manual configfs gadget + `/sys/bus/platform/devices/
   a600000.ssusb/mode` — no.
3. zeekr's minimal version (current file): `setprop sys.usb.configfs 1` plus
   `write /sys/class/udc/${ro.boot.usbcontroller}/device/../mode peripheral`,
   letting the generic init.rc build the gadget — **also no**.

The zeekr variant is worth keeping since it is the known-good pattern, but
something else is wrong. Untested ideas: confirm `ro.boot.usbcontroller` is even
set in recovery (it is set in Android; the recovery cmdline comes from our
boot.img + stock vendor_boot bootconfig); check whether adbd actually starts;
add the missing device sepolicy (we ship NONE — 777KB vs stock's 1.5MB).

## 2026-08-07 ~10:30 — TWRP WORKS. We now have a root shell and real logs.

### THE BIGGEST WIN: adb shell in recovery

Community TWRP **4.3.2** for arcfox boots, enumerates USB (18d1:d001) and gives
a **root shell**. Ours never did. This ends the no-logs problem.

Image saved at `<scratchpad>/TWRP-V4.3.2.img`, and inside `twrp.zip`.
Structurally: `kernel_size: 0`, header v4, `os_version 99.87.36 / 2099-12`
(they max it rather than zero it).

How to get it again — the XDA thread links a Nextcloud share whose listing needs
JavaScript, so render it with headless Chromium and walk the folders:

```
share: https://drive.integritywiz.com/index.php/s/tMEDEwdHa3GkcbK
path:  /RAZR Custom Recovery (NEW)/RAZR 2024 Custom Recovery/RAZR PLUS(2024)(ARCFOX)/RAZR 2024 TWRP
```
Download ONE subfolder (the whole share is 17GB of unrelated junk):
```sh
curl -sL "https://drive.integritywiz.com/index.php/s/tMEDEwdHa3GkcbK/download?path=<urlencoded-path>&files=RAZR%202024%20TWRP" -o twrp.zip
```
Also present: ORANGEFOX and PBRP folders.

Flash: `fastboot flash recovery TWRP-V4.3.2.img && fastboot reboot recovery`.

### HOW TO READ MOTOROLA'S BOOTLOADER LOG (huge — do this first, always)

`pstore`/`ramoops` is EMPTY on this device and `/proc/last_kmsg` does not exist,
so there is no kernel log. But Motorola keeps **bootloader logs in the `logfs`
partition**, a FAT16 volume. From TWRP:

```sh
adb shell 'mkdir -p /tmp/lf; mount -t vfat -o ro /dev/block/by-name/logfs /tmp/lf'
adb shell 'cat /tmp/lf/CurBoot.txt'      # e.g. "cycle 425, Log65.txt" = CURRENT boot
adb shell 'ls -lt /tmp/lf/*.txt | head'
adb shell 'cat /tmp/lf/Log63.txt' > Log63.txt
```

Numbering: each *boot session* gets a log, including bootloader/fastboot
sessions. So after `failed boot -> bootloader -> TWRP`, the failed boot is
**two back**, not one. Check the tail for the handoff.

Other log partitions: `logks` (ext4, `/mnt/product/logks`, holds `dmesglog.*`
and `logcat.*` — but only from 2024 factory; Android never runs long enough for
us to write there), `kpan` (kernel panic, empty), `ramdump` (empty),
`xbl_sc_logs`.

### WHAT THE BOOTLOADER LOG PROVED

The failed-boot log ends with a **clean handoff to the kernel**: bootargs set,
`Shutting Down UEFI Boot Services`, `Start EBS`. No AVB complaint, no image
rejection.

**This rules out: AVB, vbmeta, boot.img, init_boot.img, dtbo, the bootloader.**
The failure is in the kernel/init stage.

Also confirmed from that log: display panels are
`csot_nt37707_667_1080x2640_dsc_cmd_v3` (inner) and
`csot_nt37707_1080x1272_dsc_cmd_cli_v2` (cover).

### VERIFIED GOOD, from a TWRP shell

All six logical partitions map AND mount read-only with correct contents:
```
system_a system_ext_a product_a vendor_a vendor_dlkm_a system_dlkm_a
```
So `build-super.sh` produces a sound super, and the dlkm restoration worked.
`/vendor/etc/selinux/precompiled_sepolicy` is present (775,119 bytes).

### FIX APPLIED: /vendor/etc/fstab.qcom was NEVER INSTALLED

`device/motorola/arcfox/rootdir/etc/fstab.qcom` (70 lines, correct, adapted from
stock) existed in the tree from the beginning but `device.mk` only installed
`init.recovery.qcom.rc`. Proven on-device from TWRP:
`ls /vendor/etc/fstab*` -> No such file or directory.

First-stage mount survives that (it reads vendor_boot's
`/first_stage_ramdisk/fstab.qcom`, and we ship stock vendor_boot). But
**second-stage init** reads `/vendor/etc/fstab.<hardware>` and without it cannot
mount `/data`, `/metadata`, `/mnt/vendor/persist`, `/vendor/firmware_mnt`.

Fixed in `device.mk`:
```make
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.qcom:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.qcom
```
Rebuild: `mka vendorimage vbmetaimage vbmetasystemimage` then `./build-super.sh`,
then flash super + vbmeta + vbmeta_system.

**Result: necessary but NOT sufficient.** The failure MODE changed though — it
now HANGS at the Motorola logo indefinitely instead of resetting to the
bootloader after ~2 min. Previously every attempt burned an A/B retry; this one
did not reset at all. That is progress: init is getting further.

## 2026-08-07 ~11:00 — BISECT RESULT: our boot chain is GOOD, our super is NOT

Flashed **stock super** (the 23 sparsechunks) while keeping **our** boot.img,
init_boot.img and vbmeta. **Stock Android booted.** Confirmed by USB PID
`22b8:2e82` (normal Android/MTP; `2e80` = bootloader fastboot, `2e81` = recovery
adb), and adb briefly reporting `device` at t≈128s before debugging turned off
on the freshly wiped setup.

**Therefore PROVEN GOOD:**
- our `boot.img` (kernel byte-identical to stock, header v4)
- our `init_boot.img` (header v4 fix)
- our `vbmeta.img` (flags 3; bootloader rejects the test key then honours
  VERIFICATION_DISABLED and continues — visible in the logfs log)
- the whole fastboot install procedure

**Therefore THE FAULT IS IN OUR SUPER / SYSTEM IMAGES.** Not AVB, not the boot
images, not SELinux, not Virtual A/B, not the BCB, not vendor_boot.

This also retires suspect #2 (stock vendor_boot + our init): stock vendor_boot
drove our init_boot to a successful boot of stock's system.

### How to bisect further — use `build-super-mix.sh`

```sh
./build-super-mix.sh vendor              # only vendor is ours, rest stock
./build-super-mix.sh system system_ext   # those two ours, rest stock
./build-super-mix.sh all                 # everything ours (the failing case)
./build-super-mix.sh none                # everything stock (known-good baseline)
```

vendor_dlkm and system_dlkm are always stock — we never build them. Stock
component images are already extracted at
`~/android/firmware/W1UXS36H/images/*_a.img`.

Suggested order: `vendor` first (our blob work is riskiest there), then
`system`, then `system_ext product`.

**Flashing warning:** a mixed super containing stock's `product` is ~8.5GB
(stock product alone is 6.3GB) and takes well over 10 minutes to flash. Run the
flash in the background or with a long timeout — if it is interrupted partway
the super is left half-written and must be reflashed.

A mix does not need to boot Android fully to be informative (e.g. our vendor
under stock's system may fail on HAL compatibility). Read the result with the
metadata indicator below, which reflects first-stage mount only.

#### UN-RETRACTED: the metadata indicator IS valid, if used correctly

The retraction below was itself wrong — the reading was contaminated, not the
indicator. Rule: **erase metadata immediately before the boot you are testing**,
and read the f2fs magic directly (NOT `blkid`, which cannot probe it because
TWRP already has /metadata mounted):

```sh
fastboot erase metadata          # before the test boot
# ... boot attempt ... then from TWRP:
adb shell 'dd if=/dev/block/by-name/metadata bs=1 skip=1024 count=4 | od -An -tx1'
#  10 20 f5 f2  = formatted  -> first-stage init reached the metadata entry
#  00 00 00 00  = untouched  -> first-stage init died on the logical partitions
```

Controlled test run 2026-08-07 ~11:30, all-ours super + both fixes + metadata
and userdata erased immediately before: result **`00 00 00 00`**.

**CONFIRMED: first-stage init fails while handling the logical partitions.**

#### The paradox to solve next

- Our logical partitions **mount fine by hand in TWRP** (same kernel), all six.
- The **same vbmeta/boot/init_boot with STOCK super boots**.
- So the only variable is the content of our system/system_ext/product/vendor.
- AVB footers are self-consistent: for all four images, `Image size` in the
  footer == file size == the partition size given to lpmake. Not a size mismatch.
- vbmeta chain is correct (vbmeta: boot/init_boot/recovery/vendor + chain to
  vbmeta_system; vbmeta_system: system/system_ext/product). Flags 3.
- Note our hashtrees use **sha1**; worth diffing against stock's footers
  (`avbtool info_image` on `~/android/firmware/W1UXS36H/images/*_a.img`).

#### erofs ruled out — switched to ext4, same failure

erofs superblocks compared byte-wise against stock: same magic, same
`blocksize=12`, same `incompat: LZ4_0PADDING`. Only `feature_compat` differs
(ours 0x07 vs stock vendor 0x03), and compat bits are backward-compatible by
definition.

Rebuilt everything as **ext4** anyway (`BOARD_*IMAGE_FILE_SYSTEM_TYPE := ext4`,
matching zeekr, which never sets erofs), flashed with fresh vbmeta +
vbmeta_system and erased metadata/userdata. **Identical failure**, and metadata
still `00 00 00 00`. Both `system_a` and `vendor_a` mount by hand in TWRP as
ext4.

**Conclusion: the filesystem is not the problem, and first-stage init is not
failing on the mount operation itself** — the same images mount fine on the same
kernel from TWRP, in two different filesystem formats.

The BoardConfig is currently set to ext4. Either type appears equivalent for
this bug; erofs is the better shipping choice (smaller) once it boots.

## 2026-08-07 ~12:00 — vendor_boot IS now built (and one real bug fixed)

`PRODUCT_BUILD_VENDOR_BOOT_IMAGE := true` in `device/motorola/arcfox/device.mk`
(it was explicitly false), plus in `sm8635-common/BoardConfigCommon.mk`:

```make
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_PREBUILT_DTBIMAGE_DIR := $(COMMON_PATH)/prebuilt/dtb
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(wildcard $(COMMON_PATH)/prebuilt/modules/*.ko)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(shell cat .../modules.load)
BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD := $(shell cat .../modules.load.recovery)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_BLOCKLIST_FILE := .../modules.blocklist
BOARD_BOOTCONFIG += <stock's 7 androidboot.* entries>
BOARD_KERNEL_CMDLINE += <stock's vendor cmdline>
```
plus `device.mk` copying our fstab to
`$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.qcom`.

Staged into `device/motorola/sm8635-common/prebuilt/`:
`dtb/arcfox.dtb` (stock's dtb verbatim, 469,389 bytes — we build no kernel so we
cannot regenerate it) and `modules/` (282 .ko + modules.load, modules.load.recovery,
modules.blocklist, modules.softdep, all lifted from stock's vendor_ramdisk).

Result matches stock closely: header v4, same page size, same ramdisk load addr,
identical dtb size, ramdisk 8,172,043 vs stock 8,172,748.

#### REAL BUG FIXED: missing modules.load.recovery / modules.blocklist

The first vendor_boot build omitted them, and **TWRP stopped booting entirely** —
TWRP being a known-good recovery ramdisk that boots fine on stock vendor_boot.
Adding `BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD` (277 entries, vs 99
in the normal modules.load) and the blocklist restored it.

**This gives a fast vendor_boot sanity check: `fastboot reboot recovery`.**
If TWRP boots, vendor_boot's kernel modules and dtb are sane — a 30-second test
instead of a full flash-and-boot cycle.

#### But it did NOT fix the boot

Full set flashed (our vendor_boot + boot + super + vbmeta + vbmeta_system,
metadata and userdata erased): still hangs, metadata still `00 00 00 00`.
So stock-vendor_boot-with-LineageOS-init was NOT the cause.

#### Caveat on the metadata indicator — weaker than stated earlier

It is NOT proven that `/metadata` is formatted by *first*-stage init rather than
by vold in second stage. What the indicator reliably says is only: **the boot
never reached whatever formats /metadata.** Do not use it to claim the failure
is specifically in first-stage mount.

## 2026-08-07 ~13:00 — building the kernel from source: the sources DO exist

### What exists (all verified via the GitHub API, not assumed)

| repo | branch | size | what it is |
|---|---|---|---|
| `Kendrenogen-moto-sm8635/android_kernel_motorola_sm8635` | `stock` | 2.3 GB | Qualcomm msm-kernel, **6.1.129**. Has `build.config.msm.pineapple`, `pineapple.bzl`, `modules.list.msm.pineapple`, `modules.vendor_blocklist.msm.pineapple`. Right platform family for SM8635. |
| `Kendrenogen-moto-sm8635-6-6/android_kernel_motorola_sm8635` | `stock` | 2.4 GB | same, kernel **6.6** |
| `cenco-dev/android_kernel_motorola_sm8635-modules` | **`lineage-23.0`** | 186 MB | the vendor module set: `qcom/opensource` (9,356 files), `nxp/opensource`, `motorola` |
| `pachdomenic/android_device_motorola_arcfox-kernel` | **`lineage-23.0`** | 43 MB | **PREBUILT** kernel package for arcfox: `kernel` (Image), `dtbs`, `vendor_dlkm` (293 .ko), `vendor_ramdisk` (289), `system_dlkm` (112), `Module.symvers`, `System.map` |

The `Motorola-SM8635/*` repos that look official are **empty placeholders**
(0 KB, no branches) — do not waste time on them.

Stock runs **6.1.145-android14-11**; the source tree is 6.1.129. Different, but
that only matters if you mix source-built modules with stock ones — build them
all together and it is fine.

### DONE: we now BUILD vendor_dlkm and system_dlkm (real fix, but not THE fix)

Previously these two partitions held **stock images with Motorola's own AVB
footers**, while every other partition in super was ours — and our vbmeta had
**no descriptors for them at all**, even though the first-stage fstab mounts
both with `avb=vbmeta`. That inconsistency is now gone.

Staged from the firmware dump into `sm8635-common/prebuilt/`:
`vendor_dlkm_modules/` (287 .ko + modules.load + modules.blocklist) and
`system_dlkm_modules/` (60 .ko), taken from
`~/android/firmware/W1UXS36H/extracted/{vendor_dlkm,system_dlkm}`.

BoardConfig changes:
```make
BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST += vendor_dlkm system_dlkm
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm
BOARD_VENDOR_KERNEL_MODULES := $(wildcard $(COMMON_PATH)/prebuilt/vendor_dlkm_modules/*.ko)
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(shell cat .../vendor_dlkm_modules/modules.load)
BOARD_VENDOR_KERNEL_MODULES_BLOCKLIST_FILE := .../vendor_dlkm_modules/modules.blocklist
BOARD_SYSTEM_KERNEL_MODULES := $(wildcard $(COMMON_PATH)/prebuilt/system_dlkm_modules/*.ko)
```
The old `build_image.py KeyError: 'partition_size'` was simply because the
partitions were not in `BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST`, so
nothing sized them. Ninja targets are `vendor_dlkmimage` and `system_dlkmimage`
(with the underscore — `mka` suggests the right name if you get it wrong).

`build-super-mix.sh` now prefers our built dlkm images and falls back to stock's.

**Our AVB coverage is now COMPLETE and matches the fstab exactly:**
```
vbmeta:        boot, init_boot, recovery, vendor_boot,
               vendor, vendor_dlkm, system_dlkm  + chain -> vbmeta_system
vbmeta_system: system, system_ext, product
```

**Result: still does not boot**, metadata still `00 00 00 00`. Both built dlkm
partitions are present in `/dev/block/mapper/` and mount cleanly from TWRP.
So the AVB gap was real but is not the blocker.

### DONE: dtbo is now a build output with an AVB descriptor (also not THE fix)

Stock's vbmeta has a `dtbo` hash descriptor; ours did not, yet the fstab has
`/dev/block/by-name/dtbo /dtbo emmc defaults slotselect,avb=vbmeta,first_stage_mount`
positioned BEFORE the `/metadata` entry.

Fixed by shipping stock's dtbo as a prebuilt so our build re-signs it:
```make
BOARD_PREBUILT_DTBOIMAGE := $(COMMON_PATH)/prebuilt/dtbo/dtbo.img
```
The staged file is stock's `dtbo.img` with Motorola's AVB footer **stripped**
(`head -c 4358387`, leaving the raw DTBO container: magic `d7b7ab1e`, 11
overlays), so our build appends our own footer. Ninja has no `dtboimage` phony —
build it by path: `mka out/target/product/arcfox/dtbo.img`.

**Our vbmeta descriptor set now matches stock's**, except:
- `pvmfw` — stock has it, we do not. NOT in the fstab, so not part of
  first-stage mount. Untested; the only remaining descriptor difference.
- `product` — stock lists it directly in vbmeta AND chains vbmeta_system; we
  have it only in vbmeta_system. The fstab says `avb=vbmeta_system` for product,
  so ours is arguably the correct arrangement.

**Result: still does not boot.**

### The quick win, if you only want matched dlkm images

`pachdomenic/android_device_motorola_arcfox-kernel` (lineage-23.0) is prebuilts
extracted from a firmware dump — the same binaries we already have, but packaged
the LineageOS way with an `Android.bp`. Wiring it up would let us BUILD
`vendor_dlkm` and `system_dlkm` images instead of reusing stock's, closing one
of the divergences from zeekr without any kernel compile. Cheaper than a source
build and worth doing regardless.

## 2026-08-08 ~01:40 — *** BOOT-CONTROL HAL WAS CRASH-LOOPING; REBOOT LOOP IS GONE ***

### The userspace logger worked — first real logs of the whole project

`device/motorola/arcfox/logger/` + `device.mk` install a system-side service
that dumps logcat/dmesg to the raw **kpan** partition every 5s. System-side on
purpose (AOSP policy already grants /system/bin a domain) and to a raw
partition on purpose (/data and /metadata are themselves suspect).
`boot-cycle.sh` harvests it automatically after a failed boot:

```sh
adb shell 'dd if=/dev/block/by-name/kpan bs=4096 count=512' | tr -d '\000'
```

Justification for trying it at all: the bootloader log of the session AFTER a
failure reports
```
PM: Reset by PSHOLD          PON_REASON1: "HARD_RESET"
PM: Reset Type: Hard Reset   WARM_RESET_REASON1: "SOFT"
```
A **software** reset -- so init was running for minutes, not dying early. That
also means the old "metadata never formatted => first-stage init died" reading
was WRONG: a failed /metadata mount is tolerated, not fatal.

### What the log said

```
android.hardware.boot-service.qti: failed to stat /dev/block/bootdevice/by-name/misc  (x10)
android.hardware.boot-service.qti: Check failed: bootcontrol_init()
init: Service 'vendor.boot-qti' (pid 1687) received SIGABRT
init: starting service 'vendor.boot-qti'...     <- restart loop
```

The boot-control HAL crash-looped; init hit its critical-service budget and
rebooted. That is the ~328s PSHOLD reset, explained.

### Root cause: /vendor/etc/init/hw/ was never shipped (16 files)

`/dev/block/bootdevice` is a symlink created by `init.target.rc`:
```
on init
    wait /dev/block/platform/soc/${ro.boot.bootdevice}
    symlink /dev/block/platform/soc/${ro.boot.bootdevice} /dev/block/bootdevice
```
Those scripts live in `vendor/etc/init/**hw**/` -- a directory
`add-missing-hals.sh` never synced (it had `etc/init`, not `etc/init/hw`). We
shipped **0 of stock's 16**: init.qcom.rc, init.target.rc, init.mmi.rc,
init.qti.kernel.rc, init.qti.ufs.rc, ... Collateral: the fstab references
`/dev/block/bootdevice/by-name/` for persist, spunvm, modem and misc, so all of
those were unreachable too.

### RESULT: the reboot loop is GONE

With those 16 scripts shipped, the boot ran the **full 400s of the monitor
window without resetting** (every previous attempt PSHOLD-reset at ~328s).
It then sat with **no USB enumeration at all** and needed a power-cycle --
so it is not booted, but it is no longer crash-looping. Different failure,
further in.

### Speed lesson for the resolver

It capped at 60 rounds clearing double-installed `.rc`/`.xml` files ONE PER
ROUND at ~90s each. `extract_utils` auto-installs a HAL's init script and vintf
fragment with its module, so any such file whose basename matches a shipped
binary/lib is redundant. Removing all **90** in a single pass collapsed ~50
rounds into 3. Do that first whenever the blob list is widened.

## 2026-08-07 ~14:20 — *** THE CULPRIT IS vendor.img *** (superseded, see above)

Isolated by elimination with `build-super-mix.sh`:

| super contents | result |
|---|---|
| all stock | **BOOTS** |
| all stock + **our vendor_dlkm + our system_dlkm** | **BOOTS** (Android at ~152s) |
| stock system/system_ext/product + **our vendor** + our dlkm | **FAILS** (drops to bootloader in ~56s) |

Our dlkm images are fine. The only differing component between the booting case
and the failing case is **`vendor.img`**.

Note the failure SIGNATURE differs too: with our vendor it drops to the
bootloader in ~56s (fast), versus the long indefinite hang seen with the full
all-ours super. Two different failure modes; do not assume they are the same bug.

`vendor.img` is exactly where the risk always was: ~1,100 extracted proprietary
blobs, ~10 of them annotated `;DISABLE_CHECKELF` to silence unresolved-symbol
errors, a hand-built VINTF manifest, and a `device_framework_matrix.xml`
generated from `checkvintf` output.

### How to reproduce the good/bad pair quickly

```sh
./build-super-mix.sh none                 # all stock  -> boots
STOCK_DLKM=1 ./build-super-mix.sh vendor  # only vendor ours -> expect fail
```
(`STOCK_DLKM=1` forces stock dlkm images so vendor is the only variable.)
Flashing an 8.8GB super takes ~200-230s; use a long timeout and make sure no
stale `fastboot` process is holding the USB device.

### REAL BUG FOUND IN vendor.img: missing mount-point directories

The fstab mounts four PHYSICAL partitions onto directories inside vendor, and
our vendor image had none of them:

```
/vendor/firmware_mnt  <- modem      wait,slotselect     MISSING
/vendor/dsp           <- dsp        wait,slotselect     MISSING
/vendor/bt_firmware   <- bluetooth  wait,slotselect     MISSING
/vendor/fsg           <- fsg        wait,slotselect     MISSING
/vendor/rfs           (stock has it)                    MISSING
```
All are blocking `wait` mounts, and the kernel cmdline points
`firmware_class.path` at `/vendor/firmware_mnt/image`.

**PRODUCT_COPY_FILES CANNOT fix this.** Android 16's soong filesystem generator
refuses to install into a new top-level vendor directory:
```
error: build/soong/fsgen/Android.bp:41:1: module
  "vendor-..._mountpoints_firmware_mnt-vendor_firmware_mnt-0" ...
  Path is outside directory: ../firmware_mnt
```
Tried a hidden `.keep`, a plain `keep`, and source dirs mirroring the
destination — same error each time. Stop-gap:
**`./inject-vendor-mountpoints.sh`** creates them in the vendor staging tree and
rebuilds vendor.img. Run it after `mka vendorimage`, before `build-super-mix.sh`.
A proper fix needs a soong module or an fs_config entry.

**This did NOT fix the boot.** With the mount points present, the isolated test
(stock system/system_ext/product + STOCK dlkm + our vendor) still fails, with
the same fast signature. So vendor has at least one more defect.

### Reproducible test pair (fast, use this to bisect vendor)

```sh
./build-super-mix.sh none                  # all stock         -> BOOTS (~152s to Android)
STOCK_DLKM=1 ./build-super-mix.sh vendor   # only vendor ours  -> FAILS (~56s to bootloader)
```
8.8GB super, ~200s to flash. The failure consumes an A/B retry
(`slot-retry-count:a` 7 -> 6), so the boot really is attempted.

**pstore is still empty even after this failure**, which is a self-initiated
warm reset rather than a power cut — so DRAM retention is not the reason ramoops
never has anything. Treat kernel logs as permanently unavailable here.

### *** ROOT CAUSE: our vendor blob set is drastically incomplete ***

Comparing our built vendor tree against stock's
(`~/android/firmware/W1UXS36H/extracted/vendor`):

| | ours | stock |
|---|---|---|
| files total | 1,394 | 3,021 |
| `etc/init` (.rc) | 46 | **143** |
| `bin/hw` | 15 | **76** |
| `lib64/hw` | 23 | **58** |
| `etc/vintf/manifest` | 12 | **103** |
| `etc/permissions` | 4 | **60** |

**62 HAL service binaries are missing.** The ones we DO ship are almost all
Motorola-specific (camera, display panel/touch, sensorext) plus
`keymint-service-qti`. Missing includes, in rough order of how fatal:

- **`android.hardware.boot-service.qti`** — boot-control HAL. MANDATORY on an
  A/B device. Without it nothing can mark the slot successful, which is exactly
  consistent with the observed `slot-retry-count` decrementing on every attempt.
- `android.hardware.gatekeeper-service-qti`,
  `android.hardware.security.keymint-service.strongbox-thales`,
  `android.hardware.weaver-service.thales` — without the keystore/gatekeeper
  chain vold cannot set up metadata encryption, so `/data` can never mount.
- `android.hardware.health-service.qti`, `android.hardware.power-service`,
  `android.hardware.usb-service.qti`, `android.hardware.thermal-service.qti`,
  `android.hardware.sensors-service.multihal`
- `android.hardware.wifi-service`, `android.hardware.bluetooth@1.1-service-qti`,
  `android.hardware.audio.service`, `android.hardware.gnss-aidl-service-qti`,
  `android.hardware.nfc-service-st`, biometrics, drm, secure_element...

Get the full list with:
```sh
O=~/android/arcfox/out/target/product/arcfox/vendor
E=~/android/firmware/W1UXS36H/extracted/vendor
diff <(ls $O/bin/hw|sort) <(ls $E/bin/hw|sort) | grep '^>'
diff <(ls $O/etc/init|sort) <(ls $E/etc/init|sort) | grep '^>'
diff <(ls $O/etc/vintf/manifest|sort) <(ls $E/etc/vintf/manifest|sort) | grep '^>'
```

This is consistent with everything: our vendor breaks the boot, our images are
otherwise structurally perfect, and there is no log because the failure is a
HAL/service problem that occurs before logging is reachable.

#### FIX IN PROGRESS: `./add-missing-hals.sh --apply`

Computes every file stock's vendor has that our built vendor lacks, across
`bin/hw`, `etc/init`, `etc/vintf/manifest`, `etc/permissions`, `lib64/hw`,
`lib/hw`, and appends them to `sm8635-common/proprietary-files.txt`.

First run added **340 entries** (list went 883 -> 1229 lines):

| dir | added |
|---|---|
| bin/hw | 62 |
| etc/init | 97 |
| etc/vintf/manifest | 91 |
| etc/permissions | 54 |
| lib64/hw | 36 |

Deliberately NOT synced: `app/`, `priv-app/`, `framework/`, `overlay/` — that is
Motorola's UI payload, i.e. exactly the spyware surface this ROM exists to
remove. Only HAL/service plumbing is pulled in.

Then: `cd device/motorola/arcfox && ./extract-files.py ~/android/firmware/W1UXS36H/extracted`
followed by `build-loop.sh`, which iterates on the two mechanical error classes
(`depends on undefined module` -> add the blob; `check_elf_file` unresolved
symbol -> annotate `;DISABLE_CHECKELF`). Shared-library dependencies of the new
HALs are resolved by that loop, not by add-missing-hals.sh.

#### 2026-08-07 ~17:30 — HAL restoration COMPLETE, boot still fails

The full HAL restoration shipped: vendor.img now 713MB with **68 bin/hw
binaries (was 15, stock has 76)**, 126 init scripts, 88 vintf manifests, 57
permissions, 59 lib64/hw. All boot-critical HALs verified present. Both vbmeta
and super rebuilt around it.

Resolution machinery (all in `resolve-hal-deps.sh`, now analysis-only via
`mka nothing` at ~11s/round instead of ~90s):

| error class | handling |
|---|---|
| `depends on undefined module` | add the .so from the dump |
| `multiple versions of same aidl_interface` | HALT for a human (fix = `.replace_needed` in the COMMON extract-files.py — fixups in the wrong module's script silently do nothing) |
| `partition is different: system(X) != vendor(prebuilt_X)` | unship (platform builds that version) |
| `MODULE...already defined by <source>` | unship (in-tree source provides it) |
| `overriding commands for target` | unship the .xml/.rc (module vintf_fragment installs it) |
| `found in multiple namespaces` | drop from DEVICE list (imports are one-way) |
| `host_init_verifier: invalid interface` | drop the orphaned .rc |
| `check_elf_file: Unresolved symbol` | annotate `;DISABLE_CHECKELF` |

`.replace_needed` fixups added to **sm8635-common/extract-files.py** (NOT
arcfox's — fixups only apply in the script that owns the blob list):
sensors V2→V3, health V2→V4, wpa_supplicant supplicant V2→V4 + keystore2 V1→V5,
bluetooth audio V3→V5, composer3 V2→**V3** (match qcom-caf source, NOT newest),
allocator V1→V2 across 13 camera-stack blobs (found by readelf-ing every blob).

PARKED (documented regressions): wifi-service + wpa_supplicant (WI-FI OFF),
fingerprint FPC, face unlock, StrongBox keymint. Display composer is fine —
built from qcom-caf source.

**RESULT: still does not boot.** Two data points:
- Full all-ours super: hangs ~320s then drops to bootloader (LONGER than the
  ~56s pre-HAL failure — it gets further now).
- Isolated test (stock system/ext/product + stock dlkm + our vendor): still
  fails fast (~24s). The HAL gap was real but was NOT the vendor-breaking bug.

**CAVEAT ON THE ISOLATED TEST (added ~18:00):** stock system + our vendor may
now fail for an INHERENT reason, not a vendor bug. With mixed images the
precompiled_sepolicy sha256 cannot match, so stock init falls back to compiling
policy on-device from stock's plat CIL + OUR `plat_pub_versioned.cil`
(generated against LineageOS plat at vers **202504**, vs stock's **34.0** in
`plat_sepolicy_vers.txt`). That cross-mix can fail with a perfectly good
vendor. The all-ours build — where system and vendor are compiled together and
the precompiled policy is consistent — is the real metric, and it already
survives **~320s** (vs ~56s before the HAL work) before giving up, which looks
like service crash-looping, not structural failure. Prioritise all-ours boots
and treat isolated-test failures as only weak evidence from here.

Also found while comparing VINTF: stock ships BOTH `manifest_pineapple.xml`
(byte-identical to our manifest.xml) and **`manifest_cliffs.xml`** — SM8635's
real codename is **cliffs**, selected at runtime via
`ro.boot.product.vendor.sku` (set by `init.qti.qcv.rc` from
`ro.vendor.qti.soc_name`). The cliffs manifest adds: fingerprint, Motorola
touch/fingerprint/camera-desktop/health-storage, pasrmanager, ifaa. Not
boot-critical but needed for those HALs to register once the ROM boots.

**NEXT COMPARISON DIMENSIONS for vendor.img** (the isolated test is the
instrument — stock system + our vendor, ~200s flash + ~60s to verdict):
- `etc/vintf/manifest.xml` (the DEVICE manifest we author) + compatibility_matrix
- `build.prop` / `default.prop` differences vs stock vendor
- SELinux file_contexts: our vendor is built WITHOUT device sepolicy, stock's
  files carry labels from Motorola's policy
- `etc/fs_config_dirs` / `fs_config_files` (UID/GID/caps for vendor paths)
- remaining top-level dirs stock has that we still lack (odm link? etc?)

**THE UNDERLYING FIX** is to extend `proprietary-files.txt` to cover the missing HALs —
each needs its `bin/hw` binary, its `etc/init/*.rc`, its
`etc/vintf/manifest/*.xml`, its `lib64/hw` implementation and any dependent
libraries. This is mechanical but large; `resolve-build-blobs.sh` and
`build-blob-manifest.sh` already exist to help, and the firmware dump has
everything. Start with boot-control, then keymint/gatekeeper/weaver, then
health/power/usb, then the rest.

Note: the original blob list came from intersecting zeekr's list with this
firmware. zeekr is a different platform (SM8475 vs SM8635), so the intersection
silently dropped anything named differently — which is how 62 HALs went missing.

### Next: narrow down WITHIN vendor.img

Ideas, cheapest first:
1. Diff our `vendor/` staging tree against the stock `vendor` from the firmware
   dump (`~/android/firmware/W1UXS36H/extracted/vendor`): missing files,
   different `build.prop`, missing `etc/vintf/*`, missing init scripts.
2. Our vendor declares `ro.vendor.build.version.sdk=36` (Android 16) while the
   blobs are Motorola's Android 14/15-era and `BOARD_SHIPPING_API_LEVEL := 34`.
   Suspect a Treble/VINTF mismatch.
3. Build a vendor.img that is stock's content plus only our additions, to find
   which change breaks it.
4. Check `vendor/etc/vintf/manifest.xml` and the compatibility matrix — a VINTF
   mismatch is a classic cause of an early abort with no logs.

## 2026-08-07 ~14:00 — four more axes eliminated using the fstab as an instrument

We own the first-stage fstab now (it ships in our vendor_boot ramdisk), which
makes it a probe. Results:

**1. fstab-order probe — `/metadata` moved to the FIRST entry.** Still
`00 00 00 00` after the boot attempt. CAVEAT on interpreting this: AOSP's
first-stage mount does not strictly follow fstab order — it mounts `/system`
first (it needs it for `switch_root`) and then the rest. So this does NOT prove
init ignores the fstab; it means **we die at or before the `/system` mount**.

**2. AVB stripped from every fstab entry** (`avb=`, `avb_keys=` removed via
regex, verified in the built ramdisk: `system erofs
wait,slotselect,logical,first_stage_mount`). **Still fails.** So fs_mgr's
AVB/dm-verity setup is NOT why the `/system` mount fails. Combined with the
earlier vbmeta work, the AVB axis is now closed from both directions.

**3. super metadata made byte-identical in shape to stock** — re-enabled
`--virtual-ab` in `build-super-mix.sh`, giving `Metadata version: 10.2` +
`Header flags: virtual_ab_device`, exactly matching stock (we were emitting 10.0
/ no flags). **Still fails.** The earlier VAB test was not clean (it predated
the fstab/vbmeta_system/dlkm/dtbo/vendor_boot fixes); this one was, and the flag
makes no difference either way.

**4. Kernel module lists verified complete.** Every entry in
`prebuilt/modules/modules.load` (99) and
`prebuilt/vendor_dlkm_modules/modules.load` (413 entries, duplicates, 287 unique
files) resolves to a module that is actually present — **0 missing** in both.
The 413-vs-287 discrepancy is duplicate lines, which is harmless.

### KERNEL AXIS ELIMINATED — do NOT build the kernel from source

Swapped in a **completely different, internally coherent kernel set** from
`pachdomenic/android_device_motorola_arcfox-kernel` (lineage-23.0):

```
Image        6.1.128-android14-11 (md5 9ad92d9b...)  vs ours 6.1.145 (4209d7b4...)
dtb          469,367 bytes                            vs stock 469,389
vendor_ramdisk 282 .ko + modules.load/.recovery/.blocklist/.softdep
vendor_dlkm    286 .ko + metadata
system_dlkm     60 .ko
```
Rebuilt boot/vendor_boot/vendor_dlkm/system_dlkm/vbmeta/super around it and
flashed the lot. **Behaviour is identical** — same hang, same everything.

Combined with the earlier bisect (our boot chain + STOCK super = boots), this
eliminates the entire kernel axis: **kernel, dtb and all kernel modules are NOT
the cause.** Assembling the kleaf/bazel `kernel_platform` workspace would have
been wasted effort. The prebuilts have been restored to the stock-matched set
(6.1.145, md5 4209d7b4..., stock dtb 469,389).

Gotcha if you ever swap the kernel again: `out/target/product/arcfox/kernel` is
copied from `TARGET_PREBUILT_KERNEL` at kati time and is NOT regenerated by
ninja. Changing `prebuilt/Image` does not rebuild boot.img. Either delete
boot.img AND re-copy the Image over `out/target/product/arcfox/kernel`, or force
a full config regeneration. Verify with:
`unpack_bootimg.py --boot_img boot.img --out /tmp/x && md5sum /tmp/x/kernel`.

### Honest expectation-setting on the source build (SUPERSEDED — see above)

- The kernel is **not** implicated by any evidence we have: ours is byte-identical
  to stock's and boots stock's super fine.
- The real payoff is **diagnostics**. We proved no kernel log is obtainable on
  this device (see the ramoops verdict below). A kernel we compile ourselves can
  enable `earlycon` and a framebuffer/DRM console so boot messages render **on
  the phone's screen** — likely the only way left to see the actual failure.
- Cost is real: this is Qualcomm's `kernel_platform` bazel build, which wants
  `common/` + `msm-kernel/` + `vendor/qcom/opensource/*` + `vendor/motorola/*`
  + kleaf `build/` + matching clang prebuilts. Assembling that correctly is
  hours, not minutes.

## 2026-08-07 ~12:30 — kernel-log instrumentation via a patched dtb

Now that we build vendor_boot, we own the dtb, so we can add a **ramoops** node
and get the kernel's own console into persistent RAM — readable from TWRP. This
is the path to ground truth; it is close to working but not finished.

### How to patch the dtb (this part works)

```sh
dtc -I dtb -O dts -o stock.dts vb/dtb          # 21,322 lines, single dtb
# insert at the END of the reserved-memory node (properties must precede subnodes!)
dtc -I dts -O dtb -o patched.dtb patched.dts   # do NOT pipe dtc through head --
                                               # SIGPIPE kills it before it writes
cp patched.dtb device/motorola/sm8635-common/prebuilt/dtb/arcfox.dtb
mka vendorbootimage
```
Verify with `dtc -I dtb -O dts patched.dtb | grep -A9 ramoops_region` and diff
the round-tripped dts against stock's — should differ by exactly our 10 lines.

Node used:
```dts
ramoops_region@82000000 {
        compatible = "ramoops";
        reg = <0x00 0x82000000 0x00 0x200000>;
        console-size = <0x100000>;
        record-size = <0x20000>;
        pmsg-size = <0x20000>;
        ftrace-size = <0x00>;
        no-map;
};
```

### Results so far

- **It binds.** `/sys/devices/platform/82000000.ramoops_region` appears,
  `/proc/mounts` shows pstore mounted, and
  `cat /sys/module/ramoops/parameters/mem_address` = 2181038080 (0x82000000),
  `console_size` = 1048576. So our region wins over Motorola's.
- **Discovery: the device ALREADY has `ae000000.ramoops_region`**, which does
  not appear in the base dtb — it comes from the **dtbo overlay**. That is why
  grepping vb/dtb for "ramoops" found nothing. It evidently has no console
  buffer, since pstore was empty long before we touched anything.
- **But no records persist.** After a clean TWRP -> `adb reboot recovery` ->
  TWRP cycle, `/sys/fs/pstore` is still empty. 0x82000000 sits just past where
  the bootloader loads the ramdisk (0x81000000, 8MB) and dtb (0x81f00000), so
  the region is very likely being clobbered between boots.
- **Moving it to 0xa8000000 BRICKED the boot** (no USB at all, needed a
  power-cycle and a vendor_boot reflash). That address is inside the big
  unreserved gap in the base dtb but evidently overlaps something the **dtbo**
  overlay defines — remember the base dtb is NOT the whole picture.

### FINAL VERDICT ON RAMOOPS: the hardware supports it, the platform defeats it

Do not spend more time here without new information. Everything checks out and
it still produces nothing:

```
CONFIG_PSTORE=y  CONFIG_PSTORE_RAM=y  CONFIG_PSTORE_CONSOLE=y  CONFIG_PSTORE_PMSG=y
/sys/devices/platform/ae000000.ramoops_region   <- Motorola's, binds fine
/sys/module/ramoops/parameters/mem_address  = 2919235584 (0xae000000)
                                 mem_size   = 393216  (384K)
                                 console_size = 262144 (256K)
                                 pmsg_size  = 0        <- no /dev/pmsg0
/proc/mounts: pstore /sys/fs/pstore pstore rw
```

`/sys/fs/pstore` is **empty after every reboot**, including a clean warm
`adb reboot recovery` from TWRP into TWRP. The console buffer is configured and
the driver is bound, so the region is being **zeroed on every boot** — almost
certainly by Motorola's ABL, which injected and owns it. Adding our own node at
0x82000000 also produced nothing (that address is clobbered by the bootloader's
ramdisk/dtb load), and 0xa8000000 killed the boot outright.

Net: **there is no kernel log available on this device by any route we found** —
no pstore, no `/proc/last_kmsg`, empty `kpan` and `ramdump` partitions, and
`androidboot.console=0` with `Kernel console : null`. Only the *bootloader's*
own log (`logfs`) is readable, and it only proves the handoff to the kernel
succeeds.

### Superseded ideas for getting logs

1. ~~Dump the dtbo overlay to find the real free memory map.~~ **DONE — and the
   answer is that no static map exists.** Stock `dtbo.img` is a DTBO container
   with **11 overlays** (extract: magic `d7b7ab1e`, 32-byte table entries at
   offset 32, each `(size, offset)` big-endian). Decompiled them all: **`ramoops`
   appears in NONE of them, and not in the base dtb either.** So
   `ae000000.ramoops_region` is injected into the DT **by the bootloader at
   runtime** (Qualcomm ABL does this).

   Consequence: the reserved-memory list in the base dtb is NOT the real memory
   map, which is exactly why 0xa8000000 looked free and still killed the boot.
   Any future address must be validated on-device (read `/proc/iomem` and
   `/sys/firmware/devicetree/base/reserved-memory/` from TWRP), not from the dtb.
2. Reuse Motorola's existing `0xae000000` region instead of adding one: drop our
   DT node and pass ramoops module params on the cmdline
   (`ramoops.mem_address=0xae000000 ramoops.mem_size=... ramoops.console_size=0x100000`)
   via `BOARD_KERNEL_CMDLINE`.
3. `pmsg`/`record` buffers instead of `console` if console capture is the issue.

### Safety note

Every dtb experiment risks a no-boot. Recovery is always: power ~20s, Volume
Down + Power to reach the bootloader, then reflash a known-good vendor_boot
(or `./restore-stock.sh --full`). The **TWRP boot test** (`fastboot reboot
recovery`) is a 30-second check of whether a vendor_boot/dtb is viable — use it
before every full boot attempt.

#### Honest architectural doubt — read this before grinding further

Our build diverges from **every** working reference in the same direction:

| | zeekr (official, boots) | ours |
|---|---|---|
| kernel | built from source | **prebuilt GKI Image from stock** |
| vendor_boot | built | **stock, unmodified** |
| vendor_dlkm | built | **stock image reused** |
| system_dlkm | built | **stock image reused** |
| sepolicy | ~40 .te + genfs_contexts | **none at all** |

The "reuse Motorola's binaries, build only the Android side" shortcut is what
made a build possible in a day, but no shipping LineageOS device does it. The
remaining bug may not be a single missing flag — it may be that first-stage init
from a LineageOS `init_boot` cannot be driven by a stock vendor_ramdisk whose
`modules.load`, dtb and first-stage layout were authored for Motorola's own
init. Note this is NOT contradicted by "stock super boots": in that case every
piece downstream of init was also Motorola's.

Before spending more cycles on flags, seriously consider doing what zeekr does:
build `vendor_boot` (and `vendor_dlkm`) from the modules we already have
extracted in `~/android/firmware/W1UXS36H/images/` + `vb/fs/lib/modules/`
(288 .ko files and a `modules.load` are already unpacked in the scratchpad).

#### What is left

The only remaining difference between the booting case and the failing case is
the *content* of our images, and the failure is in first-stage init but not in
the mount. Candidates not yet examined:
- AVB handling per-partition in fs_mgr despite flags 3 — instrument or compare
  `avbtool info_image` footers of ours vs stock's `*_a.img` side by side
  (ours use **sha1** hashtrees; check what stock uses).
- super metadata slot semantics: ours is written by `lpmake --metadata-slots 3`;
  verify with `lpdump` that slot 0 (used for boot slot _a) is populated the same
  way stock's is. Stock's lpdump prints a `Slot 0:` header; ours did not.
- Whether first-stage init needs `vendor_dlkm`/`system_dlkm` AVB descriptors
  that our vbmeta lacks (stock super booted without them, which argues against,
  but stock's dlkm images carry Motorola's own footers).

#### SUPERSEDED (kept for the reasoning): the indicator retraction

I used `blkid /dev/block/by-name/metadata` reporting "no fs signature" as proof
that first-stage init died before reaching the metadata fstab entry. **That was
a false negative.** TWRP already has `/metadata` mounted (`/dev/block/sde9` on
`/metadata`, f2fs), so `blkid` cannot probe it, and the f2fs magic IS present:

```sh
adb shell 'dd if=/dev/block/by-name/metadata bs=1 skip=1024 count=4 | od -An -tx1'
# -> 10 20 f5 f2   = 0xF2F52010, the f2fs superblock magic
adb shell 'cat /proc/mounts | grep metadata'
adb shell 'ls /metadata'   # apex/ aconfig/ vold/ bootstat/ ota/ ... populated
```

So there is no evidence first-stage mount fails, and the conclusion "init dies
on the logical partitions" is withdrawn. Do not trust that indicator.

#### CONFOUND WARNING for mixed supers

A mix of our partitions with stock's is not always a valid Android. Stock
Motorola `system` paired with LineageOS `system_ext`/`product` is a genuinely
invalid combination — those three are built together and expect each other — so
a failure there may mean nothing. LineageOS `system` on stock `vendor` IS a
valid Treble pairing and is meaningful. Weigh each mix before believing it.

#### Bisect results so far (by BOOT BEHAVIOUR, which is trustworthy)

| super contents | result |
|---|---|
| all stock | **BOOTS** (with our boot/init_boot/vbmeta) |
| all ours | fails |
| ours system+system_ext+product, stock vendor | fails (meaningful: valid Treble pair) |
| ours system_ext+product, stock system+vendor | fails (CONFOUNDED, see above) |

#### Our system image is structurally fine

Checked in the staging tree `out/target/product/arcfox/system/`:
`bin/init` present (2,708,528 bytes), `etc/init/hw/init.rc` present (59,871),
36 APEX files. Not a missing-file problem. Note they are `.capex` (compressed
APEX), which are decompressed into `/data/apex/decompressed` at first boot —
so a `/data` that cannot be mounted would break apexd. `/metadata/vold` now
holds STOCK's metadata-encryption keys (recreated during stock's boot at 11:00)
while `userdata` is erased; that pairing is worth re-checking.

### >>> RESUME EXACTLY HERE <<<

Everything is flashed and current on slot A: boot, init_boot, super (with dlkm
+ the fstab fix), vbmeta, vbmeta_system. TWRP 4.3.2 is on the recovery
partition. `metadata` and `userdata` are erased.

**Status: hangs at the Motorola logo, eventually resets to the bootloader.**
Bootloader hands off to the kernel cleanly (proven from `logfs`), so the failure
is kernel/init stage.

#### The two prime suspects, in order

**1. SELinux policy load failure — TESTED AND RULED OUT (2026-08-07).**
`BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive` was added, boot.img
rebuilt and flashed. The flag **did** reach the kernel — verified by finding
`selinux=permissive` in the bootargs line of the resulting `logfs` log
(`Log69.txt`), so this was a valid test and not a silently dropped flag.

**It still hung at the Motorola logo.** SELinux is NOT the cause.

We do still ship zero device sepolicy, which will cause denials and broken
functionality later, but it is not what blocks boot. The
`BOARD_KERNEL_CMDLINE` line is diagnostic only — remove it.

**2. Stock `vendor_boot` paired with our init.** We ship stock vendor_boot
unmodified; it carries `/first_stage_ramdisk/fstab.qcom`, the GSI AVB keys and
the first-stage kernel modules, all built for Motorola's own ramdisk. zeekr
BUILDS its vendor_boot (`BOARD_MOVE_GSI_AVB_KEYS_TO_VENDOR_BOOT := true`).
Building ours would also let us set bootconfig directly, which is a more
reliable way to inject `androidboot.selinux=permissive` than boot.img cmdline.

#### Method that actually works — use it instead of guessing

Every real bug this session was found by **comparing our artifact against stock
or against zeekr**, never by theorising:

| Bug | Found by |
|---|---|
| recovery `kernel_size` non-zero | `unpack_bootimg` diff vs stock recovery |
| `init_boot` header v0 | `unpack_bootimg` diff vs stock init_boot |
| super missing vendor_dlkm/system_dlkm | reading stock's first-stage fstab |
| `vbmeta_system` never built | zeekr's BoardConfigCommon |
| `/vendor/etc/fstab.qcom` not installed | `ls` on the mounted vendor from TWRP |

Blind theories that cost cycles and were all WRONG: vbmeta signing (twice),
recovery init filename, wrong USB controller name.

#### Escape hatch

`./restore-stock.sh --full` — needs `--full` now, because our super has
overwritten stock's system partitions.

If the phone loops into recovery: `misc` is write-protected over fastboot, so
flash stock recovery, boot it to the "No command" screen, hold **Power** + tap
**Volume Up** for the menu, and pick **"Reboot system now"** — that is the only
thing that clears the BCB.

**`init_boot` was, before this fix, genuinely unsolved.** It is refused by the bootloader
every single time ("Preflash validation failed" / "Command failed") while
stock's flashes fine. On GKI, init_boot holds the generic ramdisk with
first-stage init, so running our system under stock's init is a real mismatch
and a plausible boot blocker independent of vbmeta. Worth investigating:
compare `unpack_bootimg` output for ours vs stock (header version, page size,
os_version/patch_level), the same class of structural diff that solved recovery.

Reaching the bootloader from our recovery: hold **Power ~20s** until both
displays go dark, then **Volume Down + Power**. Do NOT use recovery's
"Enter fastboot" — that is fastbootd.

### Fallback that does not require fixing our recovery at all

Installing the ROM does not need OUR recovery — it needs ANY recovery that can
`adb sideload`. The OrangeFox/PBRP/TWRP arcfox images
(`customrecoverymaker.com`, linked from the XDA recovery thread) are proven on
this device. Flashing one to `recovery` also buys a **root shell in recovery**,
which ends the no-logs problem permanently. Consider doing this FIRST next time.

### `misc` is write-protected — the BCB trap has no fastboot escape

Both `fastboot erase misc` and `fastboot flash misc <zeros>` are refused
(`flash permission denied`) even with the bootloader unlocked. So after any
`fastboot reboot recovery`, the only way out of the recovery loop is:

1. `./restore-stock.sh` (puts stock recovery back)
2. Let it boot — it lands on stock recovery's **"No command"** screen
3. Hold **Power**, tap **Volume Up**, release → recovery menu
4. **"Reboot system now"** — stock recovery clears the BCB in `finish_recovery()`

Confirmed working 2026-08-07. Note `adb reboot` does NOT clear it; it must be
the menu exit. Also confirmed: **stock recovery enumerates on USB** and shows up
as `<device-serial> recovery`, but its adbd is sideload-only — `adb shell` aborts
with a SELinux error, so no shell there.

## What was already proven on hardware

- Our recovery **boots and renders** on the inner display
- Version string reads **LineageOS Recovery 23.2 (20260807)** = our build
- Cover display shows the Motorola splash (recovery does not drive panel 2 —
  expected, not a bug)
- **Touch does not work** in recovery (no touch HAL — expected; use Vol/Power)

## The fix that made recovery boot at all

Two flash attempts failed with **"No valid operating system found"**. Cause was
NOT vbmeta (I wasted both attempts on that theory). It was a structural defect:

```
              kernel_size    ramdisk     os_version
stock         0              19243852    None
ours (bad)    35564032       16030315    16.0.0
ours (fixed)  0              16030330    None
```

arcfox's recovery partition holds a **ramdisk only**; the kernel comes from
`boot`. Fixed in `sm8635-common/BoardConfigCommon.mk`:

```make
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true
BOARD_RECOVERY_MKBOOTIMG_ARGS += --header_version 4 --os_version 0 --os_patch_level 0
BOARD_AVB_RECOVERY_ADD_HASH_FOOTER_ARGS += --partition_size 134217728
```

This matches `bidbuddyai/device_motorola_arcfox` (working TWRP tree), commit
"match GKI stock recovery header".

## Flashing rules learned the hard way

- **DO NOT flash our vbmeta.** Signed with the AOSP test key; Motorola's
  bootloader rejects it. Result: "No valid operating system found".
- **DO NOT hand-patch stock vbmeta flags either.** Patching byte 120 changes
  bytes the signature covers. Also failed.
- **Leave vbmeta alone entirely.** No arcfox XDA thread touches it. Custom
  kernels and recoveries flash and boot with stock vbmeta intact.
- `init_boot` is **always** rejected by fastboot ("Preflash validation failed")
  for our images; stock flashes fine. Let the OTA write it instead — it is in
  `META/ab_partitions.txt`.
- If recovery will not load, XDA says: `fastboot erase all` (wipes userdata).
  NOT YET TRIED.

## Reading XDA (it 403s WebFetch and headless browsers)

Real Chromium with a desktop UA gets through:

```sh
chromium --headless=new --disable-gpu --no-sandbox --virtual-time-budget=15000 \
  --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36" \
  --dump-dom "<url>" > page.html
```

Spoiler content is present in the DOM (CSS-hidden), so no clicking needed.

Key threads:
- Recovery: `xdaforums.com/t/recovery-unofficial-orangefox-pbrp-twrp-motorola-razr-2024-arcfox.4685914/`
- Custom kernel (proves custom boot images work): `.../kernelsu-next-formally-wildksu-ksu-gki-susfs-kernel-updated.4790094/`
- Forum index: `xdaforums.com/f/motorola-razr-50-aka-razr-2024-50-ultra.12863/`
- **There is no ROM thread for arcfox.** Nobody has shipped one. This would be first.

## Scripts in this repo

| Script | Purpose |
|---|---|
| `restore-stock.sh` | Restore stock boot chain from the Windows firmware. **The escape hatch.** `--full` also reflashes super. |
| `build-loop.sh` | Build, auto-fix `undefined module` + `check_elf_file`, stop on anything else |
| `resolve-build-blobs.sh` | Add missing blobs from the firmware dump |
| `fix-checkelf.sh` | Annotate `;DISABLE_CHECKELF` |
| `extract-firmware.sh` | Unpack the RSA firmware package (sparsechunk order matters!) |
| `build-blob-manifest.sh` / `split-manifest.sh` | Generate/tier the blob manifests |
| `capture-contract.sh` | Capture fold/display/sensor state (`open`/`half`/`closed`/`tent`) |
| `preflight.sh` | Check a machine can build |
| `scrub-check.sh` | Find serial/IMEI before publishing anything |

## Build incantation

```sh
cd ~/android/arcfox
unset -f grep                 # Claude Code's grep shim breaks AOSP lunch
source build/envsetup.sh
breakfast arcfox
export LC_ALL=C USE_CCACHE=1
mka bacon                     # or: mka recoveryimage
```

## Still untested / known compromises

- ROM has **never been installed or booted**. Only recovery has run.
- ~10 blobs carry `;DISABLE_CHECKELF`; peridot fixes several properly with
  `.add_needed('libbinder_shim.so')`. Runtime behaviour unknown.
- Kernel UAPI headers come from LineageOS's **Xiaomi** SM8635 kernel (6.1.174),
  not Motorola's (6.1.145).
- `vendor_boot`, `vendor_dlkm`, `system_dlkm`, `dtbo` are not built — stock
  retained deliberately (prebuilt GKI kernel + stock modules).
- `BOARD_SUPER_PARTITION_SIZE` never cross-checked against the device
  (`/sys/class/block` is SELinux-denied to shell).
- The fold config is compiled in but has never run in Android.

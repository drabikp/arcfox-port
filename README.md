# arcfox — LineageOS 23.2 for the Motorola razr 50 ultra

An unofficial LineageOS 23.2 (Android 16) port for **arcfox** — Motorola razr 50
ultra / razr+ 2024, SM8635 (Snapdragon 8s Gen 3).

This repository holds the parts of the port that are not source trees: the
`repo` local manifest that assembles the tree, the scripts that build the kernel
and resolve vendor blobs, the out-of-tree patches, the flashing runbook, and the
engineering notes.

> **No proprietary blobs are published here.** Everything under
> `vendor/motorola/` is extracted from a Motorola firmware package you supply.
> See [Blobs](#4-blobs) below.

---

## What works

Verified on a flashed build, cold-booted:

| | |
|---|---|
| Telephony | VoLTE (calls stay on IMS, no SRVCC), VoWiFi, mobile data, SMS, emergency calling |
| Display | both panels (inner 1080x2640 + cover), per-display cutouts, posture-driven routing |
| Input | both touchscreens, double-tap-to-wake on each |
| Camera | 8 cameras, API1 and API2, video recording |
| Sensors | 79 sensors, all fold postures commit |
| Power | reverse wireless charging (power share) |
| Other | WiFi, Bluetooth (incl. LHDC v5), NFC, fingerprint, face unlock (class 1) |

Known limitations, each root-caused and documented in `docs/HANDOFF-NEXT.md`:
thermal profile switching is inert (needs a Motorola framework client that does
not exist on AOSP), face unlock can never do payments (2D RGB sensor — stock is
identical), and the telephoto lens has no OIS.

---

## Building from a clean checkout

Tested on Arch/Manjaro with 16 GB+ RAM and ~400 GB free.

### 1. Sync the tree

```bash
mkdir -p ~/android/arcfox && cd ~/android/arcfox
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs
mkdir -p .repo/local_manifests

git clone https://github.com/drabikp/arcfox-port.git
cp arcfox-port/local_manifest/arcfox.xml .repo/local_manifests/

repo sync -c -j8
```

`local_manifest/arcfox.xml` replaces nine LineageOS/AOSP projects with forks
carrying the arcfox changes, and adds the device, kernel and techpack trees.
Each fork's branch holds only the arcfox commits on top of upstream.

### 2. Assemble the kernel module tree

Motorola publishes no `display-drivers` for this train, and its `qcacld-3.0`
does not build. Both are taken from LineageOS's Xiaomi sm8635-modules tree
(synced by the manifest) and patched from `patches/`:

```bash
./arcfox-port/scripts/setup-kernel-repos.sh
cp arcfox-port/kernel-modules-root/Android.{bp,mk} kernel/motorola/sm8635-modules/
```

The root `Android.mk` is deliberately empty — it stops `kati` descending into
the techpack DLKM wrappers, which are built out of tree by
`vendor/lineage/build/tasks/kernel.mk`.

### 3. Firmware

Get a stock firmware package for the **W1UXS36H.72-45-10-7** train. Motorola's
Rescue and Smart Assistant downloads one to flash it and leaves it on disk under
`ProgramData/RSA/Download/RomFiles/`. Then:

```bash
./arcfox-port/scripts/extract-firmware.sh <romfiles-dir> ~/android/firmware/W1UXS36H
```

Needs `android-tools` (simg2img, lpunpack) and `erofs-utils` (fsck.erofs).

### 4. Blobs

```bash
cd device/motorola/sm8635-common && ./extract-files.py ~/android/firmware/W1UXS36H/extracted
cd ../arcfox                     && ./extract-files.py ~/android/firmware/W1UXS36H/extracted
cd ../sm8635-common              && ./fix-vendor-blobs.sh
```

`fix-vendor-blobs.sh` is not optional and must be re-run after every
extraction: `extract-files.py` rewrites `vendor/motorola/` from scratch, so
every manual blob fix lives in that script rather than loose in the tree.

### 5. Build

```bash
source build/envsetup.sh
breakfast arcfox
brunch arcfox
```

Use `breakfast`, never a hand-written `lunch` target — a guessed
`lunch lineage_arcfox-bp2a-userdebug` silently drops ~1400 release-config flag
overrides and ships a year-stale security patch string. `breakfast` resolves
the correct `bp4a` release config.

Output: `out/target/product/arcfox/lineage-23.2-<date>-UNOFFICIAL-arcfox.zip`.

---

## Flashing

Read **[FLASHING.md](FLASHING.md)** before touching the device. Two rules that
cost real time here:

- **`fastbootd` cannot open `super` on arcfox.** Every logical-partition flash
  and even `getvar partition-size:super` fails there, while the same command
  from the bootloader succeeds. Use the bootloader, always.
- **`fastboot -w` is not optional.** Skipping the userdata wipe to preserve
  `/data` bootloops with `init_user0_failed`.

---

## Layout

| Path | Contents |
|---|---|
| `local_manifest/arcfox.xml` | the `repo` manifest that assembles the whole tree |
| `scripts/` | kernel assembly, firmware extraction, blob resolution, build and boot-test helpers |
| `patches/` | out-of-tree patches for display-drivers, wlan and camera-kernel |
| `kernel-modules-root/` | the `Android.bp`/`Android.mk` stubs for `sm8635-modules/` |
| `FLASHING.md` | flashing runbook |
| `docs/` | engineering notes: root causes, measurements, and what was deliberately left alone |

`docs/HANDOFF-NEXT.md` is the working record and supersedes `docs/HANDOFF.md`
on strategy. Both are long and written for whoever picks the port up next.

---

## Notes

Device identifiers (serial, per-unit MAC addresses) have been redacted from
these docs; `AA:BB:CC:DD:EE:0x` are placeholders. `00:03:7F:12:34:56` is
Qualcomm's public board-data default and is left as-is because it is load
bearing in the WLAN discussion.

Unofficial build, signed with the AOSP test keys. Not affiliated with or
endorsed by Motorola, Qualcomm or the LineageOS project.

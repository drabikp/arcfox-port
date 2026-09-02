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

**Known gap versus stock**, root-caused in `docs/HANDOFF-NEXT.md` §0.38:
**thermal profile switching does not happen.**

What that means in practice:

- **Thermal protection still works.** The phone throttles and protects itself
  normally — the default thermal profile is loaded and active at all times, and
  the temperature at which the system reports SEVERE is unchanged. This is not a
  safety or overheating issue.
- **What is missing is stock's per-situation tuning.** Motorola ships eight
  thermal profiles (camera, gaming, cover display, performance…) and switches
  between them as you use the phone. We ship all eight files byte-identical to
  stock, but only the default one is ever loaded, because the component that
  selects a profile is a Motorola framework patch that does not exist on AOSP.
- **The practical effect is throttling slightly sooner in heavy use.** In
  stock's own numbers, its camera profile defers the first CPU mitigation from
  40°C to 42°C; on this build the default profile applies instead, so during
  sustained camera or game use the phone starts easing off a little earlier than
  stock would. Expect marginally lower sustained performance under long heavy
  load — not a difference you are likely to notice in ordinary use.

It is documented as unfixable rather than unfixed: the profile selector is
reached only through a Motorola-private interface (`motorola.hardware.sxf`)
whose callers on stock are Motorola's patched `system_server` and `mediaserver`.
On LineageOS those are AOSP binaries and will never call it, so shipping the HAL
would start a service that nothing ever talks to.

**USB modes.** File transfer (MTP), PTP and USB tethering over NCM all work.
Verified on a flashed build against the host USB descriptor:

| Mode | Status | Evidence |
|---|---|---|
| File transfer (MTP) | works | interface class 6, PID `0x2e76`, `mtp-detect` opens a real session and enumerates storage |
| PTP | works | interface class 6, PID `0x2e84` |
| Tethering (NCM) | works | class 2 + class 10 CDC, host network interface comes up |
| Tethering (RNDIS) | **does not apply** | see below |
| Webcam (UVC) | **not supported** | see below |

**RNDIS tethering does not apply.** `init.mmi.usb.rc` rewrites `rndis,adb` into
`rndis,${persist.vendor.usb.config.extra},adb`, and only `rndis,none,adb` has a
handler — so with that property unset the string becomes `rndis,,adb` and matches
nothing. Setting `persist.vendor.usb.config.extra=none` in `vendor.prop` should
close it; that is identified but **not yet built or tested**. Not urgent: AOSP
prefers NCM for USB tethering and NCM works.

**USB webcam (UVC) is not supported, and is not supported on stock either.**
There is no `uvc` composition anywhere in Motorola's `init.mmi.usb.rc` (only an
unrelated `rndis,webcam` entry) and neither stock nor this build sets
`ro.usb.uvc.enabled`. The gadget does expose a `uvc.0` function, so adding a
composition plus the enable property would likely work — but that is **new
functionality beyond stock**, not a regression, and it has deliberately not been
attempted.

**Not port limitations — hardware behaviour, identical on stock:**

- The telephoto camera has **no OIS**, so a zoomed *photo* preview shakes. EIS
  is video-only. Nothing in software can change this.
- Face unlock is **Class 1 (convenience)** and cannot authorise payments: the
  sensor is a 2D RGB camera and the stock HAL declares the same class.
- Reverse wireless charging works, but the phone will not transmit while it is
  itself charging over USB.
- "100% but still charging" is correct: this is a dual-cell battery, and the
  flip cell terminates before the main cell finishes its constant-voltage phase.

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

- **Installing a downloaded build?** → **[INSTALL-RELEASE.md](INSTALL-RELEASE.md)**
  — prerequisites and the whole procedure, no build tree needed.
- **Installing what you just built, or returning to stock?** →
  [INSTALL.md](INSTALL.md)
- **Want the rules and the reasoning?** → [FLASHING.md](FLASHING.md)

⚠️ The install has only been tested onto stock **W1UXS36H.72-45-10-7**. The
package writes 11 partitions and none of them are firmware — the modem,
bootloader, DSP and Bluetooth firmware stay whatever the phone already has, and
the vendor blobs were extracted from that train.

Two rules that cost real time here:

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
| `INSTALL-RELEASE.md` | installing a downloaded build (start here as a user) |
| `INSTALL.md` | installing your own build, and returning to stock |
| `FLASHING.md` | developer runbook: the rules and why each exists |
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

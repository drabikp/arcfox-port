# Changelog

Public builds of LineageOS 23.2 for the Motorola razr 50 ultra (arcfox).
Dates are build dates; each build is a full package, installed by sideload.

Checksums for every release are in the download folder, and the install and
update procedures are in [INSTALL-RELEASE.md](INSTALL-RELEASE.md).

---

## 20260926

Third public release. Updating from 20260915 is a normal sideload
([INSTALL-RELEASE.md](INSTALL-RELEASE.md)); from 20260902 use the dedicated route.

**Built 2026-09-27 from a clean tree** (`rm -rf out`, no ccache, pinned
manifest, published bootstrap scripts); SHA-256
`a681c17e9ca9ab687376a66bde00eaf8799f15fdfc7a07b1648918329040f693`.
The package first produced on 2026-09-26 by the incremental build tree was
never uploaded: comparing it with the clean build showed ~130 stale files
that the sources no longer produce (60 GKI modules from an older kernel build
duplicated into `vendor_dlkm`, flat leftovers in `system_dlkm`, two unused
wlan modules in the `vendor_boot` ramdisk, one duplicated system library).
9576 of the 10470 packaged files are byte-identical between the two; every
other difference is a build date, signature, salt or the kernel git hash.
The clean package passed two cold boots (eSIM enumeration, LTE data on the
eSIM, Wi-Fi, NFC, OMAPI, adb, zero tombstones).

Reproducibility fixes found by that rebuild, all pushed: `setup-kernel-repos.sh`
applied none of its patches (wrong path), the local manifest dropped LineageOS's
`hardware/qcom-caf` namespace linkfiles, and the device tree built the wlan
module before the `dataipa` symbols it links against (only an incremental tree
hid it).

### Fixed

- **eSIM works, without Google apps.** The eUICC is detected, the pre-installed
  LPA runs GMS-free, profiles enumerate at boot, a QR download from an SM-DP+
  completes, profiles can be enabled/switched (two at once — the eUICC supports
  MEP), and mobile data attaches on the eSIM. Previously the eSIM list came up
  empty for the first ~4 minutes after every boot and downloads failed.
- **Root cause of that eSIM outage removed.** The QTI secure-element HAL's `eSE1`
  instance never manages to open the embedded secure element on this build and
  "recovers" by cold-resetting it through the NFC controller; the same chip
  carries the eUICC, so the modem lost the card for ~258 s after every boot.
  Nothing on this build uses `eSE1` (the Thales StrongBox/weaver clients are not
  shipped), so it is no longer declared and the HAL is not started. SIM OMAPI
  terminals are unaffected (they are served by the RIL), and NFC is unchanged.
  Details and evidence: the device tree's `fix-vendor-blobs.sh` (fixups 6/7) and
  the port's `ESIM-FINDINGS.md`.
- **eSIM list survives a late card.** The framework re-enumerates embedded
  subscriptions when the eUICC reaches LOADED and retries with a bounded
  back-off, so a slow card no longer leaves the list empty until reboot.
- **eSIM wizard follows dark theme.** Google's LPA asks the (absent, GApps-only)
  SetupWizard partner provider whether to use day/night; a small provider now
  answers, and yields to the real one when GApps are installed.
- **Motorola's eSE restart trigger no longer denied by SELinux** (`vendor.ese.*`
  property grant for `vendor_init`).

### Verified this cycle

- Two cold boots of the release image: eSIM enumeration within 0.3 s of the SIM
  loading, zero slot-2 wedge signatures, SIM1/SIM2 OMAPI connected, NFC on, LTE
  data validated on the eSIM, USB debugging persistent, no tombstones.
- End-to-end eSIM download and activation of a Truphone/1Global profile on this
  build; roaming data on LTE.
- Kernel history was rewritten (commit messages only, trees identical) before
  the clean build; the image's `uname -r` suffix `-g770a722b9ca7` is the current
  `arcfox-ack-merge` head.

### Known issues

- No `eSE1` (embedded secure element) OMAPI reader: StrongBox-backed keys and
  off-host card emulation on the eSE are not available. Payments via HCE are
  unaffected.
- Rarely a boot comes up with the cover panel not enumerated (bootloader logo on
  the cover, inner display fine). A reboot clears it.
- Occasionally USB comes up MTP-only after a reboot, with no adb.

---

## 20260915

Second public release. Updating from 20260902 needs the
[dedicated route](INSTALL-RELEASE.md#from-20260902--read-this-first) because
that build left the running slot without a bootable recovery.

### Fixed

- **Updates write the new slot's recovery.** The A/B payload now carries
  `recovery` and `vbmeta_system`, so after an update the slot you boot from has
  the matching recovery. Reported on XDA against 20260902.
- **Recovery boots on our own kernel chain.** `vendor_boot` staged only the 99
  modules a normal boot needs, while recovery's list asks for 277, so first-stage
  init died before recovery appeared. It now stages the union, 282 modules, as
  stock does. Before this fix, recovery had only ever been exercised on top of
  stock's boot chain.
- **Off-mode charging no longer ends in the bootloader.** A bring-up logging
  script had shipped in the release image and rebooted the phone after a few
  minutes on the charger.
- **USB debugging follows official semantics.** Off by default, and the toggle
  survives reboots. Motorola's own property trigger used to re-blank the USB
  config after early boot, which turned the setting off again.
- **Add-on packages fit.** The images shipped completely full, so MindTheGapps could not
  install. Both now reserve headroom like official LineageOS builds.

### Foldable behaviour

- **Opening the phone wakes it.** The device-state table carried no wake trigger,
  so unfolding left the inner display black until a button press. Stock does this
  from private code.
- **Fold-with-an-app-open setting**, with the same three choices as official
  foldables: always continue on the cover, swipe up to continue, or never.
- **Cover display keeps content clear of the camera lenses.** The keyboard, the
  dock and the lock screen's hint text and lock icon sit above them, and in
  landscape the strip beside the lenses is left free, following the same 297 px
  rule stock uses. The camera block is deliberately *not* declared as a display
  cutout; that approach cost usable screen area and broke scrolling.
- **Cover app drawer at full size.** It was being scaled down to the workspace's
  fit scale, which made icons and labels tiny.
- **Clock widget matches on both displays.** The widget now auto-sizes to the box
  the launcher gives it and keeps the clock and date together, so the date is no
  longer clipped and the size no longer flips between panels.

### Verified this cycle

- Double-tap-to-wake runs in the touch controller's firmware gesture mode, the
  same mechanism stock uses. See [docs/DT2W.md](docs/DT2W.md).
- The 20260902 update route was run end to end on a phone staged to match that
  build's partition state.
- The port walked against the LineageOS device support requirements. Results and
  the remaining work are in [docs/OFFICIAL-CHECKLIST.md](docs/OFFICIAL-CHECKLIST.md).

### Known issues

- Rarely a boot comes up with the cover panel not enumerated, so it keeps showing
  the bootloader logo while the inner display works. A reboot clears it.
- Occasionally USB comes up MTP-only after a reboot, with no adb.

---

## 20260902

First public release.

- Both displays with per-panel cutouts, corners and posture maps, both
  touchscreens, and all fold postures.
- Telephony including VoLTE and VoWiFi, mobile data, SMS, emergency calling.
- All three cameras on Camera API1 and API2, with video stabilisation
  (Vidhance nodes, EIS on).
- WiFi built from source: the wlan subtree comes from LineageOS and carries
  Motorola's bootarg factory-MAC parser, so the phone keeps its own MAC.
- Kernel 6.1.145 built from source rather than shipped as a prebuilt, with the
  modules partitioned across `system_dlkm` and `vendor_dlkm`.
- Bluetooth, NFC, fingerprint, face unlock, sensors.
- Reverse wireless charging (power share).
- Double-tap-to-wake on both panels.
- MTP, PTP and USB tethering.

Known problems in this build, all fixed in 20260915: reboot-to-recovery does not
work after installing, so GApps cannot be added; off-mode charging ends in the
bootloader; USB debugging is on out of the box.

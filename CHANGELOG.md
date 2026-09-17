# Changelog

Public builds of LineageOS 23.2 for the Motorola razr 50 ultra (arcfox).
Dates are build dates; each build is a full package, installed by sideload.

Checksums for every release are in the download folder, and the install and
update procedures are in [INSTALL-RELEASE.md](INSTALL-RELEASE.md).

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

# Changelog

Public builds of LineageOS 23.2 for the Motorola razr 50 ultra (arcfox).
Dates are build dates; each build is a full package, installed by sideload.

Checksums for every release are in the download folder, and the install and
update procedures are in [INSTALL-RELEASE.md](INSTALL-RELEASE.md).

---

## 20261014

Fifth public release. Updating from 20260915 or newer is a normal sideload
([INSTALL-RELEASE.md](INSTALL-RELEASE.md)); from 20260902 use the dedicated route.

**Built 2026-10-14 from a clean tree** (`rm -rf out`, pinned manifest
`manifest-20261014-pinned.xml`); SHA-256
`214f0c600c20c55a6df0a0a5ba13bb972526c3fb33398736f03fe234e2551b53`.
The download folder now also holds the build's own **`init_boot.img`**, for
rooting with Magisk; see [Root with Magisk](INSTALL-RELEASE.md#root-with-magisk).

### Fixed

- **Cover display missing after boot, and the crash loop it caused.** Now and
  then a boot left the cover panel on the bootloader logo. With the phone
  closed the cover is display 0, so WindowManager refused to remove it ("Can't
  remove the primary display") and `system_server` crashed every few seconds
  until the phone was opened; one bugreport from the field had 49 crashes in 8
  minutes. The bad boot that could be captured with full logs was a start-up race:
  SurfaceFlinger processes the queued display hotplug events before its
  scheduler exists, and an event arriving in the few milliseconds between the
  two was queued and never processed. The field report had no start-up log, so
  its cause is likely the same but unconfirmed. Those events are now
  processed once the scheduler is up (`frameworks/native` fork). A test build that
  forces the race on every boot proves the fix: the cover was missing on 3 of 3
  boots without it and present on 5 of 5 with it.
- **Media codec services crashing at boot.** Qualcomm's Codec2 services (the
  audio and video codecs) crashed within the first ~16 s of roughly a third of
  all boots, and took `mediaserver` down with them. On one boot it also reached
  `system_server` and restarted the whole UI. Cause: the stock
  services are Android 14 builds and allocate 264 bytes for an object that the
  Android 16 codec library constructs at 288, so the constructor overwrote the
  next heap block. `fix-vendor-blobs.sh` now patches one byte in each service
  binary so that it allocates 512 bytes, checks the result by hash, and checks
  that the built library still fits. After the fix there were no Codec2 crashes
  in 40 reboots; before it there were 6 in 10. Crash dumps from these services
  now work too: their sandbox used to kill the dumper.
- **Bluetooth music silent after an audio service restart.** AOSP's and
  Motorola's Bluetooth audio providers both registered under the same name.
  Cold boots worked, but after any restart of the audio HAL Bluetooth rebound to
  AOSP's provider, which the audio path does not use. Calls kept working while
  A2DP music was silent until Bluetooth was toggled. Only Motorola's provider
  ships now. Separately, if music over Bluetooth is silent on any build, check
  that *Developer options → Disable Bluetooth A2DP hardware offload* is off, and
  reboot after changing it. That option should break A2DP on stock as well:
  neither build ships the audio configuration it needs.
- **Screen recording on the hardware encoder.** Qualcomm's video platform
  specification files were never extracted. Without them the hardware video
  encoder loaded none of its input converters and rejected every frame of a
  screen recording: the Quick Settings recorder (which uses the HEVC encoder)
  saved no file at all. The files ship now.
- **Sensor and keystore features declared.** The gyroscope, light, proximity,
  step counter and step detector were in the sensor list, but the phone did not
  declare them as system features. The same was true of dynamic head-tracker
  support (for head-tracking headsets) and the hardware keystore (version 300).
  The Play Store and apps that check features first treated them as missing:
  step counters, for example. They are declared now, as on stock. Stock's files also declare a
  barometer, which this phone does not have; this build leaves it out.
- **Power share settings page.** The main switch was hidden under the action
  bar (Android 16 edge-to-edge layout).

### New

- **Open to answer, close to end.** As on stock: opening the phone answers a
  ringing call, closing it ends a call on the earpiece or declines a ringing one
  (speakerphone, headset and Bluetooth calls continue), and calls answered or
  placed on the cover display use the speakerphone. Switches:
  *Settings → System → Gestures → Flip phone calls*. The one deliberate
  difference from stock: closing the phone never ends an emergency call.
  Requested on XDA.
- **`init_boot.img` in the download folder**, for Magisk. Patch this one, not
  Motorola's stock `init_boot`.

### Verified this cycle

- The installed zip, sideloaded over the previous test build with data kept,
  then rebooted five times (six boots): no Codec2 service death and both Codec2
  stores registered on every boot, both panels enumerated, no `system_server`
  or audio HAL crash, Motorola's Bluetooth provider (8 A2DP offload
  capabilities) bound every time, no tombstones. The 40-reboot Codec2 figure
  above was measured with the same patched services on the test build.
- Screen recording from Quick Settings (HEVC hardware encoder): 882 frames in a
  16 s recording. The same test on the previous build saved no file at all.
  The `screenrecord` command on the AVC encoder: 354 frames in 3 s.
- The seven features are declared and no barometer is.
- Payload: 391 `vendor_dlkm` and 60 `system_dlkm` modules, every vermagic
  matching the kernel (`6.1.145-20325-g770a722b9ca7`); `recovery.img` and
  `init_boot.img` in the download folder byte-identical to the payload's.
- Security patch level unchanged: 2026-08-01 (platform), 2026-07-01 (vendor).
- Not re-tested on this build: open-to-answer / close-to-end (the test phone
  has no SIM; it was tested on real calls on 2026-10-04 with the same app), and
  the cover-display race (proven by the forced-race test build on 2026-10-05).
- New SELinux denial: the video codec service now reads
  `/sys/devices/soc0/subset_parts` and is denied. Qualcomm's own policy
  deliberately forbids that read for the service, and recording works.

### Known issues

- Occasionally USB comes up MTP-only after a reboot, with no adb.
- In a few percent of boots Qualcomm's audio service crashes within its first
  second and restarts on its own. The code is Motorola's and Qualcomm's,
  identical to stock, and since the Bluetooth fix above the restart no longer
  affects Bluetooth audio.
- Apple Lossless (ALAC) files fail in apps that use Android's built-in
  decoders; apps that bring their own decoder should be unaffected. Qualcomm's
  ALAC decoder expects the codec data from Qualcomm's own media parser. Stock
  ships that parser switched off on this chipset, and the official LineageOS
  builds for recent Qualcomm phones do not ship it at all, so this build keeps
  stock parity.
- The cover-display start-up race above is the only cause that has been proven.
  If the cover still stays on the logo after a boot, please send an
  `adb bugreport` taken before rebooting. If the UI keeps restarting with the
  phone closed, open the phone first (that stops the loop), then take it.
- The embedded secure element (eSE1), as in 20260926.

---

## 20260928

Fourth public release. Updating from 20260915 or newer is a normal sideload
([INSTALL-RELEASE.md](INSTALL-RELEASE.md)); from 20260902 use the dedicated route.

**Built 2026-09-28 from a clean tree** (`rm -rf out`, pinned manifest
`manifest-20260928-pinned.xml`); SHA-256
`e8ae1108f74cc9c5aec9c56c8e3afc87bde4a1799c80c141f079244df266cf45`.
The only source change since 20260926 is the device tree commit below.

### Fixed

- **Display no longer capped at 60 Hz.** The build left the framework's
  `config_defaultRefreshRate` at AOSP's 60 and `config_defaultPeakRefreshRate`
  at 0, so DisplayModeDirector cast a global 0–60 Hz render vote that nothing
  widened: both panels (24/30/60/90/120/165 Hz) scrolled at 60 Hz, and even a
  user `peak_refresh_rate` of 165 had no effect. The device tree now carries
  Motorola's own values from the stock vendor overlay (default 0, peak 120),
  which is also what stock Settings' default "High" mode writes.
- **Peak refresh rate setting.** Settings → Display → Peak refresh rate
  (LineageOS's list) is enabled: 120 Hz by default, up to 165 Hz selectable.
  The minimum refresh rate list stays hidden, since a minimum equal to the
  peak pins the panel at full rate.

### Verified this cycle

- The installed zip, sideloaded over 20260926 with data kept: inner display
  120 Hz while scrolling and 24 Hz idle; 165 selected in Settings gives
  165 Hz; cover display (folded) 120 Hz scrolling and 24 Hz idle.
- Payload: 391 `vendor_dlkm` and 60 `system_dlkm` modules, every vermagic
  matching the kernel (`6.1.145-20325-g770a722b9ca7`); recovery in the payload
  byte-identical to the published `recovery.img`.

### Known issues

- Unchanged from 20260926. Motorola-private refresh tuning (the cover panel's
  90 Hz dim-light zone, Gametime's 165 Hz) needs Motorola's framework and is
  not reproduced; the standard AOSP policy runs with stock's default values.

### Correction

- `manifest-20260926-pinned.xml` pinned `sm8635-common` at `949ec77`, one
  commit before the kernel-module ordering fix (`b0c06ae`) that the published
  20260926 package was built with; a rebuild from it failed in MODPOST. It now
  pins `b0c06ae`.

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
  unaffected. **This is settled, not a bug being chased.** The element gates
  access behind a Root of Trust the TEE re-establishes from factory-locked keys
  and the verified-boot state; that cannot be reproduced on an unlocked,
  self-signed build, and the Thales StrongBox stack that drives it is not
  functional on LineageOS userspace. No Motorola LineageOS tree ships it: the
  official razr 40 ultra and the sm8635 sibling both drop the eSE reader the same
  way and use TEE-backed keymint only. Investigated in depth; do not expect this
  to change.
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

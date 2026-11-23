# Changelog

Public builds of LineageOS for the Motorola razr 50 ultra (arcfox): LineageOS
24.0 (Android 17) from 20261122, LineageOS 23.2 (Android 16) before that.
Dates are build dates; each build is a full package, installed by sideload.

Checksums for every release are in the download folder, and the install and
update procedures are in [INSTALL-RELEASE.md](INSTALL-RELEASE.md).

---

## 20261122 (LineageOS 24.0, Android 17)

First LineageOS 24.0 release. Updating from 23.2 keeps your data; the tested
starting point is 23.2-20261014. If you use GApps, sideload **MindTheGapps 17**
right after the ROM, after rebooting to recovery and before the first boot.
MindTheGapps 16's installer refuses Android 17
([INSTALL-RELEASE.md](INSTALL-RELEASE.md#from-232-to-240),
[GAPPS.md](GAPPS.md)). There is no way back to 23.2 without wiping the phone.

**Built 2026-11-22 from a clean tree** (`rm -rf out`, compiler cache off, pinned
manifest `manifest-20261122-pinned.xml`); SHA-256
`f3991b24700fb2ceff0d797ac9a942c5f41b79e9d259f6de034608f7a047a02d`.
Security patch level **2026-11-01** (platform; 20261014 had 2026-08-01). The
vendor level stays 2026-07-01. That is the level of Motorola's vendor files
from stock W1UXS36H.72-45-10-7, which this build ships unchanged.

### New

- **Android 17**, on LineageOS 24.0.
- **Always-on display and ambient display**, on both panels. Stock sets the
  doze configuration that turns them on; earlier builds never did, so the
  option was missing. Requested on XDA.
- **Adaptive brightness on both panels.** It was never available before. The
  inner display uses the main light sensor with stock's brightness curve. The
  main sensor sits behind the inner panel and reads almost nothing when the
  phone is closed, so the cover uses its own light sensor, scaled the way stock
  scales it.
- **Display size per panel.** The cover and the inner display keep separate
  *Display size* settings. Font size is still shared. Requested on XDA.
- **The home screen follows auto-rotate.** Requested on XDA.
- **IMS settings for many more carriers.** VoLTE and VoWiFi depend on
  per-carrier settings. The build carried about 70 carriers' worth; it now
  carries about 2,500 entries, generated from Motorola's own carrier settings.
  This is meant for the XDA report of no VoLTE or VoWiFi on a carrier that works
  on stock. It has not been tested with that carrier's SIM.

### Fixed

- **No swap.** Motorola's start-up script unloads Android's standard
  compressed-RAM swap driver (zram) and loads Motorola's own in its place. That
  one cannot be built for this port, so the phone ran without any swap. This
  was measured on 24.0 test builds; 23.2 has the same configuration. The
  standard driver is now loaded again after that point, and the phone has a
  6 GiB compressed swap, as stock's own settings ask for.
- **Cover double-tap to wake dead after a boot with the phone open.** The cover
  panel turned off for the first time a moment before the gesture was armed, so
  its touch controller powered down fully and ignored taps until the cover had
  been switched on once. The gesture is now armed earlier in start-up.
- **Volume keys reversed on the cover.** Folded, the volume rocker is upside
  down; stock swaps the keys, and now this build does too. Reported on XDA.
- **Phone app under the cameras on the cover in landscape.** The Phone app
  ignored the side system-bar space that keeps apps clear of the camera block.

Making Motorola's Android 14 vendor code run on Android 17 also took changes
that fix nothing visible from 20261014. Each came up while porting and was
fixed before release:

- the audio HAL crashed in a loop because one audio structure grew
  in Android 17
- the camera provider needed a compatibility shim
- a buffer size was raised in the IMS video-call codec (the same class of bug
  as the Codec2 fix in 20261014)
- two vendor daemons were killed by their sandboxes
- vendor services died whenever a bug report or an app freeze collected stack
  dumps, which would have cut media playback
- light-sensor readings were lost
- the screen kept redrawing while asleep once the always-on display existed

### Verified this cycle

- **The published zip, three ways:**
  - **Clean install from Motorola's stock boot chain** with MindTheGapps 17.
    Recovery started on Motorola's kernel, as it does for a new user. Google
    sign-in and Play Store installs work, and there were no crashes.
  - **Update from 23.2-20261014 with MindTheGapps 16** to this build with
    MindTheGapps 17, without a wipe. One boot. The PIN, files, settings,
    contacts and Wi-Fi survived. Google Play services updated from 25.15 to
    26.11.
  - **The regression suite,** below.
- **The regression suite re-checked the earlier claims it covers.** Everything
  passed apart from the known audio-service restart races (below):
  - 5 reboots: both panels on every boot, no Codec2 service deaths, double tap
    armed at the cover's first turn-off.
  - 8 of 8 cameras streaming through Camera2, 3 of 3 through the old camera
    API.
  - Screen recording on the hardware encoder, and the speaker → microphone tone
    loopback (70 dB signal-to-noise).
  - Fold and unfold routing (emulated postures), and MTP, PTP and NCM tethering
    seen from the computer.
  - A recovery round trip.
  - The 6 GiB swap.
- **Steps that needed a person, all passing:** double tap to wake on both
  panels, a real fold and unfold, fingerprint unlock, an NFC card, Bluetooth
  music (checked by ear) and 9 minutes of off-mode charging.
- **Telephony on the installed release** (Orange Slovakia), checked from the
  phone's logs:
  - Mobile data over LTE with Wi-Fi off, passing Android's connectivity check.
  - Calls over VoLTE and over Wi-Fi calling, outgoing and incoming, all as HD
    voice, with call audio fine both ways.
  - SMS sent and received, both over IMS.
- **Kernel unchanged:** the same 6.1.145 source as 20261014.
- **Not re-tested this cycle:**
  - VoLTE on the carriers added by the new carrier settings
  - open to answer / close to end
  - the eSIM fix
  - video recording in the camera app
  - LHDC
  - power share
  - face unlock
  - whether Bluetooth music uses Motorola's audio provider. The tests only
    showed that music plays.

### Known issues

- **Bluetooth restarted 5 times in 15 seconds on the first unlock after the
  23.2 → 24.0 update** with fresh GApps. The Bluetooth stack could not parse a
  reply from the controller about LE scan filters. The crashes stopped after
  those 15 seconds and have not recurred after a Bluetooth restart, a reboot or
  a clean install.
- **Qualcomm's audio service sometimes crashes in the first seconds** after a
  boot (1 of 6 boots in the release test) and restarts on its own about 3
  seconds later. It is the same family of start-up races in Motorola's and
  Qualcomm's code as on 23.2, but the cause is not proven. It happens more
  often on 24.0: about 3 in 8 boots on the test builds, against 4 in 90 on 23.2.
- **Charging stops around 80–95 % on a phone left plugged in for days.** After
  every boot the phone shows *Not charging* and slowly drains, even on a strong
  charger. Unplug for a few seconds and plug back in: it charges normally again.
  This looks like Motorola's overcharge protection in the battery firmware,
  which the port does not change. It has not been compared with stock yet.
- **Auto-rotate occasionally stops responding until a reboot.** Reported on XDA
  on 23.2; not reproduced here, cause unknown.
- **Occasionally USB comes up MTP-only after a reboot, with no adb.** Not seen
  in this cycle's dozen or so reboots.
- **Apple Lossless (ALAC) files fail in apps that use Android's built-in
  decoders.** Unchanged from 20261014; see there.
- **No embedded secure element (eSE1),** as in 20260926.

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
- Open to answer / close to end: checked on real calls on the installed zip.
- Not re-tested on this build: the cover-display race (proven by the
  forced-race test build on 2026-10-05).
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

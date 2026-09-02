# arcfox LineageOS — READ THIS FIRST (written 2026-08-08 ~10:15,
# updated ~10:50)

`HANDOFF.md` is the full chronological record and is still accurate for
everything it describes. **This file supersedes its strategy.** Read this, then
use HANDOFF.md as the reference manual.

---

## 0.31 LAUNCHER PICKS A 3x3 GRID -- multi-display aggregation again (2026-09-01)

Operator reported "main screen is misaligned again". Screenshot in
`workspace/logs/foldtests-2026-09-01/main-screen.png`: one stray icon floating
mid-workspace, no widgets, and a hotseat of 3 slots with 2 apps pinned to the
edges.

**Launcher3 is running a 3x3 grid on the 1080x2640 inner panel.**

```
inv.numRows: 3   inv.numColumns: 3   numShownHotseatIcons: 3
gridName: 3_by_3   dbFile: launcher_3_by_3.db
```

Not a stale preference: after `pm clear com.android.launcher3` with the device
OPEN it recomputes 3_by_3 from scratch.

### Root cause -- the same shape as the DeskClock widget bug

`DisplayController.perDisplayBounds` holds BOTH panels, and Launcher3 selects the
grid from the MINIMUM width and MINIMUM height across every supported bound --
both panels, both rotations:

⚠️ **THE ARITHMETIC BELOW WAS WRONG IN EVERY PARTICULAR AND IS CORRECTED HERE**
(independent review, 2026-09-01). The retracted version claimed 4 bounds, a
411.4 x 411.4 dp square, and a `minHeightDps` threshold that 4_by_5 missed by
8.6 dp. All three were wrong, and it predicted the OPPOSITE of what the device
does. What actually happens:

- `InvariantDeviceProfile.java:891-913` uses `bounds.availableSize` (insets
  REMOVED), not raw bounds, and there are **8** entries, not 4. Measured live:
  inner `(1080,2469) (2532,943) (1080,2458) (2532,943)`, cover
  `(1080,849) (923,943) (1080,860) (923,943)`.
- `:902-906` **TRANSPOSES landscape entries** (`minWidthPx` takes
  `availableSize.y`, `minHeightPx` takes `.x`). So landscape can never contribute
  1080 to height -- the retracted "min h = 1080 from the LANDSCAPE entries" was
  backwards.
- Real result: minW = 943 px, minH = 849 px -- the height comes from the **cover
  panel in portrait** (1272 - 74 - 349). At density 420 that is
  **359.24 x 323.43 dp**.
- There is **no minHeightDps threshold**. `:916-921` sorts every display option by
  **Euclidean distance** and takes the nearest.

At (359.24, 323.43): `3_by_3 (255,300)` scores **106.84** and wins; `4_by_5
(275,420)` scores 128.15. At the retracted 411.4 x 411.4, 4_by_5 would have won --
which is how we know the old model was wrong: it predicted the grid we do not get.

So it derives a geometry from the COVER panel's portrait height and the inner
panel's landscape width, and the nearest option to that is the smallest grid
Launcher3 ships. Identical family to
[[deskclock-widget-multidisplay-sizing]]: a foldable aggregating across display
profiles and landing on a geometry that matches nothing real.

### ⚠️ CONSEQUENCE: our Launcher3 overlay is currently INERT

`device/motorola/arcfox/overlay-lineage/packages/apps/Launcher3/res/xml/
default_workspace_4x5.xml` -- committed earlier today as "launcher: make room for
the clock widget", spanY 1 -> 2 -- is never loaded, because the grid is 3_by_3 and
Launcher3 loads the 3x3 default workspace instead. That commit cannot have had any
effect on this device and its verification was never possible. Do not treat the
DeskClock widget placement as tested until the grid is fixed.

### No user-facing workaround

This is AOSP `Launcher3QuickStep` (system_ext/priv-app), NOT Trebuchet. There is
no grid picker in its settings, and the GridCustomizations provider requires
BIND_WALLPAPER or com.android.launcher3.permission.GRID_CONTROL, which shell does
not have -- `content query` on it is a SecurityException. It must be fixed in the
build.

### Two candidate fixes, neither implemented

1. **Device overlay** on Launcher3 `res/xml/device_profiles.xml`.
   ⚠️ The retracted number here (`below 411`) WOULD NOT HAVE WORKED -- it would
   have shipped a build that still boots to 3_by_3. Against 3_by_3's 106.84,
   4_by_5 at minHeightDps 411 scores 121.51, at 400 scores 113.84, at 390 scores
   107.37 -- all still losing. It only wins **below ~389**, and even then by 0.09,
   which is far too thin to ship. Prefer removing or bounding `3_by_3` in the
   overlay over tuning 4_by_5 toward a tie.
2. **Patch Launcher3** to derive the grid from the ACTIVE display instead of the
   min across all supported bounds. Correct, upstreamable, and the same argument
   already written up for the DeskClock fix. Bigger change; needs care not to break
   genuine tablet/two-panel handling.

**A third option the first writeup missed:** `DisplayController.java:560-563`
computes `isTablet` from `smallestSizeDp(bounds) >= MIN_TABLET_WIDTH` on RAW
bounds; every bound's min dimension is 1080 px = 411 dp < 600, so the device flags
TYPE_PHONE. `3_by_3` is `deviceCategory="phone"` only (`device_profiles.xml:68`),
so if `getDeviceType()` returned TYPE_MULTI_DISPLAY, 3_by_3 would be filtered out
by category and 4_by_5 would win outright -- no threshold tuning at all.

Recommend 2, with the category route as the cheaper alternative. Either way it
costs a build + flash, so it was NOT done in the same session as the fold tests.

---

## 0.30 FOLD TESTS B-F: PASS, ON THE FLASHED BUILD (2026-09-01)

Run on the post-flash build with the operator working the hinge. Logs in
`workspace/logs/foldtests-2026-09-01/`.

### Posture resolution -- PASS, all five

Continuous 1 Hz sampling of `dumpsys device_state`, logging only on change:

```
20:13:35  OPENED
20:14:05  CLOSED_HALL        <- intermediate; per-position snapshots miss this
20:14:14  CLOSED
20:14:15  HALF_OPENED_MAIN
20:14:26  TENT
20:14:32  OPENED
```

⚠️ **Scope corrected:** "all five" overstates it. CLOSED (state 1) appeared only
as a single-sample transient between CLOSED_HALL and an open state -- it is the
opening motion, not an independently held posture -- and two configured states,
HALF_OPENED_QVD (3) and OPENED_HALL (6), were never observed at all. What is
proven: OPENED, CLOSED_HALL, HALF_OPENED_MAIN and TENT commit from real hinge
movement, and a later `cmd device_state` sweep confirmed routing for all seven.
Note also that `transitions.log` and `transitions-panel.log` disagree at 20:17:49
(CLOSED vs OPENED).

Every posture in `fold/device_state_configuration.xml` is reachable and commits.
This is the machine that used to sit at INVALID (-1) because the lid switch never
appeared; `MotFlip_LID` is now present and all four hinge sensors (Hinge Angle,
Hinge Posture, Flip Position, Flip Hall Effect) are registered with live
connections.

### Display routing -- PASS, both directions, twice

```
20:16:51  OPENED       display0 = port 131 (INNER)
20:17:29  CLOSED_HALL  display0 = port 132 (OUTER)
20:17:37  OPENED       display0 = port 131
20:17:44  CLOSED_HALL  display0 = port 132
20:17:49  OPENED       display0 = port 131
```

`display_layout_configuration.xml` is parsed and registered -- `dumpsys display`
shows `DeviceStateToLayoutMap` with state(0..3) -> port 132 and state(4..6) ->
port 131 -- and the swap actually happens, reversibly and repeatably.

### ⚠️ METHOD WARNING: the first measurement said the opposite, and it was WRONG

The first pass sampled `mScreenState` from `dumpsys display` and reported
`ON/OFF` unchanged across the whole fold sequence. That was read as "posture
resolves but display routing does not follow" -- a defect that does not exist.

`mScreenState` is per LOGICAL display. When the layout swaps, logical display 0
changes WHICH PHYSICAL PANEL backs it, so the reading is `ON/OFF` whether or not
the swap occurred. The metric was structurally incapable of detecting the thing
it was being used to judge.

The correct field is the port in `mCurrentLayout` / `DeviceStateToLayoutMap`
(`dispId: 0(ON), addr: {port=131|132}`), which names the physical panel.
⚠️ Even that is only *nearly* right: `LogicalDisplayMapper.java:1237` sets
`mCurrentLayout` from the object stored in the static map, so it proves which
layout was SELECTED, not which binding took effect -- `applyLayoutLocked` can
`continue` past a display when `device == null` (`:1251`). The conclusive field is
the live LogicalDisplay -> DisplayDevice binding in `mBaseDisplayInfo` plus each
device's `state`/`committedState`.
**Validate a metric against a case where it MUST change before trusting a
negative result from it.**

### Not covered -- needs eyes, not adb

Everything above is framework state. What a person actually SEES was not
assessed: whether the cover panel renders the lock screen and launcher legibly,
whether an app moved to the cover survives, and whether content is correctly
sized for 1080x1272. `config_displayUniqueIdArray` and the per-display cutout
were fixed earlier and verified in the built apk, but no visual pass has been
recorded on this build.

Also noted, not chased: `mDeviceStatesOnWhichToWakeUp={}` and
`mDeviceStatesOnWhichSelectiveSleep={}` are both EMPTY (AOSP defaults; we do not
override them). Routing works without them, so they are not a defect -- but they
are what would make the device sleep/wake the panels on fold, and are worth a
look if power behaviour on close ever comes up.

---

## 0.40 NOT A BUG: "100% but 1h13m to full" is real CV charging (2026-09-02)

Reported as an inconsistency. It is accurate on both counts. arcfox has a DUAL
CELL battery and the two cells finish at different times:

```
power_supply/main_battery   status=Charging  4514 mV   276 mA
power_supply/flip_battery   status=Full      4530 mV     0 mA
power_supply/mmi_battery    status=Charging            (aggregate)
power_supply/battery        status=Charging            (what the framework reads)

mmi_charger [C:sc7603]            batt_status 4 (FULL)      <- flip cell
mmi_charger [C:qti_glink_charger] batt_status 1 (CHARGING)  <- main cell
mmi_configure_charger  FV=4530 (flip) / FV=4540 (main), CFULL=0 on both
```

The flip cell has reached its float voltage (4530 == FV 4530) and terminated. The
main cell is 26 mV below its float target (4514 vs FV 4540) and still drawing
current, so `ext_charger.c:118` (`if (chg->chg_cfg.full_charged) batt_status =
POWER_SUPPLY_STATUS_FULL;`) has not fired for it, and the aggregate follows the
main cell.

**The fuel gauge reports 100% SoC before the constant-voltage phase completes.**
That is normal lithium behaviour. The UI is showing two accurate but
different-looking facts side by side: state of charge (100%, fuel gauge) and
charge termination (not yet, charger). `LimitMode: 2` is also active at 34 degrees,
so charge current is thermally limited, which is why the remaining estimate is
over an hour rather than minutes.

⚠️ Do not "fix" this by forcing POWER_SUPPLY_STATUS_FULL at capacity==100. That
would report termination before the cell reaches float voltage and would be a
genuine lie to the framework. Both cells are at charge_counter == charge_full for
their LEARNED capacity (main 2714000, flip 976500; design total 4000000), so
nothing is being overcharged.

⚠️ Diagnostic note: `/sys/class/power_supply/battery` on this device is an
AGGREGATE synthesised by mmi_charger. When battery state looks contradictory,
read `main_battery` and `flip_battery` separately before concluding anything --
the aggregate hides which cell is doing what.

---

## 0.39 REVERSE CHARGING: WORKS, BUT ONLY ON BATTERY (2026-09-02)

Reported as "reverse charging is not working". It works. **It will not transmit
while the phone is charging over USB.** That is a firmware/hardware precondition
of the CPS4041 path, not something our software gates.

Measured with a 1 Hz on-device logger that keeps running while unplugged
(`/data/local/tmp/wlslog.sh`, since adb dies with the cable):

```
12:29:26  usb=1  rx_conn=0     plugged in, nothing happens
12:29:54  usb=0  rx_conn=0     cable pulled
12:30:08  usb=0  rx_conn=1     RECEIVER DETECTED and charging
12:30:13  usb=0  rx_conn=0     device lifted off
12:30:15  usb=1  rx_conn=0     cable back in
```

The software chain was never at fault and is fully intact after several wipes:
`org.lineageos.arcfox.powershare` installed, `sys.arcfox.powershare=1`,
`tx_mode=1`.

### ⚠️ INSTRUMENT TRAP: tx_mode_vout is USELESS

`tx_mode_vout` read **0 for the entire test, including while a device was
actively charging**. The same is true of the `qti_glink_charger` dump
(`TX_IIN: 0mA, TX_VIN: 0mV, TX_VRECT: 0mV`) -- those were 0 while the feature
worked. Reading them as "the transmitter is not energised" produced a confident
WRONG diagnosis before the unplugged test corrected it.

**Judge reverse charging by `rx_connected` only.** Nothing else in that directory
reflects reality.

### The enable path really is one write

Confirmed against stock's own HAL binary: `setWlsTxMode on/off` writes ONLY
`/sys/class/power_supply/wireless/device/tx_mode`. Every other sysfs path the
stock HAL references (`rx_connected`, `rx_dev_*`, `pen_*`, `folio_mode`,
`wireless/online`) is read-only status. So there is no second node we are
missing, and the init+property+app approach in place is complete.

### Worth improving, not a defect

The `ArcfoxPowerShare` app has battery-level and wireless-input guards but no USB
guard, so the toggle can be switched on while plugged in and silently do nothing.
A precondition check ("disconnect the charger to share power") would remove the
entire class of confusion this caused. Optional UX work, not a bug.

⚠️ For the record: this feature was previously written up as "CONFIRMED WORKING by
the operator" while the note beside it admitted the coil energising had never been
verified, because `tx_mode` was unreadable without root. Both statements were true
and the pairing was misleading. `adb root` works on this build -- verify the
hardware, do not infer it from a successful write.

---

## 0.38 THERMAL PROFILE SWITCHING IS DEAD, AND CANNOT BE REVIVED (2026-09-02)

A known, understood divergence from stock. **Do not try to fix it by shipping
motosxf.rc** -- that was investigated to a conclusion and does not work.

### The divergence

We ship all eight `thermal-engine*.conf` files, byte-identical to stock, but only
the DEFAULT one is ever loaded. Measured live: `vendor.motosxf.mode` and
`vendor.thermal.mode` are BOTH EMPTY. So the seven profile variants
(`-camera`, `-cli`, `-game-perf`, `-gb`, `-perf`, `-tmo`, `-arcfox`) are dead
weight on this build.

Consequence, in stock's own numbers: the camera profile defers first cluster0
mitigation from **40 to 42 degrees** and removes the 40-degree set-point
controllers on cluster1/cluster2. On our build the default profile applies during
camera use, so the device begins mitigating earlier than stock does. Real, but
modest, and the SEVERE report at 40 degrees is unaffected either way (see 0.36
and the thermal review).

### Why it cannot be fixed

The chain that selects a profile is:

```
Motorola's patched system_server / mediaserver
      | binder call to motorola.hardware.sxf::IMotoSxf     <-- WE DO NOT HAVE THIS
motosxf sets vendor.motosxf.mode
      | init.maxe.rc
vendor.thermal.mode
      | init_thermal-engine-v2.rc  (this part DOES ship and DOES work)
thermal-engine loads thermal-engine-arcfox-<mode>.conf
```

`/vendor/bin/hw/motosxf` is a **VINTF-stable AIDL HAL** serving
`motorola.hardware.sxf::IMotoSxf` (`BnMotoSxf`, `getInterfaceVersion`,
`getInterfaceHash`, `MotoSxfActionLooper`). It does not decide its own mode; it is
TOLD. Stock's own sepolicy names the callers:

```
(typeattributeset hal_motsxf_client (mediaserver_34_0 system_server_34_0 hal_audio_default))
```

On LineageOS those three are AOSP binaries and will never call a
`motorola.hardware.*` interface. Verified: the only system-side reference to
`motorola.hardware.sxf` anywhere in system/system_ext/product is
`/system/etc/vintf/compatibility_matrix.device.xml`, which is a DECLARATION that
the framework may use the HAL, not a caller. On the vendor side only
`libverdict.so` references it, and `libverdict.so` is linked by nothing except
`motosxf` itself.

⚠️ So shipping `motosxf.rc` plus a `file_contexts` label and a domain would start
a VINTF HAL that nothing ever calls. `vendor.motosxf.mode` would stay empty
exactly as it is now and no profile would ever be selected. Same shape as the 43
unlabelled Motorola services we declined to port, the powershare client chain, and
`com.motorola.thermalservice`. Dropping the `.rc` AND its VINTF fragment together
in `7d26208` was correct -- without the fragment it could not have registered even
if it started.

### Compliance was never the obstacle

For the record, since it was asked: shipping a vendor blob with its init `.rc` and
sepolicy labels is entirely normal for an official LineageOS device, and the
binary (`vendor/bin/hw/motosxf`, proprietary-files.txt:1030) plus its config
(`vendor/etc/motosxf_conf_profile`, :2352) are ALREADY shipped, so nothing new
would be redistributed. The charter constraint for this device is kernel `.ko`
prebuilts (0.20), which is cleared. The blocker here is reachability, not policy.

### The only lever, and why it is not taken

`init_thermal-engine-v2.rc` ships and honours `vendor.thermal.mode`, so we COULD
set it ourselves and pin a profile permanently. Not done, because nothing on this
build knows when the device is in camera/game mode -- that signal lives in the
Motorola framework. Pinning a non-default profile permanently would defer camera
throttling at the cost of whatever the default profile protects in every other
scenario, which is an unquantified trade on thermal behaviour. Left alone
deliberately.

---

## 0.37 ✅ VoLTE WORKS (2026-09-02). VoWiFi still open.

**VoLTE had never once registered on this port.** Now it does, and an ordinary
call stays on it. This matters beyond convenience: 2G/3G shutdowns are underway
in many countries, and without VoLTE this device eventually cannot place a voice
call at all.

### Root cause: two config gates, both false, neither ours

```
config_device_volte_available = false   (AOSP default; no overlay existed)
carrier_volte_available_bool  = false   (no IMS keys in the Orange SK config)
        ↓ ImsManager requires BOTH
updateVoiceCellFeatureValue: available = false
reevaluateCapabilities: turnOffIms
GsmCdmaPhone: useImsForCall=false   ->  EVERY call went to circuit-switched
```

Before: `handleImsConnected` **0 times** in a full log; only
`handleImsUnregistered` with `CODE_REGISTRATION_ERROR`.

### Proven on device before shipping

`persist.dbg.volte_avail_ovr=1` + `persist.dbg.wfc_avail_ovr=1` + reboot
(ImsManager honours those ahead of the resources), then an ordinary call:

```
handleImsRegistered: onImsMmTelConnected imsTransportType=WWAN
useImsForCall=true, useOnlyDialedSimEccList=false, isEmergency=false
ImsPhoneConnection x101, GsmCdmaConnection x0
notifySrvccState events: 0
```

An ORDINARY call, carried over IMS, which STAYED on IMS. The VoLTE and Wi-Fi
calling toggles also appeared in Settings.

### ⚠️ The emergency-call SRVCC was a FALSE LEAD

Earlier today the emergency-calling test showed `notifySrvccState: state=STARTED`
with an `ImsPhoneConnection`, and it was suggested this hinted VoLTE partly
worked. **It proved the opposite.** That call reached IMS only via
`REQUEST_EMERGENCY_DIAL`, which AOSP permits WITHOUT IMS registration
(`useImsForCall=false, isEmergency=true` in the same log). Never read an
emergency call as evidence about VoLTE.

### Shipped

- `device/motorola/sm8635-common/overlay/.../values/config.xml` (**new**):
  `config_device_volte_available`, `config_device_vt_available`,
  `config_device_wfc_ims_available` = true. Commit `65bbcd9`.
- `packages/apps/CarrierConfig/assets/carrier_config_carrierid_1713_Orange.xml`:
  `carrier_volte_available_bool`, `carrier_wfc_ims_available_bool`,
  `enhanced_4g_lte_on_by_default_bool`, `editable_wfc_roaming_mode_bool`,
  `vonr_enabled_bool`. Branch `arcfox-orange-sk-ims`, commit `f817e61`.

Both verified in the BUILT APKs (`aapt2 dump resources` / `unzip -p` on the
asset), not the source.

⚠️ **`hide_enhanced_4g_lte_bool` deliberately NOT copied.** Stock sets it true,
hiding the switch and making VoLTE always-on. We keep a visible toggle.

⚠️ **NOT NEEDED: an ims-type APN.** Adding one to `vendor/apn/SK.xml` was
proposed; measured, IMS registers WITHOUT it, because the modem raises the IMS
PDN from its own `ORANGE_SVK` mcfg. Do not add one.

⚠️ **Structural gap that will recur:** stock gets carrier config from the GMS
`CarrierSettings.apk` plus ~3290 `.pb` files, which LineageOS cannot ship. EVERY
carrier this device meets will have an empty config until its values are
re-expressed as AOSP CarrierConfig XML. The active SIM is **Orange SLOVAKIA,
MCC 231/01, carrierId 1713** (not Czech 230).

### ✅ PROVEN ON THE SHIPPED CONFIG (2026-09-02, after flash)

The debug overrides were wiped with /data, so this was the committed config
alone. Verified `[]` empty before measuring.

```
carrier_volte_available_bool   BOOLEAN true   (cmd phone cc get-value -s 0)
carrier_wfc_ims_available_bool BOOLEAN true   matched to carrierId 1713
useImsForCall=true, isEmergency=false          <- was FALSE on every prior build
ImsPhoneConnection x107, GsmCdmaConnection x0
notifySrvccState events: 0                     <- stayed on VoLTE, no CS fallback
```

The VoLTE toggle also defaulted to ON without the user setting it, which is
independent evidence `enhanced_4g_lte_on_by_default_bool` reaches the framework
and the carrier config file is being matched.

⚠️ Instrument note: `onImsMmTelConnected` showed 0 for the WWAN case because the
registration callback fires early in boot and the post-wipe log buffer is back to
256 KiB by default. Raise it (`logcat -b all -G 16M`, `logcat -b radio -G 32M`)
BEFORE looking, or the evidence has already rolled off. The call-path evidence
above is direct and does not depend on it.

### ✅ VoWiFi ALSO WORKS (2026-09-02)

Binding the three IWLAN service packages was sufficient. With Wi-Fi connected and
Wi-Fi calling enabled:

```
handleImsRegistered: onImsMmTelConnected imsTransportType=WLAN
NetworkRegistrationInfo{ domain=PS transportType=WLAN
                         registrationState=HOME
                         accessNetworkTechnology=IWLAN }
```

Was `registrationState=UNKNOWN` on every previous build.

⚠️ **`ps -A | grep iwlan` returns 0 and that is NOT a failure.** The
QualifiedNetworksService runs IN-PROCESS, not as a standalone daemon. Judge VoWiFi
by the WLAN NetworkRegistrationInfo and `imsTransportType=WLAN`, never by a
process listing. This nearly got reported as "the binding is insufficient".

⚠️ The medium risk did not materialise: mobile data was verified intact after the
flash (mDataRegState=0 IN_SERVICE, 4 rmnet UP, ping 8.8.8.8 0% loss). If it ever
does regress, the revert is the three `config_wlan_*_service_package` strings
only; VoLTE does not use the WLAN transport and survives that revert.

### Original VoWiFi analysis (kept for context)

`config_wlan_data_service_package`, `config_wlan_network_service_package` and
`config_qualified_networks_service_package` are all EMPTY STRINGS, and
`vendor.qti.iwlan` never runs -- the same "nothing was ever bound" shape as the
ImsService in `75b2198`. Stock's vendor RRO sets all three to `vendor.qti.iwlan`.
Deliberately NOT done in the same change: binding a `DataService` and
`NetworkService` that have never run on this build can disturb mobile data, so it
must land alone to keep any regression attributable.

---

## 0.36 NOT A BUG: shaky ZOOMED PHOTO preview on tele is hardware (2026-09-02)

Reported as "EIS on the tele lens is not working". It is working. Measured from
`dumpsys media.camera` static info:

```
cam | focal    | availableOpticalStabilization | availableVideoStabilizationModes
 0  | 4.68mm   | [0 1]   OIS present           | [0 1 2]
 2  | 4.68mm   | [0 1]   OIS present           | [0 1 2]
 3  | 7.07mm   | [0]     NO OIS                | [0 1 2]
 6  | 7.07mm   | [0]     NO OIS                | [0 1 2]
 1  | 3.28mm   | [0]     NO OIS                | [0 1 2]
```

**The 7.07 mm tele pair has no optical stabilisation hardware at all.** EIS (video
stabilisation) is available on every camera and confirmed working -- the operator
reports tele VIDEO preview is stable, which is the EIS path from 0.22 doing its
job.

PHOTO preview does not run video stabilisation; EIS is a video-mode feature. So on
tele, zoomed stills preview has nothing stabilising it. On the main camera the same
zoom feels steadier because that sensor has OIS. Same lens, stable video, shaky
photo preview -- all three are consistent and correct.

⚠️ Do not "fix" this, and do not read shaky tele photo preview as an EIS
regression. The Vidhance config is byte-identical to stock besides:
`vidhance_calibration` 7661 B, `vidhance.lic`, and all three
`com.vidhance.node.{gme,preview,video}.so`. Same family of settled hardware verdict
as [[face-is-class-1-by-hardware]].

---

## 0.35b ✅ API1 CAMERA AND VIDEO BOTH PASS (2026-09-02)

**The charter item is closed.** Tested with a purpose-built API1 client:
`device/motorola/sm8635-common/tests/Api1CameraTest` (diagnostic only, NOT in
PRODUCT_PACKAGES -- build with `m Api1CameraTest`, install with adb).

```
api1_camera_count=3         PASS
api1_open                   PASS
api1_preview                PASS
api1_preview_frame          PASS bytes=3110400   (= 1920*1080*1.5, real NV21)
api1_recorder_prepare       PASS
api1_recorder_start         PASS profile=1280x720
api1_recorder_stop          PASS
api1_video_bytes=7892985    PASS
```

Video verified with ffprobe on the pulled file, not by size alone:
`h264 1280x720, 132 frames, 4.48 s, plus aac 210 frames`. A real playable MP4 from
MediaRecorder bound to a legacy `android.hardware.Camera`.

### ⚠️ This OVERTURNS the earlier "preview unresolved" result below

0.35 recorded `waitForPreviewStart()` returning -110 (ETIMEDOUT) from AOSP's
`camera_client_test` and left preview UNRESOLVED, suspecting the harness. That
suspicion was right: with a real Activity and a real SurfaceView, preview delivers
frames immediately. **AOSP's camera gtests are not a valid instrument for camera
function on this device** -- they run headless as root against a synthetic
SurfaceComposerClient surface. Do not re-derive a camera fault from them.

The other 0.35 lesson still stands and is worth keeping: free the camera first
(`am force-stop org.lineageos.aperture`), or any camera test fails with
"rejected (existing client(s) with higher priority)".

---

## 0.35 (SUPERSEDED by 0.35b) API1 CAMERA: PARTIALLY VERIFIED, video NOT tested (2026-09-02)

Tested with AOSP's own `camera_client_test` (`frameworks/av/camera/tests`), built
from this tree and pushed to /data/local/tmp. `CameraZSLTests` is a genuine API1
client -- `#include <camera/Camera.h>`, `setPreviewTarget()`, `startPreview()`.

### ✅ Established

```
Number of camera devices:                        8
Number of normal camera devices:                 3
Number of public camera devices visible to API1: 3   (devices 0, 1, 5)

CameraService: connect call (PID …, "ZSLTest", camera ID 0) and Camera API version 1
CameraService: Camera 0: Closed        <- served by Camera2Client, the API1 shim
```

API1 **enumeration and connect both work**. The service accepts the legacy
`connect()`, identifies it as "Camera API version 1", and serves it through
`Camera2Client`. The connect path is not broken.

### ⚠️ NOT established: preview, and NOT tested at all: video

`waitForPreviewStart()` returned **-110 (-ETIMEDOUT)** at `CameraZSLTests.cpp:287`.
⚠️ Do NOT record that as "API1 preview is broken" -- the harness is a headless
gtest running as root with a synthetic SurfaceComposerClient surface, and AOSP's
camera gtests are unreliable outside the CTS harness. All the stream errors in the
log are TEARDOWN errors ("Stream N does not exist", -22), consistent with streams
never being created, and no error was logged at startPreview time itself. Device
vs harness is UNRESOLVED.

**Video via API1 was not exercised at all.** This binary never touches
MediaRecorder; the "API1 camera/video" charter item has a video half that nothing
here reaches.

### ⚠️ Two false alarms this test produced, recorded so they are not re-derived

1. `CameraServiceBinderTest.CheckBinderCameraService` FAILED at
   `CameraBinderTests.cpp:416` -- but that line is `connectDevice()`, which is
   **API2**, not API1. It says nothing about the legacy path.
2. The first `CameraZSLTests` run failed at line 216 and segfaulted. Cause, from
   the log: `rejected (existing client(s) with higher priority) … Conflicts with:
   Device 0, client package org.lineageos.aperture`. **The camera app was holding
   camera 0.** After `am force-stop org.lineageos.aperture` the connect succeeded.
   Free the camera before running any camera test. The segfault is an AOSP test
   bug -- it does not null-check after a failed connect.

### To actually close this

A real API1 client app doing preview + MediaRecorder capture. That is the only
thing that settles both halves; the gtest cannot.

### Cleanup

Test binary removed; the 2 tombstones it left (`Cmdline:
/data/local/tmp/camera_client_test`) deleted so the tombstone count stays a
meaningful health signal; adb dropped back to shell. Camera verified healthy
afterwards: 8 devices, 3 API1-visible, provider running, `cameraserver` never
restarted.

---

## 0.34 ✅ EMERGENCY CALLING: TESTED AND RECORDED (2026-09-02)

**The last outstanding MUST. This section is the record; it did not exist before.**

### Method (safe -- no real emergency service was contacted)

AOSP's own test hook was used to make a number the operator controls be treated as
an emergency number, so the full emergency path runs to a destination we own:

```
cmd phone emergency-number-test-mode -a <operator's second handset>
cmd phone emergency-number-test-mode -p     # confirm
cmd phone emergency-number-test-mode -c     # cleared afterwards
```

Number redacted here on purpose: the operator's second handset, +420 607 ••• 154.
A personal mobile number does not belong in a file headed for upstream review.

### Preconditions, measured

```
emergency list from the modem : [155, 112, 158, 159, 911, 150]   (Czech + 911)
SIM / network                 : Orange, LTE     (registered; NOT the EDGE,Unknown
                                                 seen earlier with the other SIM)
armed list                    : [155, 112, 158, 159, 911, +420…154, 150]
baseline                      : 0 active calls, mCallState=0
```

### Result: PASS

Operator dialled the number from the ORDINARY dialer (not the emergency dialer)
and reports: **call placed, second handset rang, two-way audio worked.**

Evidence that the EMERGENCY path was taken, not a normal call --
`logs/emergency-call-2026-09-02/`:

```
10:51:53 EmergencyNumberTracker: [0]Found in mEmergencyNumberList
         -> the dialled number was classified as emergency at dial time

10:52:03 GsmCdmaCallTracker: notifySrvccState: state=STARTED,
                             mHandoverConnections=[[ImsPhoneConnection …]]
         -> SRVCC: the call was handed over from IMS/VoLTE to circuit-switched,
            which is the characteristic emergency behaviour on LTE

10:52:14 Telecom EmergencyCallDiagnosticLogger: Evaluating emergency call …TC@1
10:52:14 Telecom EmergencyCallDiagnosticLogger: Triggering diagnostics … reason: 4
10:52:16 Telecom InCallController$EmergencyInCallServiceConnection: Disconnecting
         -> Telecom bound the EMERGENCY InCallService, not the normal one
```

`setIsNetworkIdentifiedEmergencyCall=false` is expected and correct: the NETWORK
did not independently classify it, because it is our test number rather than a
real emergency number. The DEVICE-side classification is what this MUST is about,
and it is unambiguous.

### Cleanup, verified

Test mode cleared; list back to `[155, 112, 158, 159, 911, 150]` with the test
number absent, 0 active calls, `mCallState=0`. Radio/main buffers had been raised
to 32M/16M for the capture (`logcat -b radio -G 32M` -- that buffer is NOT listed
by `logcat -g`, see [[logcat-G-misses-the-radio-buffer]]).

⚠️ What this does NOT prove: that dialling a REAL emergency number reaches a REAL
PSAP. That cannot be tested without contacting emergency services and must never
be attempted. What is proven is the device-side path: classification, emergency
InCall routing, SRVCC to CS, and a connected call with two-way audio.

---

## 0.33 POST-FLASH LOG SWEEP (2026-09-01)

Full harvest in `workspace/logs/postflash-2026-09-01/logcat-all.txt` (35492 lines,
buffer raised to 16M after capture; kernel/events reach back to boot at 13:50).

### ⚠️ CORRECTION TO A RECORDED BLOCKER: `adb root` WORKS ON THIS BUILD

Earlier handovers state "adb root is unavailable (disabled by system setting)" and
mark several checks impossible because of it. **That is false as of 2026-09-02.**
`adb root` returns `restarting adbd as root` and `whoami` returns `root`, on the
shipping userdebug build, even though `ro.debuggable=0`.

This unlocks: `/sys/kernel/debug` (mount it first -- `mount -t debugfs none
/sys/kernel/debug`; it is NOT mounted by default), `/vendor/bin`, `/vendor/lib64`,
`/mnt/vendor/persist`, and `adb remount`, which gives writable overlayfs on
/vendor and a full test loop with NO FLASH. The IPA experiment below was done that
way in minutes.

⚠️ Two gotchas: the toggle is in Settings and a wipe/reboot can reset it (the
device silently stopped enumerating mid-session for exactly this reason), and
⚠️ per [[validate-live-before-flashing]] the overlay must be cleared afterwards
(`rm -rf /mnt/scratch/overlay` + reboot) or later "verify the artifact" checks read
the overlay instead of the image.

### Clean

0 ANRs, 0 kernel panics/oops, 0 EXT4/IO errors, 0 `Could not start service`,
0 `incorrect label or no domain transition`, no service started more than once,
and every `init.svc.*` is `running` or `stopped` (none restarting).

The absence of service-start failures is a real consequence, not a coverage gap:
commit 7d26208 dropped the 16 dead `.rc` files, so those services no longer exist
to fail.

### Large error counts, all explained

- **5125x** `ActivityThread: Failed to find provider info for
  com.google.android.setupwizard.partner` -- a GMS SetupWizard provider absent from
  this GMS-less build, emitted by the wizard and FallbackHome. Cosmetic.
- **490x** `init: Control message: Could not find 'aidl/vendor.qti.data.nwmgr.INwMgr'
  for ctl.interface_start` -- the cnd/INwMgr churn documented in vendor.prop today.
  Stock parity; the server exists in vendor.libdpmframework.so but its only host,
  vendor.dpmd, can never link.
- **PT** `cdsp_stat` / `adsp_stat` -- DSP telemetry.
- `ro.vendor.hw.curve` "Read-only property was already set" -- init.mmi.touch.sh
  sets it twice. Benign.

### ⚠️ TWO GENUINE ITEMS, BOTH NOW ROOT-CAUSED (neither caused by today's changes)

#### 1. NFC abort: an eSE/NFC HAL ownership race, once per boot

`/vendor/etc/init/nfc-service-st.rc` declares the ST NFC HAL `disabled` and drives
it entirely from one property:

```
service st_nfc_aidl_service /vendor/bin/hw/android.hardware.nfc-service-st
    class hal
    disabled
on property:vendor.ese.nfc.disable=1
    stop st_nfc_aidl_service
on property:vendor.ese.nfc.disable=0
    start st_nfc_aidl_service
```

That property is set by **`/vendor/bin/hw/android.hardware.secure_element-service.qti`**
-- the eSE HAL takes exclusive ownership of the shared ST controller during its own
init, then hands it back. Measured timeline:

```
46.597  com.android.nfc starts (pid 5995)
46.742  init: action (vendor.ese.nfc.disable=1) -> SIGKILL st_nfc_aidl_service (pid 2837)
46.764  com.android.nfc: FORTIFY destroyed mutex -> SIGABRT      (22 ms later)
46.832  com.android.nfc restarts (pid 6182)
47.974  action (vendor.ese.nfc.disable=0) -> HAL restarts (pid 6492)
```

The app binds the HAL and is 22 ms into initialisation when the HAL is SIGKILLed
out from under it; libnfc-nci then locks a mutex the torn-down connection already
destroyed. Fires exactly ONCE per boot (1x disable, 1x enable) and self-heals:
adapter `mState=on`, `android.hardware.nfc.INfc/default` registered, zero
NfcService/NfcNci errors afterwards.

Both the .rc and the eSE HAL are unmodified stock blobs; the race is in the
framework app's start timing relative to them, so there is no clean fix at our
layer. Cost is one crash and ~1.2 s of NFC unavailability at boot. LEFT ALONE.

#### 2. WLAN IPA line: a legacy datapath call that cannot succeed on this DP

`qca-wifi-host-cmn/dp/inc/cdp_txrx_ipa.h:276`:

```c
if (!soc || !soc->ops || !soc->ops->ipa_ops || !cfg_pdev) {
        QDF_TRACE(... QDF_TRACE_LEVEL_FATAL, "%s invalid instance", __func__);
```

Called from `qcacld-3.0/core/wma/src/wma_main.c:5135` inside `#ifdef IPA_OFFLOAD`
(so IPA_OFFLOAD IS defined -- a no-op build would print nothing) with
`cds_get_context(QDF_MODULE_ID_CFG)` as `cfg_pdev`. That legacy OL cfg context does
not exist on the modern lithium/beryllium DP, so the guard trips on a NULL pointer
that can never be non-NULL here. It is a leftover from the pre-lithium datapath.

Fires exactly ONCE at init. WiFi works, and our module carries the same IPA
strings as stock's, so this is not a build-config regression.

✅ **SETTLED 2026-09-02 by live experiment. WLAN-IPA offload CANNOT work on this
device, and the trace is the correct report of that.** Do not reopen.

The ini is at `/vendor/etc/wifi/kiwi_v2/WCNSS_qcom_cfg.ini` (not the path first
guessed), and Motorola sets `gIPAConfig=0` EXPLICITLY at line 49 -- a deliberate
disable, not a default. Setting it to `0x2d` (bit0 enable | bit2 IPv6 | bit3 RM |
bit5 UC) live and reloading the driver produced:

```
wlan_pld:pld_is_ipa_offload_disabled:2768:: Not supported on type 0
wlan: [IPA] ipa_component_config_update: IPA disabled from platform driver
wlan: [IPA] ipa_pdev_obj_create_notification: IPA is disabled
```

The ini value is READ and then OVERRIDDEN. `pld_common.c:2751`
`pld_is_ipa_offload_disabled()` implements ONLY `PLD_BUS_TYPE_SNOC`; every other
bus type hits an explicit `pr_err("Not supported on type %d")`. `PLD_BUS_TYPE_PCIE
= 0`, and kiwi_v2 is a discrete PCIe part -- so **WLAN-IPA offload in qcacld is a
SNOC-bus feature that has no PCIe path at all.** Zero wlan pipes ever appeared in
`/sys/kernel/debug/ipa`.

That single fact explains all four observations at once: why Motorola wrote
`gIPAConfig=0`, why they compiled IPA out of their driver entirely (stock's .ko has
0 undefined ipa symbols; ours has 23, because we build from source with
kiwi_v2_defconfig which sets `CONFIG_IPA_OFFLOAD := y`), why no DT node declares a
WLAN-IPA path, and why the FATAL trace fires once.

⚠️ Reverse engineering would NOT have helped and was considered: RE recovers how a
CLOSED, WORKING thing behaves. Here the code is open source (13 .c files in the
tree) and the feature is absent from stock, so there was nothing to recover.

Device restored: ini md5 back to `6c76731abc4d35b43df69c8b41cd7036`, overlay
deleted, rebooted clean.

### The original observations

**1. `com.android.nfc` aborted once at boot.**
```
F libc: FORTIFY: pthread_mutex_lock called on a destroyed mutex (0x779415a1c4)
F libc: Fatal signal 6 (SIGABRT) in tid 5995 (com.android.nfc), pid 5995
```
It restarted and recovered: adapter `mState=on`, `android.hardware.nfc.INfc/default`
registered, `nfc` service present, zero NfcService/NfcNci errors afterwards. NFC
trouble is noted historically (§ near line 2344, com.android.nfc ANR-loops) but
this specific abort is not recorded anywhere. A destroyed-mutex FORTIFY abort is a
genuine race in the NFC native layer, not a config problem.

**2. One WLAN F-level kernel line, never recorded before:**
```
wlan: [123:F:DP] cdp_ipa_set_uc_tx_partition_base invalid instance
```
IPA uC transmit partition setup on the datapath. WiFi works, so it is not fatal in
practice, but nothing in the tree mentions it.

### ⚠️ INSTRUMENT CAVEAT: tombstone count is NOT a reliable crash detector here

The NFC process took `Fatal signal 6 (SIGABRT)` and produced **no tombstone and no
`DEBUG` lines at all** -- debuggerd never captured it. `/data/tombstones` was empty
before and after.

This weakens "0 tombstones" as a standalone health claim, including the way it was
used for sensorext in 0.29/0.32. The sensorext conclusion still stands, but on
CORROBORATION rather than on tombstone count alone: a single pid with no init
restarts, no `initAlsComp` abort message anywhere in the buffer, and
`ISensorExt/default` registered. When claiming a crash is gone, cite the process
lifetime and the absence of the specific abort message, not just an empty
tombstone directory.

---

## 0.32 REVIEW FALLOUT FIXED AND CONFIRMED ON DEVICE (2026-09-01)

An independent adversarial review of 0.29-0.31 broke four of six claims. Two would
have shipped. Everything below is fixed, flashed and measured on the device.

### ✅ gralloc allocator: a LIVE defect, now closed

The V1 -> V2 DT_NEEDED rewrite was catching
`vendor.qti.hardware.display.allocator-service`, which is the gralloc SERVER and
INHERITS the BnAllocator vtable (five BnAllocator symbols). Stable AIDL is
transaction-compatible but not vtable-compatible: V2 adds three methods, so
BnAllocator grows 10 -> 13 slots.

Before (measured): `service call ...IAllocator/default 16777215` returned
**Parcel(00000002)** from a V1 binary, and `E Gralloc5: Failed to get IMapper
library suffix` fired in every process touching GraphicBufferMapper, because
libui's `kIAllocatorMinimumVersion = 2` stopped it taking the Gralloc4 fallback.

After (measured on the flashed build, instrument proven alive by reading 34207
logcat lines): **Parcel(00000001)**, and **zero** IMapper-suffix errors.

⚠️ Only THAT ONE blob is excluded. Three others import from the allocator library
too (`com.qti.chi.override.so`, `libcamximageformatutils.so`, `libchifeature2.so`)
but their only import is the STATIC helper `IAllocator::fromBinder` -- no vtable --
and they link BOTH V1 and V2 natively with no `;DISABLE_DEPS`, so excluding them
would reintroduce the soong dual-version error. **Import count is not the test;
ask whether the blob inherits a Bn* vtable.**

⚠️ `PRODUCT_PACKAGES += android.hardware.graphics.allocator-V1-ndk.vendor` -- the
`.vendor` suffix is load-bearing. The bare name installs the CORE variant and puts
nothing in /vendor/lib64 while the build still succeeds.

### ✅ launcher 3x3 -> 4x5, confirmed

`inv.numColumns: 4`, `inv.numRows: 5`, `numShownHotseatIcons: 4` (was 3/3/3).
Screenshot `logs/foldtests-2026-09-01/main-screen-after.png`: the DeskClock widget
places and renders clock + date legibly, hotseat has four evenly spaced icons.

⚠️ This is the FIRST REAL TEST of 69cb196. `default_workspace_4x5.xml` had never
been read on this device -- a 3_by_3 grid loads `default_workspace_3x3.xml`, which
has no `appwidget` element at all -- so the `spanY=2` placement and the date-ratio
change were previously unexercised. Both hold.

### ✅ sensorext still clean, 0 tombstones after a full vendor rebuild.

### Regression sweep after the flash

8 cameras + provider running; both panels enumerated; all four touch/gesture input
devices (`goodix_ts`, `gdx_cli_0`, `double-tap`, `s-double-tap`); 79 sensors;
device state commits `OPENED`. 216 AVC denials, 134 of them the deliberate
`hal_sensors_default` trade.

### ⚠️ FOUR near-misses this session, all the same failure

The build's exit code says nothing about what went into the image:

1. `cp -p` from the firmware dump gave a blob a **2009** mtime; ninja skipped the
   copy and shipped the OLD binary. `m` succeeded, `check_elf_file` PASSED (it only
   checks symbol resolution, not that DT_NEEDED matches).
2. `PRODUCT_PACKAGES` with a bare module name installed **nothing**; the build
   succeeded and the vendor image's gralloc server linked a library that was absent.
3. `m Launcher3QuickStep` rebuilt the apk but NOT `system_ext.img`, and `super` was
   packed from an image **10.5 hours stale**. Caught by comparing mtimes.
4. A `mScreenState` metric that could not detect the thing it was used to judge,
   and a `grep` pattern that returned zero because the dump format differed.

**Verify the ARTIFACT: `stat`/`md5sum` the file in `out/` against its source, and
prove the instrument can produce a non-zero result before trusting a zero.**

### ✅ The c2 mediaserver abort was DOWNSTREAM OF THE GRALLOC BUG, and is gone

Measured on the flashed build, without any c2-specific change being made:

```
tombstones                                  0    (was 1, mediaserver)
"does not have IConfigurable" in logcat     0    (was the abort message)
avc denied ... custom_version_prop          0    (was 4)
Gralloc5 "IMapper library suffix" errors    0    (was firing)
media.audio.qc.codec  pid 2723, ETIME 04:57      (was pid 8102, ~25 s and four
media.hwcodec         pid 2717, ETIME 04:57       init restarts behind hwcodec)
init: starting service 'vendor-qti-media-c2audio-hal-1-0' ... has pid 2723
                                            single start, no restart lines
mediaserver           pid 3079, no restart, 30 unique c2.qti.* codecs present
```

**The causal chain.** `vendor.qti.media.c2audio@1.0-service` does not link the
allocator directly, but its closure reaches
`android.hardware.graphics.allocator-V2-ndk.so` **via libui.so** (66-lib closure,
measured). While the allocator server lied about being V2, libui's Gralloc5 path
(`kIAllocatorMinimumVersion = 2`) engaged instead of falling back to Gralloc4 and
failed with "Failed to get IMapper library suffix" -- so graphic-buffer setup was
broken in every process using it, c2audio failed at startup, init restarted it
four times, and mediaserver aborted holding a binder to an instance that had just
died.

⚠️ **The `custom_version_prop` denial was a SYMPTOM, not a cause.** It was the
recommended thread to pull, and granting it would have been treating a symptom of
a bug three layers down. It disappeared on its own when the gralloc lie was fixed,
with no sepolicy change. This is the [[a-denial-can-be-load-bearing]] lesson from
the other direction: before granting a denial, ask what is upstream of it.

⚠️ Instrument note: `logcat -b all -d | grep -c "starting service"` returns 0 by
~6 minutes of uptime because the 256 KiB buffer has already wrapped past boot. The
single-start evidence above was captured earlier and corroborated by ETIME, not by
that count.

### Still open
- Emergency calling, the last MUST, now needing setup again after this wipe.
- Two upstream patches awaiting a LineageOS Gerrit username.

---

## 0.29 SENSOREXT, PHANTOM HALs, AND TWO DECISIONS CLOSED (2026-09-01)

Four open items from the previous handover, all closed. Everything here is
committed; nothing needs a re-derivation.

### sensorext SIGABRT: a blob fixup, not sepolicy — FIXED

`motorola.hardware.sensorext-service` aborted four times per boot in
`SensorExt::initAlsComp`. The cause was `.replace_needed('libtinyxml2.so',
'libtinyxml2_1.so')` in `device/motorola/arcfox/extract-files.py`, whose stated
premise ("built against 10.x") is false for this binary. Full evidence, and the
0x68-vs-0x70 test that decides which tinyxml2 a blob wants, in the corrected
block at §"FALSIFIED" below and in the commit. Fixup removed; blob restored
unpatched.

✅ **CONFIRMED ON A FLASHED BUILD 2026-09-01.** After a clean flash and wipe:
**zero** tombstones naming sensorext (was four per boot), and
motorola.hardware.sensorext-service is up on a single pid with no restarts.
⚠️ Still NOT proven: that ALS compensation actually FUNCTIONS. No crash is not
the same as working -- /mnt/vendor/persist/sensors is unreadable without root and
`adb root` is unavailable even on this userdebug build.

⚠️ **A near-miss worth keeping.** The first build of this fix silently shipped the
OLD blob. Restoring it from the firmware dump with `cp -p` gave it the dump's
mtime of 2009-01-01, older than everything in out/, so ninja skipped the copy.
`m` reported success and `check_elf_file` PASSED -- it only checks that undefined
symbols resolve among the declared shared_libs, not that DT_NEEDED matches. Caught
only by stat-ing the file inside out/.../vendor/bin/hw against its source
(144161 vs 106576). `touch` any hand-placed blob, and verify the artifact rather
than the build's exit code.

⚠️ **The generalisable lesson**: the crash is in a BINDER TRANSACTION handler,
so init restarts the service, the caller retries, and the process is alive by
the time anyone looks. `init.svc.*`, `ps` and even a late `logcat` all show
health. Only `/data/tombstones` showed the truth — and tombstones survive
reboots. Check them before concluding a service is fine.

### manifest_cliffs.xml: nine phantom HAL declarations pruned

⚠️ **EVIDENCE CORRECTED (independent review).** The original claim -- "no server
anywhere in the vendor image (only the generated interface libs carry their
descriptors)" -- is FALSE. The built image holds a server artifact for every one of
the nine, four named for the pruned fqname exactly
(`bin/hw/com.motorola.hardware.display.touch@1.2-service`,
`motorola.hardware.camera.desktop@2.0-service`,
`motorola.hardware.health.storage@1.0-service`,
`vendor.zui.hardware.ifaa@1.0-service`) plus four `-impl.so` passthroughs. The
original search excluded any file whose name began with the interface package,
which excluded the servers themselves.

The REAL reason nothing serves them: commit `7d26208` deleted their init `.rc`
files (`etc/init` went 143 -> 121). A configuration fact, not a property of the
blobs. The prune is still correct for what we ship, but it is downstream of our own
`.rc` removal -- restore any of those `.rc` files later and the manifest entry must
come back with it, or the service starts and fails to REGISTER.

⚠️ "Removing a declaration cannot break a working feature" is also only half true.
Correct for HIDL (`libhidl` `ServiceManagement.cpp:924-940`: undeclared just means
an immediate `nullptr`). WRONG for AIDL --
`frameworks/native/cmds/servicemanager/ServiceManager.cpp:473-475` calls
`tryStartService()` without consulting `isVintfDeclared`. Safe here because nothing
serves these nine, but the general claim does not hold.

⚠️ The wifilearner carve-out is right to keep, wrong as reasoned: its stated
distinguishing property ("unlike these nine it HAS a real server") is shared by all
nine, and it is equally unstartable -- its `.rc` exists only in stock.

Confirmed as stated: no registration in `lshal list -i` / `service list`. Removed via a new
idempotent **fixup 5 in `fix-vendor-blobs.sh`** — the file is a shipped blob and
a re-extract restores stock's copy byte for byte, so the edit cannot live in the
tree. `--check` mode gates it.

✅ **CONFIRMED ON THE FLASHED BUILD:** `lshal --types=lazy` fell from **13 to 4**.
The four survivors are exactly the ones this fixup does not target --
`media.c2 .../default2`, `ListenSoundModel`, `IQtiMapper` (a passthrough, probably
a false positive) and `wifilearner`.

⚠️ **NEW. Probably not caused by the prune, but that is UNPROVEN.**
`mediaserver` SIGABRTs once per boot at ~10 s uptime:

```
Check failed: transResult.isOk() Codec2 service "default2" does not have IConfigurable.
```

⚠️ **ROOT CAUSE CORRECTED. The version-mismatch story first written here was
WRONG.** `codec2/hidl/client.h:191` has `typedef HidlBase1_0 HidlBase;` -- the
client fetches **@1.0** and enumerates by the V1_0 descriptor, so no 1.2 -> 1.0
cast exists in this path. `Return<>::isOk()` is a HIDL TRANSPORT status (dead or
failed binder), not a type check; a cast failure would null `baseStore` and trip a
different CHECK.

What actually happened: **default2's server crash-looped at boot.**
`media.audio.qc.codec` is pid 8102, started ~25 s after `media.hwcodec` (pid 2653),
behind four earlier mediacodec pids at init's 5 s restart spacing. mediaserver
aborted holding a binder to an instance that had just died. Unchased contributing
signal: every instance takes `avc: denied { read } ...
tcontext=u:object_r:custom_version_prop:s0` from `u:r:mediacodec:s0`, and no rule
for it exists anywhere in `device/motorola/`.

It is still true that `default2` registers only at @1.0 while
`manifest_media_c2.xml` declares @1.2 -- that just is not what aborts mediaserver.

It is a BOOT RACE that self-heals: mediaserver restarts, and the end state is
healthy -- one tombstone, no crash loop, 13 unique `c2.qti.*` audio codecs present
(the earlier "14" here and the manifest comment's "4" are both wrong).

⚠️ **"Pre-existing" is UNPROVEN.** Established: the prune names no media interface,
and `manifest_media_c2.xml` was last modified 2026-08-11 against the prune on
2026-09-01. Not established: there is no pre-prune capture of this crash anywhere.
Because the failure is a BOOT RACE, "the prune does not name media.c2" does not
license "the prune did not cause it" -- removing nine declarations changes
hwservicemanager's boot-time work, and therefore timing.
**Open.** The likely fix is declaring `default2` at @1.0 in its own fqname while
`default` stays @1.2 -- both are major 1 inside a single <hal> entry, so the
conflict check that forced one version should not apply. Untested.

⚠️ `vendor.qti.hardware.wifi.wifilearner@1.0::IWifiStats` was deliberately LEFT
declared. It is unregistered too, but it HAS a real server
(`/vendor/bin/wifilearner`). That is a "why does it not start" question and
deleting the declaration would hide it. **Open item.**

### allocator V1 -> V2: keep it, and it was never a rule violation

The 74-blob rewrite does not contradict "ship the library version the blob
wants". That rule is about unstable C++ ABIs where offsets move. Measured: these
blobs import ZERO symbols from the allocator library — the V1 soname is in
DT_NEEDED and in no UND entry, i.e. a link-line artifact, not a call surface —
and the interface is stable AIDL besides. Reasoning recorded in extract-files.py.

### Two patches are upstream-ready but NOT sent

`DigitalAppWidget: size the clock from the host's real bounds` (DeskClock) and
`clean_headers: drop struct sched_param from the generated uapi header`
(vendor/lineage). Both carry Change-Ids, both are device-neutral (the arcfox
date-ratio tweak is a separate commit that stays local). **No Gerrit remote or
username is configured on this host**, so upload needs the operator:

```
git push ssh://<user>@review.lineageos.org:29418/LineageOS/android_packages_apps_DeskClock \
    HEAD~1:refs/for/lineage-23.2
git push ssh://<user>@review.lineageos.org:29418/LineageOS/android_vendor_lineage \
    HEAD:refs/for/lineage-23.2
```

### Denial count corrected

See the SELinux block in the charter section: the shipped config carries 140
`hal_sensors_default` sysfs denials per boot by design, and the old "699 -> 73"
headline was measured with those grants enabled.

---

## 0.28 EXT-MODULE BUILD-OUT: 284/287 FROM MOTOROLA SOURCE (2026-08-28, cont.)

Eleven build passes (v1..v10 + focaltech/kiwi finals). Every fix lives in
build-kernel-modules.sh's override table or patches/; logs in scratchpad emlogs/.

### FINAL TALLY vs the 287 shipped vendor_dlkm
  BUILT FROM SOURCE: 284   (+ all 60 system_dlkm, signed)
  qca_cld3_kiwi_v2 : EXCEPTION after 7 attempts (v10..v17) -- build from the
                     XIAOMI tree as documented interim (loses Motorola's
                     hdd MAC-from-serialno additions; see 0.24). Findings kept:
                     - CONFIG_QCA_CLD_WLAN_PROFILE=kiwi_v2 loads the defconfig
                     - published-source defect #5: kiwi_v2_defconfig omits BOTH
                       CH_AVOID flags while an inherited default enables only
                       FEATURE_WLAN_CH_AVOID_EXT -> struct/user gate mismatch
                       (-DFEATURE_WLAN_CH_AVOID is the parity fix)
                     - ⚠️ NONDETERMINISM: identical invocations reached
                       different depths (v13 vs v16/v17, clean objdir ruled
                       out for v17) -- qcacld's include assembly is sensitive
                       to state we never fully pinned. 16-pass log in emlogs/.
                     - ⚠️ faithfully replicating CLO Android.mk vars (v14)
                       REGRESSED a deeper synthetic invocation -- those vars
                       flip Kbuild branches; minimal-delta beats faithful-copy.
  moto_swap        : EXCEPTION -- stock contains hybridswap (393 strings) but
                     the mem_cgroup_hybridswap kernel fields were NEVER
                     PUBLISHED; cannot reach stock parity from source. Ship
                     prebuilt, documented.
  qca_cld3_qca6750 : second WLAN variant; Motorola's qcacld has no
                     qca6750_defconfig. Likely never loads on arcfox (kiwi_v2
                     is the active chip per CONFIG_MOT_CNSS_KIWI_V2). Decide:
                     Xiaomi-tree build or prebuilt exception.

### PUBLISHED-SOURCE DEFECTS (Motorola tag), all patched in patches/
1. camera-kernel Kbuild omits cam_ois_dw9784.o + cam_ois_sem1217s.o (stock has
   both; cam_ois_core calls them). +2 lines.
2. video-driver Kbuild omits the cliffs platform (inc + cliffs.o) although
   msm_vidc_platform.c hard-includes msm_vidc_cliffs.h under MSM_VIDC_PINEAPPLE.
   NOTE: link ONLY cliffs.o -- msm_vidc_cliffs.c is an unlinked legacy duplicate
   (pineapple has the same pair, only pineapple.o linked).
3. datarmnet Kbuild defines -DRMNET_LA_PLATFORM but headers test
   CONFIG_RMNET_LA_PLATFORM -> stub inlines collide with real defs. -D fixes.
4. moto_swap kernel-side hybridswap memcg patch unpublished (above).

### KEY BUILD FACTS DISCOVERED (full table in build-kernel-modules.sh)
- audio-kernel silently builds NOTHING without MODNAME=audio_dlkm
  BOARD_PLATFORM=pineapple (Motorola's Makefile, unlike Xiaomi's, passes
  neither). "OK with 0 .ko" -- always count artifacts.
- camera needs TARGET_PRODUCT=rtwo AND CONFIG_AF_NOISE_ELIMINATION=y (the
  latter exists only in moto-pineapple-ctwo.config, yet stock arcfox exports
  the gated symbols -- blob parity decides).
- focaltech needs CONFIG_INPUT_TOUCHSCREEN_MMI in BOTH planes: -D for cpp AND
  make var for the object list. Its legacy fb-notifier path cannot compile on
  this kernel; stock proves it compiled out (0 notifier imports).
- Config-in-two-planes is the GENERAL pattern: CLO KBUILD_OPTIONS vars gate
  Makefile object lists, -D gates headers. When a module "builds" but misses
  exports, or compiles files it should not, check the OTHER plane.
- Dependency chains (KBUILD_EXTRA_SYMBOLS): dataipa BEFORE datarmnet (ipam.ko
  exports ipa_rmnet_ll_xmit); bm_adsp_ulog before qti_glink_charger before
  {sc760x,qpnp_adaptive,mmi_lpd}; sensors+mmi_relay+mmi_info+display feed
  touchscreen_mmi which feeds the 3 panel drivers; securemsm feeds bt-kernel
  (+ -I securemsm/include) and camera and display.
- moto_sched BUILT -- needs -I to its own root + kernel srctree. The reviewer's
  "can never load without the walt patch" is satisfied by Motorola's kernel
  natively. Same for ps5169, UFS vendor stack: Route-A dividends.
- ⚠️ REGRESSION TRAP: passing KBUILD_EXTRA_SYMBOLS on the command line
  OVERRIDES a module Makefile's own internal chaining. Only pass it when the
  Makefile has none (check first).

### PROCESS FAILURES THIS SESSION (own goals, for the record)
- Announced "proceeding with v8" without the launch command ever running.
- A watcher hung on pgrep matching ITS OWN command line -- the exact trap in
  memory `time-the-operation-not-just-its-exit-code` lineage. AGAIN.
- First swap-harness run reported 100% false failures (2>/tmp_err on Android's
  read-only /). con_dfpar remains unloadable until next reboot (driver leaks
  its /proc entry on rmmod -- NEVER hot-swap it).

### NEXT
1. kiwi v14 result; qca6750 decision.
2. Step-3 BoardConfig rewire (LAST reviewer-sequence item).
3. CRC-compare the full source set vs stock; then boot-chain assembly.

---

## 0.27 VALIDATION + SIGNING DONE; BACKUPS TAKEN (2026-08-28)

Executes 0.26's NEXT list, steps 1-2-4. Step 3 (BoardConfig rewire) still open.

### Step 1 — live insmod validation on the running kernel: PASS (17/18 swaps)
22-module test set spanning both build configs (merged-tree in-tree + ext),
swap-tested on the RUNNING 6.1.145 GKI (rmmod stock -> insmod ours -> restore):
17 OK, 2 busy-skips, 2 not-vendor_dlkm skips, and exactly ONE real failure:
- rmnet_offload: EINVAL, dmesg "disagrees about version of symbol
  rmnet_frag_deliver" -- OUR build vs the LIVE stock rmnet_core. This is the
  predicted inter-module CRC drift DEMONSTRATING the coherent-set rule live:
  our module refuses a mixed set, loudly, instead of corrupting. Working as
  designed; ships fine WITH our rmnet_core.
NEGATIVE TEST (the signing theory, proven on device): our UNSIGNED mac802154
(13 exported syms) -> insmod = Permission denied, dmesg "mac802154: exports
protected symbol ieee802154_alloc_hw" = main.c verify_exported_symbols() firing
exactly as predicted. Stock signed module restored fine.
⚠️ CASUALTIES/LESSONS:
- con_dfpar is UNLOADED until next reboot: its exit path leaks /proc/con_dfpar,
  so after rmmod NOTHING (ours or stock) can load it again -- "proc_dir_entry
  already registered". This driver can never be hot-swapped; update flows must
  never rmmod it. Harmless meanwhile (refcount-0 utility).
- ⚠️ First harness run reported 100% false failures: `2>/tmp_err` on Android's
  READ-ONLY / made the shell fail the REDIRECT, so insmod never ran. Redirect
  stderr to /data/local/tmp. Same shape as the locale trap: the harness, not
  the subject.

### Step 2 — module signing: DONE and cryptographically verified
Fragment: patches/kernel-config/arcfox-signing.config (MODULE_SIG_ALL=y +
SHA256; pineapple_GKI.config unsets it and gki uses sha1). Result: 332/332
installed modules signed sha256; key certs/signing_key.pem in O= is generated
ONCE and survives re-invocations (verified by md5 before/after); the signing
cert IS embedded in our Image; tipc.ko's CMS signature VERIFIES against that
cert and FAILS against Google's shipped tipc.ko (negative control). So a
self-built Image + our system_dlkm is a self-consistent signed set.
THREE traps encoded in build-kernel-modules.sh `install`:
1. The BoringSSL in prebuilts/kernel-build-tools REFUSES SHA256 in sign-file.
   Host OpenSSL 3.x is required -- and the r34 merge fixed certs/extract-cert.c
   (key_pass now unconditional), so the BoringSSL HOSTCFLAGS crutch from 0.25
   is no longer needed at all on the merged tree.
2. A stale scripts/sign-file keeps its old RPATH (BoringSSL) even after
   HOSTCFLAGS change -- delete the binary AND .sign-file.cmd.
3. modules_install must run SERIALIZED after Image+modules: a combined -j32
   goal races install jobs against the sign-file relink (Error 127).
Verification one-liner for kernel CMS sigs: openssl cms -verify -binary
-inform DER -in sig.p7 -content payload -CAfile cert -certfile cert (kernel
signatures are NOATTR/NOCERTS; `openssl smime` fails on them by design).

### Step 4 — last-good backups: $HOME/android/arcfox-backups/last-good-20260828/
boot_a+b, init_boot_a, vendor_boot_a, dtbo_a, vbmeta_a, vbmeta_system_a pulled
(boot_a verified = the running ab14763719 GKI); super.img (8.5 GiB) pulled with
head-64MiB md5 cross-check vs device. Remember: super is NOT A/B -- this file
is the ONLY rollback for vendor_dlkm/system_dlkm.

### STILL OPEN before a flash
- Step 3: BoardConfig rewire (peridot/sm8550 shape), drop
  TARGET_NO_KERNEL_OVERRIDE, delete 629 committed .ko + prebuilt/Image.
- Rebuild ALL ext modules against the merged tree + regenerate dtb/dtbo or keep
  prebuilt (manaus precedent).
- Boot chain assembly: boot.img from our Image (+ our system_dlkm in super,
  vendor_dlkm from our set). fastboot boot alone CANNOT test this (0.26).

---

## 0.26 ACK MERGE DONE (r34), AFTER AN INDEPENDENT REVIEW CORRECTED 0.25 (2026-08-28)

Kernel branch `arcfox-ack-merge` HEAD = `78ad201f48ae`, SUBLEVEL **145**, clean.
An adversarial review of the merge + a "should we even build the kernel"
analysis ran first; its findings were spot-checked by hand before acting.

### ⚠️ CORRECTIONS TO 0.25 — three of its claims were wrong
1. **The abort rationale was BACKWARDS.** "Do not auto-resolve core MM/KVM
   hunks" pointed at exactly the SAFE files. Classification by blob identity
   (ours vs the r14 import tag): 9 of the 14 code conflicts had ours ==
   byte-identical to the tag — pure older ACK code, `--theirs` provably safe —
   and that set contained EVERY scary file (mm/userfaultfd.c, KVM mem_protect,
   net/unix/garbage.c, eventpoll, vendor_hooks). The REAL work was 5 mundane
   QCOM driver files. See memory `classify-merge-conflicts-by-blob-identity`.
2. **The merge target was wrong.** ack/android14-6.1 head (6.1.176) was the
   most expensive of seven measured candidates (63 genuine hunks) and leaves
   the certified sublevel family. `android14-6.1-2025-09_r34` (SUBLEVEL 145 =
   the family the phone boots; flashed GKI is r28 of the same family) costs the
   SAME 5 genuine files as the idiomatic ASB tag while being 12 months fresher.
   That is what was merged.
3. Misc: "6,193 files merged cleanly" was total-touched, not clean (5,991 M);
   and 0.25's gloss "the 6,347 tag-diff files are Motorola drivers/dts" was
   wrong — 4,852 of them are Motorola DELETING Documentation/devicetree.
   Also: the `-s ours` ancestry commit records ancestry only to the tag's FORK
   POINT with the ack branch (the tag is on a release side-branch), leaving a
   61-commit gap that self-inflicted 30 of the original 93 hunks as
   empty-base artifacts.

### What was merged and how (full rationale in commit 78ad201f48ae)
21 conflicts: 7 doc-deletes (git rm), 9 Class-A (--theirs, each verified
ours==tag before AND staged==r34 after), 5 hand-resolved:
  clk-alpha-pll: keep Motorola's mask block; combine NULL-guard + checked read.
  qcom_edac: KEEP OURS — upstream's fix dereferences drv->edac_reg_offset which
    Motorola's llcc-qcom.c NEVER populates (NULL deref at probe); Motorola's
    own edac_regs[] already selects INTERRUPT_0, so the fix's substance exists.
  sdhci-msm: upstream 3-arg regulator refactor wins (auto-merged caller already
    3-arg); Motorola's 1-arg set_vmmc was byte-identical to base -> dropped.
  pinctrl-msm: union of declarations minus dead was_enabled.
  q6v5_mss: r34's msm8974 descriptor wholesale (foreign SoC static data).
VALIDATION: build OK (Image 35,367,424 B, 332 modules); KMI: all 347 shipped
prebuilts vs merged Module.symvers = 20,475 CRC match / 0 mismatch — identical
to the pre-merge measurement. The merge is KMI-invisible, as the frozen-KMI
theory predicts.

### The architecture question ("build own kernel at all?") — reviewed verdict
ARCH-2 (prebuilt Google GKI + prebuilt Google system_dlkm + source vendor_dlkm)
is charter-legal (device-support-requirements.md:216) and technically clean —
the 60 system_dlkm are arguably NOT "feasible" to rebuild since the signing key
and the Image's un-extendable builtin keyring bind within one build. BUT: zero
of 310 official devices use the prebuilt-GKI allowance; the charter bullet was
authored (commit 873eada4) to RETIRE the old Pixel exception, and Pixels moved
to source builds. VERDICT: **ARCH-3, full source, three-repo LineageOS layout
mirroring android_kernel_motorola_sm8550** — with ARCH-2 kept as the documented
fallback. Key discovery: LineageOS leaf kernels are THIN forks; ASB merges land
once in a shared base (android_kernel_qcom_sm8650) and leaves inherit them, so
ARCH-3's recurring merge cost is inherited, not owned. A merge backlog at
submission is demonstrably acceptable (official Pixels sat 4 months stale on an
ACK pin; several official Moto kernels are 6-19 months stale; currency is a
charter SHOULD).

### NEW defects the review found (open)
- ⚠️ `TARGET_NO_KERNEL_OVERRIDE` is a GSI/Cuttlefish-only variable (16 upstream
  users, ALL virtual devices); arcfox uses it on a physical device. Remove it
  during the Route-A BoardConfig rewire.
- ⚠️ `CONFIG_MODULE_SIG_ALL is not set` (pineapple_GKI.config:88) and
  MODULE_SIG_HASH="sha1" vs shipped sha256 — "ARCH-1 signing is automatic" is
  FALSE as the tree stands. Before any self-built Image: MODULE_SIG_ALL=y,
  sha256, Image+modules in ONE invocation (a fresh O= regenerates the key and
  silently invalidates every signature). build-kernel-modules.sh now carries a
  TODO(signing) block; it also had clang-r574158 at line 43 contradicting 0.25
  (fixed to r547379).
- ⚠️ `super` is NOT A/B (boot/init_boot/vendor_boot/dtbo/vbmeta are; super is
  single). vendor_dlkm/system_dlkm live inside super -> NO slot rollback for
  the module half. Any flash plan must back up super (or its logical images)
  first, and `fastboot boot` of a self-built Image is NOT a sufficient test:
  the on-device system_dlkm is signed with the PREBUILT Image's key, so 25
  protected-symbol exporters (bluetooth, tipc, wwan, rfkill...) would -EACCES.
- sig_enforce is compile-time false (kernel/module/signing.c:26-35), so
  unsigned self-built vendor modules CAN be insmod-validated on the RUNNING
  kernel with zero flashing — that is the pre-flash validation path.

### NEXT
1. insmod-validate a broad set of self-built vendor_dlkm on the running kernel.
2. MODULE_SIG_ALL=y + sha256; one-invocation build; verify 60 system_dlkm signed.
3. Route-A BoardConfig rewire (peridot/sm8550 shape), drop
   TARGET_NO_KERNEL_OVERRIDE, delete the 629 committed .ko + prebuilt/Image.
4. Back up super + last-good images BEFORE any flash (authorized).

---

## 0.25 ROUTE A: MOTOROLA'S OWN KERNEL, + DISPLAY SOLVED, + ACK ANCESTRY (2026-08-27)

Supersedes 0.24's base choice. Scripts: `setup-kernel-repos.sh`,
`patches/display-drivers/`, `build-kernel-modules.sh`.

### The base question is settled by measurement, not argument
Two independent reviews (technical + LineageOS-compliance) both rejected the
LineageOS/Xiaomi kernel for a Motorola device. Decisive numbers:
  Motorola config symbols surviving olddefconfig:  Motorola base 20/20
                                                   Xiaomi base    0/5 sampled
  in-tree vendor_dlkm modules built:               Motorola 173/287 (= 0.20's
                                                   predicted 173), Xiaomi 172
  ps5169.ko (in modules.load, bound to dwc3_msm):  Motorola BUILDS, Xiaomi cannot
  set_moto_sched_enabled/_ops:                     Motorola exports, Xiaomi 0
  UFS vendor feature set:                          Xiaomi has no drivers/ufs/host/vendor/
Compliance census (655 official repos, 7,831,645 paths): ZERO committed .ko
anywhere; all 46 official Motorola devices build from source; cross-vendor kernel
sourcing is 1-in-310 (nintendo_nx -> nvidia, same silicon). Our tree has 629
committed .ko -- that is the hard blocker, and building from source removes it.
⚠️ Prebuilt GKI from Google IS charter-permitted ("GKI devices MAY use either a
source-built kernel or a prebuilt GKI image from Google, but MUST build all
feasible modules from source") -- but ZERO of 310 devices use that allowance.
⚠️ `TARGET_PREBUILT_KERNEL` does NOT mean "ship a binary": build_kernel() at
vendor/lineage/build/envsetup.sh:931 repo-inits a kernel manifest, builds, and
copies into TARGET_KERNEL_DIR. 0.19's reading (and TARGET_NO_KERNEL_OVERRIDE)
is inverted from upstream.

### RESULT: Motorola kernel builds
Image 35,359,232 B, 332 modules, SUBLEVEL 128, Module.symvers, from
MotorolaMobilityLLC/kernel-msm @ MMI-W1UXS36H.72-45-4-1.
⚠️ THREE toolchain workarounds, all "Jan-2026 tree meets Aug-2026 toolchain",
none a source defect: BoringSSL for certs/extract-cert.c; libbpf needs
-Wno-incompatible-pointer-types-discards-qualifiers (plain -Wno-error is NOT
enough on 6.1.128); clang-r547379 (clang 20) NOT r574158 (clang 21), which trips
-Wdefault-const-init-field-unsafe in list.h/mount.h/fs.h; plus
KCFLAGS=-Wno-error=format for 27 printk sites in Motorola's own walt.c/gunyah/
mhi/qcom-pdc/af_qrtr.

### ⚠️ 0.24's DISPLAY CLAIM WAS WRONG, AND THE GAP IS NOW CLOSED
"NT37705A is arcfox's actual panel" was inferred purely from a symbol name.
arcfox's LIVE panel is `csot_nt37707_667_1080x2640_dsc_cmd_v3` (read off the
device). The shipped msm_drm.ko has ZERO nt37707 references and four nt37705 ->
mot_nt37705A_display_read_cellid is DEAD CODE for another Motorola device.
The panel needs NO Motorola driver: all 297 properties in its dtsi are standard
qcom,* (zero mot,*/moto,*), and Motorola DOES publish that dtsi in
`kernel-display-devicetree` @ our tag. Only a SYSFS CONTRACT was missing.
Reimplemented in patches/display-drivers/ (msm_drm.ko builds, all 9 attrs
present): panelName (DT node name minus "qcom,mdss_dsi_mot_" -- reproduces the
stock string exactly), panelSupplier (qcom,mdss-dsi-panel-supplier),
panelBLExponent (qcom,mdss-dsi-bl-is-exponent), panelCellId empty, panelVer 0,
panelDC/panelPcdCheck 0, panelId + panelEnableSfBrightZone DT-overridable.
PRIMARY connector only (stock exposes none on the cover, card0-DSI-2) and
panelDeclare deliberately NOT created (absent on stock too; init.mmi.touch.sh
tolerates it). Consumers: init.mmi.touch.sh, displaypanel.default.so,
hardware_revisions.sh, mot_tcmd, motorola.hardware.sensorext-service,
als_comp_config*.xml.
⚠️ Motorola publishes no display-DRIVERS for this train, so we build Xiaomi's.
It calls mi_display_pwrkey_callback_set(), a Xiaomi patch to
drivers/input/misc/pm8941-pwrkey.c absent from Motorola's kernel -> stubbed.
Removing mi_disp/ outright is the cleaner end state but is NOT supported in
Xiaomi's tree: 297 mi_* refs across 12 CORE display files with INCOMPLETE
guards (sde_connector.c:2956 dereferences panel->mi_cfg unguarded).

### ACK MERGE: ancestry recorded, merge NOT taken
⚠️ Motorola IMPORTED GKI rather than merging it. Their HEAD says "Merge source
code with GKI android14-6.1-2025-03_r14", but that tag is NOT an ancestor of
HEAD and git's merge-base falls back to 6.1.57 (Dec 2023) = 22,826 commits.
Verified their claim is true in CONTENT before acting: kernel/sched/core.c and
mm/memory.c are byte-identical to the tag; fs/ and security/ differ in ZERO
files (the 6,347 differing files are Motorola's own drivers/dts).
So `git merge -s ours android14-6.1-2025-03_r14` records the missing ancestry --
commit 855226bb on branch `arcfox-ack-merge`, **0 files changed** -- moving the
merge base to 471a10d3 and cutting the work to 10,537 commits (6.1.128->6.1.176).
The real merge was ATTEMPTED and ABORTED, deliberately: 6,193 files merged
cleanly but 51 files / **93 hunks** conflict. 18 are Documentation/*.yaml
(modify/delete, trivial). The other 33 are real code and include mm/userfaultfd.c
(7 hunks), arch/arm64/kvm/hyp/nvhe/mem_protect.c, net/unix/garbage.c (6),
fs/eventpoll.c, drivers/android/vendor_hooks.c, plus soc/qcom, remoteproc,
pinctrl, rpmsg, slimbus, qrtr, mhi, stmmac, sdhci-msm (9).
⚠️ DO NOT auto-resolve core MM/KVM hunks and flash. A wrong resolution there is
silent memory corruption, not a failed boot. Tree is left clean and buildable at
SUBLEVEL 128 with the ancestry commit kept; tag `backup/pre-ack-merge` is the
pre-ancestry state. Re-run `git merge ack/android14-6.1` to resume.

### STILL NOT BOOTED
Everything in 0.24 and 0.25 is compile-time / symbol-table evidence. The ONLY
runtime datapoint remains one insmod rc=0 against the OLD 6.1.145 GKI.
⚠️ Module SIGNING is unresolved and blocks any boot test on a self-built kernel:
CONFIG_MODULE_SIG_PROTECT=y, 60/60 shipped system_dlkm are signed, 25 of them
EXPORT protected symbols (bluetooth.ko 77, can-dev.ko 37, l2tp_core.ko 21...),
and build-kernel-modules.sh never signs. A self-built Image can NEVER mix with
the PREBUILT system_dlkm (Google's key is baked into the prebuilt Image).

---

## 0.24 KERNEL MODULES BUILD FROM SOURCE — 276/287 (2026-08-27)

The official-support blocker of §0.20 is largely dismantled. Build script:
`build-kernel-modules.sh` (workspace root, unversioned like the rest).

### The ABI question is SETTLED — vermagic never had to match
`same_magic()` (kernel/module/main.c) skips everything up to the first space when
a module carries CRCs, comparing only `SMP preempt mod_unload modversions
aarch64`. The shipped prebuilts already say `6.1.145-...-12614-g4d093a72e6ad`
while the running kernel is `6.1.145-...-ab14763719` — different, and they load.
PROVEN: 11 of 12 Aug-18 modules built against Motorola's **6.1.128** are
CRC-identical to the shipped prebuilts; one was `insmod`-ed on the live 6.1.145
GKI (rc=0, size 16384 vs stock 20480, then restored). `msm-mmrm.ko` built against
**6.1.174** is CRC-identical in all 42 symbols. See memory
`vermagic-is-not-the-module-abi`.
⚠️ The converse holds: **non-KMI (vendor) symbol CRCs DO drift.** Of the 276 built,
162 are CRC-identical to the shipped prebuilts and 114 differ; 12 of 60
system_dlkm and 70 of 172 in-tree vendor modules differ across 6.1.145 -> 6.1.174.
So kernel + system_dlkm + vendor_dlkm MUST ship as ONE coherent set. Mixing is
exactly what caused the §0.19 disaster.

### What builds
Base = `kernel/motorola/sm8635` = **LineageOS/android_kernel_xiaomi_sm8635 @
lineage-23.2 (6.1.174)**, driven by LineageOS `kernel.mk` CLASSIC KBUILD — **not
bazel**. Reference device is **peridot** (POCO F6, same SM8635/pineapple); its
BoardConfig.mk is the template (`TARGET_KERNEL_SOURCE`, `TARGET_KERNEL_CONFIG`,
`TARGET_KERNEL_EXT_MODULE_ROOT`, `TARGET_KERNEL_EXT_MODULES`).
Kernel: Image 35,576,320 B (prebuilt is 35,564,032), 346 modules, `6.1.174-gfb4bafa4289e`.
  in-tree            172 / 287   (§0.20 predicted 173)
  QTI techpacks       29 / 30 dirs -> 93 .ko
  Motorola drivers    ~30 of 91 dirs
  TOTAL              275 / 287   <- CORRECTED, and see the warning below

⚠️ **"275/287" IS A BASENAME COUNT AND BADLY OVERSTATES PROGRESS.** Two independent
reviewers dismantled this framing on 2026-08-27; both corrections verified by hand:
 - 276 was a PHANTOM. `have.txt` listed camera.ko, but `find` returns ZERO camera.ko:
   build-ext2.sh counts .ko AFTER the fact, so it recorded the XIAOMI-built camera.ko,
   which build-cam.sh then `rm -rf`'d before the Motorola build FAILED. Never count
   artifacts with a post-hoc `find` that cannot tell which source produced them.
 - ⚠️ The shell locale is Slovak: bare `sort`/`comm`/`join` MIS-COLLATE SILENTLY.
   Always `LC_ALL=C`. Two of the reviewer's own passes were corrupted by this too.
 - NAME MATCH != FUNCTIONAL MATCH. Of 275 matched pairs only **162** have an identical
   import-CRC set; 113 differ, 46 have a different SYMBOL SET (i.e. different source),
   41 have >=1 ship-only function. File size and srcversion are both USELESS as
   discriminators here (shipped are strip-debug'd, built carry BTF; srcversion is empty
   on 272/275 because CONFIG_MODULE_SRCVERSION_ALL is unset).
 - The 12 that do NOT build are ALL LOADED ON THE DEVICE RIGHT NOW: touchscreen_mmi
   (3 users), camera (28 users), goodix_gt96x_mmi, goodix_brl_mmi, focaltech_v3_5,
   qti_glink_charger, sc760x_charger_mmi, qpnp_adaptive_charge, mmi_lpd_mitigate,
   ps5169, moto_sched, moto_swap. That is the touch stack, the charging stack and
   camera. A device with no touchscreen does not have a "small gap".
 GOOD NEWS that survived: all 60 system_dlkm build, and all 99 vendor_boot first-stage
 modules build except ps5169.

### ⚠️ msm_drm.ko IS BUILT FROM THE WRONG VENDOR AND THE NAME HID IT
Verified by hand: the shipped msm_drm.ko exports Motorola panel symbols that our
Xiaomi-sourced build does NOT -- mot_nt37705A_display_read_cellid, moto_panel_sysfs_add,
dsi_panel_mot_parse_commands, dsi_display_motUtil_transfer (shipped 1/1/1/2, built
0/0/0/0), and the shipped module carries the string `nt37705A` -- **arcfox's actual
panel**. It never appeared in any gap list because the FILENAME matches.
⚠️ AND, unlike camera, MOTOROLA'S DISPLAY SOURCE IS NOT PUBLISHED FOR OUR TRAIN:
`vendor-qcom-opensource-display-drivers` newest tag = MMI-T1TR33.43-20-56 (repo last
pushed 2023-12-29) and `kernel-msm-techpack-display` stops at S1SUS32.73-13-4-3.
Neither has MMI-W1UXS36H.72-45-4-1. This is now the REAL unpublished-source problem
that camera turned out not to be.

### ⚠️ MODULE SIGNING IS AN UNLOGGED BLOCKER
CONFIG_MODULE_SIG_PROTECT=y. 60/60 shipped system_dlkm are SIGNED; 0/287 vendor_dlkm
are. 25 of those 60 EXPORT a protected symbol (bluetooth.ko 77 syms, can-dev.ko 37,
l2tp_core.ko 21, mac802154, 6lowpan, mii, hci_uart...). main.c:1283 gives -EACCES to an
unsigned module exporting a protected symbol. Consequences:
 - You can NEVER mix a self-built Image with the PREBUILT system_dlkm (signed with
   Google's build-time key baked into the prebuilt Image).
 - build-kernel-modules.sh runs `Image modules` only -- no modules_install, no
   scripts/sign-file -- so self-built system_dlkm would ALSO fail on those 25.

### OTHER TRAPS THE REVIEW SURFACED
 - ⚠️ TARGET_PRODUCT=rtwo. `config/rtwo.mk:13` is the ONLY definition site of
   CONFIG_MOT_SENSOR_PRE_POWERUP, and the stock camera.ko contains 6 `MotPreAct`
   strings -- so Motorola builds arcfox as rtwo. camera-kernel Kbuild only includes a
   product .mk for {hiphi*, li, oneli, eqs, rtwo}; under LineageOS TARGET_PRODUCT is
   `lineage_arcfox`, so it is NEVER included and the HAL's power-up opcodes 0x251-0x253
   would hit unhandled handlers. FORCE rtwo.mk.
 - ps5169.ko has NO source in any module tree -- it is drivers/usb/redriver/ps5169.c in
   MOTOROLA'S CORE KERNEL. It is in vendor_dlkm modules.load:96 and bound to dwc3_msm.
 - WiFi MAC: the shipped qca_cld3_kiwi_v2.ko has hdd_generate_random_mac_from_serialno
   + hdd_update_mac_serial; our build does not. Expect a randomized MAC per boot.
 - Tracepoint CRC blindness: modules importing only __tracepoint_* (moto_sched,
   moto_swap) are NOT protected by MODVERSIONS -- genksyms hashes the struct, not the
   callback signature. Drift is currently 0 across 490 shared hooks; re-run that diff on
   every kernel bump or accept silent memory corruption.
 - set_moto_sched_enabled/_ops come from Motorola's kernel/sched/walt patch (0 hits in
   LineageOS). moto_sched can never load without it; it has 0 users on-device.

### Three build gotchas, all encoded in the script
1. `HOSTCFLAGS=-I prebuilts/kernel-build-tools/.../include` (BoringSSL).
   `certs/extract-cert.c` declares `key_pass` under `#ifdef USE_PKCS11_ENGINE`
   but USES it under `#ifndef OPENSSL_IS_BORINGSSL` — host OpenSSL 3.x fails to
   compile. BoringSSL compiles that branch out. No source patch needed.
2. `-Wno-error` / `KCFLAGS` — build.config.constants wants CLANG_VERSION=r487747c
   (clang 17), the tree ships clang 21. **KBUILD_EXTRA_CFLAGS is IGNORED by
   kbuild; KCFLAGS is the one that works.** CRCs come from genksyms type
   signatures, not codegen, so a newer clang does not perturb the module ABI.
3. External modules need `M=../sm8635-modules/<path>` RELATIVE TO KERNEL_SRC, via
   their OWN Makefile. Their Kbuilds do `include $(MMRM_ROOT)/config/...` where
   `MMRM_ROOT=$(KERNEL_SRC)/$(M)`, and audio-kernel HARDCODES
   `$(OUT_DIR)/../sm8635-modules/...`. So the modules repo must be a SIBLING of
   the kernel named `sm8635-modules` — it now lives at
   `kernel/motorola/sm8635-modules` (moved out of `~/android/kernel-src`).

### §0.20 CORRECTIONS
- ⚠️ **"The 2 misses are WLAN build-variant names" — WRONG, they build.**
  `qcacld-3.0/.kiwi_v2` is a SYMLINK back to `qcacld-3.0`; the variant is chosen
  by the PATH NAME and the goal is `all`, not `modules`. `qca_cld3_kiwi_v2.ko`
  BUILT (arcfox needs `.kiwi_v2`, matching CONFIG_MOT_CNSS_KIWI_V2; peridot uses
  `.qca6750`).
- ⚠️ **"285 of 287 have source today" — OPTIMISTIC.** The techpacks available are
  **Xiaomi's**, and Motorola added code to theirs. Shipped `camera.ko` contains a
  real `mot_ois`/`dw9784` driver: 114 exported symbols vs 100 in our
  Xiaomi-sourced build, including `mot_ois_start_protection`,
  `mot_ois_stop_protection`, `mot_ois_handle_shut_down` and a 764-byte
  `mot_ois_fw_prog_download`. NOT published for our train: `kernel-msm` @ tag has
  only a Kconfig declaration, `motorola-kernel-modules` has 0 hits, and
  `kernel-msm-techpack-camera` exists (321 refs) but its newest tags are Android
  11/12-era with **no MMI-W1UXS36H tag**. §0.23 confirmed the wide camera's OIS
  WORKS — a Xiaomi-sourced camera.ko would regress it.
- ⚠️ **0 of 20 Motorola CONFIG symbols exist in the LineageOS kernel**
  (MOT_OIS_*, ARCFOX_DTB, MOT_CNSS_KIWI_V2, UFSHID, SCHED_MOTO_UNFAIR...). An
  `arcfox_GKI.config` written against it would be **INERT** — `olddefconfig`
  silently drops unknown symbols, the same dead-config trap as §0.19's
  `TARGET_PREBUILT_KERNEL`. Kernel-side porting surface is small (~15 files:
  UFS/sched/SCSI/USB-redriver); the camera OIS is the real problem.
- ⚠️ **The LineageOS kernel is XIAOMI-PATCHED.** `drivers/usb/dwc3/dwc3-msm-core.c`
  calls `get_hw_version_platform()` UNGUARDED at lines 7107/7404 to force USB gen1
  on Xiaomi projects N3/N18/O81/O82; without `CONFIG_MI_HARDWARE_ID` modpost fails
  outright. Set to `=m` (as peridot does) to unblock; the arcfox-correct fix is to
  GUARD those two call sites. Only 1 core file is affected.
  `touch-drivers` fails on `xiaomi/xiaomi_touch.h` — CORRECT, arcfox uses the
  Motorola touch drivers instead.

### The remaining 11, by class (most are NOT missing source)
- include-path only: `qti_glink_charger` (needs mmi_charger.h),
  `mmi_lpd_mitigate` (needs qti_glink_charger.h), `moto_sched` (needs the private
  `kernel/sched/sched.h`), plus the 4 touch drivers whose .c/.h are out of sync.
- REAL API drift 6.1.128 -> 6.1.174: `moto_swap` — `struct
  mem_cgroup_hybridswap` has no member `usage`. Also seen elsewhere: i2c_client
  `.remove` int->void, `FW_ACTION_HOTPLUG` renamed.
- `ps5169` — in-tree Motorola USB redriver the LineageOS kernel does not carry.

### NOT DONE — nothing is flashable yet
No device-tree wiring (`TARGET_NO_KERNEL_OVERRIDE := true` still disables
kernel.mk entirely), no arcfox config fragment, dtb/dtbo still prebuilt, and
**nothing has been booted**. Building the kernel from source also means shipping
our own system_dlkm.

---

## 0.23 BLUETOOTH AUDIO FIXED, AND GPS WAS NEVER BROKEN (2026-08-27)

Committed: `b0097dd` (interfaces, branch `arcfox-btaudio-lhdcv5`), `c408617`
(sm8635-common). Both FLASHED and verified on the image.

### A2DP was silent — and it was also halving video framerate
⚠️ **ONE defect, TWO symptoms, and I chased them as two bugs.** Silent Bluetooth
audio and a "stuttering" YouTube video had the same cause. The user found it:
*"after disconnecting bluetooth the video plays ok."*

`btaudio_offload_if.so` DT_NEEDEDs `vendor.qti.hardware.bluetooth.audio-V2-ndk.so`.
Only version 1 is frozen in `vendor/qcom/opensource/interfaces`, so `-V2-ndk`
builds from the **UNFROZEN `current`**, which defines **7 types where Qualcomm's V2
defines 9** — missing `Lhdcv5Capabilities` and `Lhdcv5Configuration`. Same soname,
**different ABI**. PAL's `init_a2dp_source()` dlopens it, the layout mismatches, and
**NOTHING IS LOGGED** — the only symptom is `a2dp handle is not identified` from an
unrelated code path, with `A2dpStateMachine state=Connected` and `mIsPlaying:false`.

MEASURED: every A2DP-routed AudioFlinger thread ran its clock at **0.40–0.51×** real
time while local threads read 1.00×. Chromium paces video off the audio clock, so
YouTube rendered **11.5–14.9 fps on A2DP vs 25.4 fps on speaker**.

FIX: add the two AIDL types. Types and order were recovered from the `AParcel_*`
sequence in `writeToParcel` of the stock library, **independently twice**, agreeing
slot for slot; the rebuilt library emits a **byte-for-byte identical** sequence.
Field NAMES are ours and are ABI-irrelevant (parcels are positional; `toString()` is
never instantiated so no name reaches the binary).

⚠️ **NEVER run `-freeze-api` on that interface** — it would make `current` become V3
and bake a V2 without these types into the tree. `update-api` only rewrites
`current/`, which is why the V2 soname survives.
⚠️ Upstream has no frozen V2 and no mention of LHDC, so a future upstream V2 will
re-break this. Re-check after every sync of that repo.

### Two dead ends, recorded so nobody repeats them
⚠️ **Do NOT disable A2DP offload.** There is no software A2DP path on this platform
(upstream deleted the `bluetooth_qti` module; BT A2DP lives in PAL's primary
module), and PAL gates `init_a2dp_source()` on
`!persist.bluetooth.a2dp_offload.disabled` — so disabling it skips the dlopen
entirely and produces the IDENTICAL error with no evidence. Official peridot ships
offload **ENABLED**.
⚠️ **A prebuilt cannot replace this library.** extract_utils names prebuilts after
the FILENAME, so stock's `.so` collides with the **system**-partition module while
the file needed comes from the auto-generated `.vendor` variant — soong:
`partition is different: system(...) != vendor(prebuilt_...)`. `FINDINGS.md` already
recorded that shape. Build from source.

### GPS: NOT BROKEN — it was untested under sky. SETTLED.
Every layer was already healthy: init, VINTF, sepolicy, blobs, QMI, AIDL HAL, and
**all 152 GNSS files md5-identical to stock**. The indoor session reported 3978 SV
status messages (~34 sats/epoch) with **`Number of CN0 reports: 0`** — a HARD BOUND,
since that counter only increments when the 4th-strongest satellite exceeds 0 dB-Hz,
and a fix needs 4. A fix was geometrically impossible indoors.

Outdoors, confirmed:
```
timeUncertaintyNs        6.0e9  -> 149      (NTP tops out ~15ms; 149ns can only
                                             come from demodulating GNSS time)
horizontalAccuracyMeters 155446 -> 21.2
```

⚠️ **`Unable to initialize IGnssPsds interface` is COSMETIC and stock-identical.**
The impl blob is md5-identical to stock and deliberately exports no
`getExtensionPsds` — PSDS is done out-of-band by `xtra-daemon`. I flagged it as
unexplained for a long time. XTRA works (`xtra_last_download_status = 0`; the
INT_MAX fields are other download types never attempted).
⚠️ `dumpsys location --gnssmetrics` **RESETS the counters**; plain `dumpsys
location -a` does not. Read `-a` FIRST — this burned an agent into concluding the
modem never started.

Still open, non-blocking: only 5 signal types are advertised (GPS L1/L5, GLONASS G1,
Galileo E1/E5a) — **no BeiDou/QZSS/NavIC** despite XTRA carrying BeiDou predictions
for 37 satellites. Modem-side over QMI, not the ROM. Costs sensitivity.

---

## 0.22 VIDEO STABILISATION (EIS) WORKS — system-level, no app patch (2026-08-27)

Committed as arcfox `05ae21b`. ⚠️ The `camxoverridesettings.txt` half is currently
live only via an `adb remount` OVERLAY — it lands in vendor.img on the next flash.

### The symptom
Video recorded fine but was completely unstabilised: **6.5px mean inter-frame
motion**, 61/80 frames jumping >2px. IPE ran `stabilizationtype 72` (SAT|MCTF —
**no EIS bit**) with an identity ICA warp.

### TWO causes; NEITHER fix works alone
**1. The Vidhance CHI nodes were not shipped.** Motorola stabilises with
**Vidhance**, not QTI EISv3 directly — CamX core is built for it (`Deferring %fx
zoom to Vidhance`). `libvidhance.so`/`.lic`/calibration shipped; the three
`com.vidhance.node.{gme,preview,video}.so` did not. Requesting EIS without them
KILLS THE SESSION: `Failed to load Chi interface for com.vidhance.node.preview` →
`Node type 255 is not supported or created` → `CreateUsecaseObject failed`.

⚠️ **The exclusion note was WRONG.** It claimed soong refuses them over
allocator V1/V2 — but `extract-files.py`'s `replace_needed` fixup rewrites exactly
that, and `com.qti.node.eisv3.so` has an identical dependency shape and had been
shipping through that same tuple all along. They build with **zero** errors.

**2. EIS was never enabled.** Blobs alone changed NOTHING (still 72, zero Vidhance
instances). `/vendor/etc/camera/camxoverridesettings.txt`:
```
EISV2Enable=1
EISV3Enable=1
overrideForceEISSupport=1
enableSATPreviewEISV2=1
```

### `enableSATPreviewEISV2` is what avoids forking Aperture — the key finding
With only the first three, EIS works for apps requesting
`CONTROL_VIDEO_STABILIZATION_MODE_ON (1)` — proven with unmodified **Open Camera**
(stabilizationtype 10/12). But Aperture PREFERS `PREVIEW_STABILIZATION (2)`, which
the HAL advertises and never wired to EIS on the SAT path. The fourth setting closes
it: **unmodified Aperture → stabilizationtype 10, 61 Vidhance node instances.**

⚠️ **Do NOT "fix" this in Aperture.** Patching `VideoStabilizationMode.getMode()`
to prefer ON was tried and REVERTED — it forks a shared LineageOS app for one
device and does nothing for third-party camera apps, which this config fixes too.

Zoom during video recording verified working, so losing the SAT bit from the mask
does not cost optical zoom in video.

### Settled, do not reopen
- **Tele has NO OIS** — hardware. Motorola's spec sheet lists OIS for the main
  camera only; HAL reports `availableOpticalStabilization [0]` for both 7.07mm cams;
  this unit's EEPROM says `oisStatus: NOT_AVAILABLE`. The wide's OIS works.
- **The NCS/CSS `interface type 1/7/8/9/10` cluster is stock-identical noise.**
  arcfox has no depth/AON camera so CSS is deliberately never created. Types 7–10
  have no factory at all. Do not theorise from it again.
- **105Hz gyro** is CamX's default `gyroSensorSamplingRate` (104.0), not a defect.
- **`Locationmap has duplicated entry`** is benign — stock declares that section
  from 4 libraries vs our 2, so stock collides harder and its EIS works.
- `libcamxevainterface.so` is NOT an EIS dependency (shipped anyway, same one-liner).

---

## 0.21 ALL 8 CAMERAS — the blob was hiding them behind a property (2026-08-24)

**`ro.vendor.qti.va_aosp.support` is why arcfox exposed 2 cameras instead of 8.**
Root-caused, fixed, and the telephoto proven to produce real frames. Committed as
`2e1b351` on branch `arcfox-vndfwk-camera-gate` in `hardware/qcom-caf/common`.

### The mechanism

`ExtensionModule::GetDevicesSettings()` in `com.qti.chi.override.so`:

```c
if (isRunningWithVendorEnhancedFramework()) goto keep;
m_logicalCamXmlName.assign("lanai_mot_cam_cts.xml");   // unconditional overwrite
```

and `isRunningWithVendorEnhancedFramework()` (`libqti_vndfwk_detect.so`) is exactly
`property_get_bool("ro.vendor.qti.va_aosp.support", false)`. Stock sets it in
`system/build.prop`; LineageOS ships it nowhere. The HAL prints the whole thing:

```
chxextensionmodule.cpp:11785 GetDevicesSettings() Pure AOSP Version build,
    switching current xml: _ to default lanai_mot_cam_cts.xml
```

⚠️ **No CamX setting can beat it.** `multiCameraLogicalXMLFile` (hash 0x79AFCDA5,
the only XML-valued setting in the whole vendor partition) IS honoured — the
override dump prints back the value written to
`/vendor/etc/camera/camxoverridesettings.txt` — and is then clobbered by the line
above. Tested with `lanai.xml` and `arcfox_supportLogicalCamFor3rd.xml`. Chasing
this cost hours; the answer was one line above the line being grepped.

### The result

With the guard cleared, auto-matching picks `arcfox_supportLogicalCamFor3rd.xml`
"based on xml matching" with **no override file needed**. 2 -> 8 logical cameras:
`Wide`, `Tele`, `Front`, `CLIWide`, `CLITele`, `MultiCamera`, `MultiCamera_CLI`,
`MultiCamera_3rdApps`. Camera 0 becomes `LOGICAL_MULTI_CAMERA` with physIds {2,3}.

| cam | facing | focal | what |
|---|---|---|---|
| 0 | Back | 4.68mm | logical, wide+tele behind it |
| 1 | Front | 3.28mm | inner selfie (ov32b40) |
| 3 | Back | **7.07mm** | **the telephoto (s5kjn5)** |
| 6 | Front | 7.07mm | cover-display tele |

**PROVEN, not inferred:** two captures seconds apart report EXIF focal 4.68mm then
**7.07mm**, ISO 897 -> 5772. Digital zoom cannot change focal length. The tele is
reached by ZOOM RATIO, not a separate lens button — that is the correct Android
model for a physical sub-camera, so a single "1x" control is not a bug.

### Why NOT to just set the property

Measured A/B/A across a reboot: with the property set globally, `xtra-daemon`
requires a QCC telemetry registration, gets `SPC registration failed`
(`vendor_qtrsdkservice` is never published — `qcc-vendor` runs but `qccsyshal`'s
init rc lives in system_ext and is not shipped), retries 12x, `exit(-1)`, and
`loc_launcher` grounds it after 5 restarts. GPS predicted ephemeris then never
refreshes again. Without the property it downloads directly from xtracloud.net.

So the fix **gates on the process**, not the property: only
`vendor.qti.camera.provider-service_64` sees enhanced. ⚠️ Both
`libqti_vndfwk_detect.so` and `libqti_vndfwk_detect_vendor.so` are built from that
one source file (byte-identical, 35328 B, neither is a prebuilt) — gating on the
library would NOT have worked.

⚠️ Only bit1 (`va_aosp`) is implied. **Do not also set `va_odm.support=1`** — it
lights up the FM HAL, ANT, the QTI BT audio provider, cnd's vendor-enhanced
services and IMS LTR. Much larger, genuinely riskier change.

### Corrections to earlier claims in this file and elsewhere

- ⚠️ **arcfox is XT2451-x, not XT2453.** `ro.boot.hardware.sku=XT2451-3`.
- ⚠️ **DT_NEEDED is not "uses".** 130 files link `libqti_vndfwk_detect.so`; only
  **23** import a symbol. IMS, `cnd` and the Bluetooth HAL are inert or read bit0.
  A DT_NEEDED census overstated the blast radius by ~4x.
- ⚠️ **`grep` here is a ugrep function with `-I`** that silently skips binaries and
  returns ZERO hits on `.so` files. Use `/usr/bin/grep`. This produced false
  negatives three times in one session, including a confident "not present".
- On stock, third-party apps see only camera IDs 0 and 1 —
  `CameraMotAccessUtil.isCameraHiddenFromApp()` hides id>=2 from any package not in
  Motorola's whitelist, and stock's camera 0 is the bare wide. **This port now
  exposes MORE than stock does.**

### Charter status after this

⚠️ **STATUS BLOCK RECONCILED 2026-09-01 — the text below replaces stale claims
that contradicted later sections. Two of them misled a reader in this very
session. When updating, fix THIS block, not just the section you worked in.**

Camera MUST (front+rear) PASS. Video Recording MUST is a **separate MUST** and also
PASS — 1080p24 H.264+AAC both cameras, zero dropped frames, verified by ffprobe and
frame-difference. All-rear-cameras SHOULD now met.

✅ **EIS/stabilisation WORKS** — see §0.22 (2026-08-27), which this line previously
contradicted. Fixed by shipping the three `com.vidhance.node.{gme,preview,video}.so`
CHI nodes plus four settings; verified with unmodified Aperture at
`stabilizationtype 10`, 61 Vidhance node instances (was `72` with an identity warp
and 6.5px mean inter-frame motion). The old claim that `libcamxevainterface.so` is
missing AND required was wrong on both counts — §0.22 line 630 states it is NOT an
EIS dependency and is shipped anyway.

⚠️ **Camera briefly REGRESSED and was re-fixed 2026-08-31.** `camera.ko` was built
without `TARGET_SYNX_ENABLE`, so `cam_sync_synx.o` never compiled and
`cam_generic_fence_parser()` returned -EINVAL for `CAM_GENERIC_FENCE_TYPE_SYNX_OBJ`,
aborting the provider on every launch. Fixed by `KBUILD_OPTIONS +=
TARGET_SYNX_ENABLE=y` in `camera-kernel/Makefile`. Verified: live preview, no crash.
Note this block still said "PASS" throughout the outage — a status line is not
evidence.

✅ **Emergency calling: TESTED AND RECORDED 2026-09-02 — see §0.34.** PASS on the
shipping build: the number was classified by EmergencyNumberTracker, Telecom bound
the EmergencyInCallService, the call SRVCC'd from IMS to circuit-switched, and it
connected with two-way audio. Method was AOSP's `cmd phone
emergency-number-test-mode`, so no real emergency service was contacted. Full
evidence in §0.34 and `logs/emergency-call-2026-09-02/`.
✅ API1 camera and video BOTH PASS -- preview delivers real frames and
MediaRecorder produces a valid h264+aac MP4. See §0.35b.

⚠️ **SELinux denial count: "699 -> 73/boot" is STALE and understates the
shipping config.** That 73 was measured with the three
`allow hal_sensors_default sysfs:{dir,file,lnk_file}` grants ENABLED. Those grants
are deliberately commented out -- they killed double-tap-to-wake by letting the
sensor stack claim the gesture evdev nodes, and the trade is documented in
`sepolicy/vendor/hal_sensors_default.te`. What we actually ship therefore carries
those denials.

Measured 2026-09-01 on the shipping build (device `<device-serial>`, 30 min uptime,
`logcat -b all -d | grep -E "avc: +denied"`):

| what | count | confidence |
|---|---|---|
| `hal_sensors_default` -> `sysfs` (the documented trade) | **140** | exact -- 140 distinct audit serials, 130 file + 10 dir, one 4 ms burst at HAL start |
| all domains, whole buffer | **>=203** | LOWER BOUND only -- `main` and `system` are 256 KiB and had wrapped past the first ~20 s of boot |
| implied real total | ~213 | 73 + 140 |

The 140 is solid; the total is not, and cannot be made solid from this device.
`persist.logd.size` is not settable by shell (sepolicy), `logcat -G` does not
survive a reboot, and `adb root` is unavailable on this build -- so a clean
whole-boot count needs a userdebug/root path we do not currently have. Quote the
140 and the bound, not a tidy single number.

By domain over that same buffer: `hal_sensors_default` 143 (140 sysfs + 3
`boot_status_prop`, the latter documented as not fixable), `system_suspend` 30,
`vendor_init` 13, `rild` 7, `vendor_ssr_setup` 3, `vendor_subsystem_ramdump` 2,
and one each from `mediacodec`, `init`, `hal_secure_element_default`,
`hal_nfc_default`, `hal_face_default`.

### Do NOT "fix" the camera desktop sepolicy denial

`hal_camera_default.te` already explains why the `ICameraDesktop` denial is left
alone (VINTF, not sepolicy). An independent reviewer flagged it as a defect this
session; the tree's existing reasoning is better. Leave it.

Related but real, and still open: we DO ship
`vendor/etc/vintf/manifest/motorola.hardware.camera.imgtuner.aidl.xml` declaring
`IImageTuning/default` as present, while the binary carries the generic
`vendor_file` label so init never starts it. Nothing on the device references
`IImageTuning` and the framework-matrix entry is `optional="true"`, so it is inert
— but it is a declared-but-absent HAL. Either label it properly or stop shipping
the fragment.

---

## 0.20 OFFICIAL-SUPPORT VIABILITY — the blocker I claimed does NOT exist (2026-08-18)

⚠️ An earlier assessment in this session concluded "this port can never be
officially supported, because ~21 Motorola-proprietary kernel modules have no
published source." **That was factually wrong on both halves.** Recorded here so
nobody repeats it.

**Nothing is proprietary.** All 287 vendor_dlkm modules are GPL-family — 171
`GPL v2`, 112 `GPL`, 3 `Dual BSD/GPL`, 1 `GPL and additional rights` (measured
with `strings <ko> | grep '^license='` over every file). All 60 system_dlkm too.
The binaries even embed their own source paths, e.g.
`../../motorola/kernel/modules/drivers/moto_swap/zram-6.1/zram_drv.c`.

**The source is published.** Motorola delivers releases by **TAG, not branch** —
this is what my search got wrong. Tag `MMI-W1UXS36H.72-45-4-1` (our build train)
exists across 16+ repos:

| slice | where | count |
|---|---|---|
| in-tree msm-kernel | `MotorolaMobilityLLC/kernel-msm` @ tag (has `moto-pineapple-arcfox.config`) | 173 |
| moto/mmi drivers | `MotorolaMobilityLLC/motorola-kernel-modules` @ tag | 31 |
| QTI techpacks | `LineageOS/android_kernel_xiaomi_sm8635-modules` @ `lineage-23.2` | 83 |

**285 of 287 have source today.** Verified HTTP 200:
`motorola-kernel-modules/MMI-W1UXS36H.72-45-4-1/drivers/moto_swap/Kconfig` and
`android_kernel_xiaomi_sm8635-modules/lineage-23.2/qcom/opensource/audio-kernel/Android.mk`.
The 2 misses are WLAN build-variant names (`qca_cld3_kiwi_v2`, `qca_cld3_qca6750`) —
a defconfig question, the `wlan` source is present.

⚠️ `motorola-kernel-modules` is the ONLY relevant repo not named `kernel-*`.
⚠️ Motorola's `kernel-*-devicetree` repos are dtsi-only, ZERO `.c` files — they
are not the module sources (the exception is `kernel-msm-techpack-dataipa`).

**Precedent is unambiguous:** across ~160 official devices, zero ship `.ko`
prebuilts, and all 46 non-`lamu` Motorola devices build kernel from source. A
charter exception would be asking three Project Directors to stretch "all
*feasible* modules" over code that is one `git clone` away. Don't bother.

**Effort:** 1–3 weeks for the full three-repo layout; 3–7 days for the 31 moto
drivers alone as a first slice. Known potholes: `moto_product.bzl` is `load()`-ed
by `pineapple.bzl:4` but never shipped (open Motorola issue), and
`moto_fragment.config` is missing — apply `moto-pineapple.config` +
`moto-pineapple-arcfox.config` directly.

⚠️ THREE kernel versions are in play. Pin deliberately before building:
shipped GKI binary **6.1.145** (authoritative — it is what runs), Motorola's
tagged msm-kernel **6.1.128**, local `kernel/motorola/sm8635` **6.1.174**.

---

## 0.19 THE KERNEL WAS NEVER THE ONE WE SHIP (2026-08-17) — READ BEFORE ANY DLKM WORK

> **⚠️ CORRECTED 2026-08-18 — this section overstated the constraint, and the
> correction is good news.**
>
> 1. The kernel is **Google's certified GKI**, not a Motorola build.
>    `ab14763719` = `android14-6.1-2025-09_r28`; `ab13748990` = `android14-6.1-2025-03_r12`.
> 2. Only the **60 system_dlkm** modules are welded to it. The **287 vendor_dlkm**
>    are UNSIGNED (AOSP: *"module signing is not supported for GKI vendor
>    modules"*) and export no protected symbols, so they load across GKI builds
>    within one KMI generation. Verified: cfg80211/qca_cld3_kiwi_v2/msm_kgsl/
>    btpower carry no signature trailer; tipc/rfkill/libarc4 do.
> 3. **A newer certified GKI can therefore be adopted for CVE fixes** — swap
>    `boot.img` AND its matching `system_dlkm` from the same `ab` build, leave
>    vendor_dlkm alone. Our branch is deprecated **2027-01-01**; android14-6.1
>    EOLs **2029-07-01**. Six newer respins of 6.1.145 already exist (r29…r34).
> 4. The charter permits *"a prebuilt GKI image from Google"*, which is exactly
>    what we ship — the kernel itself was never the compliance problem. See §0.20.


Commit `095834e`. **`TARGET_PREBUILT_KERNEL` was dead config for ten days.**

AOSP declares `INSTALLED_KERNEL_TARGET` as a bare *path* and never supplies a
rule to build it (`build/make/core/Makefile:1014`); that is the kernel build's
job. `TARGET_NO_KERNEL_OVERRIDE := true` disables all of
`vendor/lineage/build/tasks/kernel.mk` (gated at its line 106), including the
`NEEDS_KERNEL_COPY` path that would have copied the prebuilt. With no rule, make
treats an existing `out/target/product/arcfox/kernel` as up to date **forever**.
A hand-placed 6.1.128 GKI Image from 07 Aug — byte-identical to
`~/android/kernel-src/arcfox-kernel-prebuilt/kernel`, a path no makefile
references — shadowed `prebuilt/Image` (6.1.145, byte-identical to stock's own
boot kernel) and went into every boot.img ever flashed.

**It is a SIGNING constraint, not a version one.** `kernel/module/main.c:1283`:

```c
if (!mod->sig_ok && gki_is_module_protected_export(...)) {
        pr_err("%s: exports protected symbol %s\n", ...);
        return -EACCES;
}
```

`mod->sig_ok` = does the module's signature verify against the key built into the
running kernel. `CONFIG_MODULE_SIG_PROTECT=y`, no `sig_enforce`, no bypass.
Proven by A/B on the handset, same kernel, same second: 6.1.128 `tipc.ko` loads
`rc=0`; 6.1.145 `tipc.ko` gives Permission denied.

⚠️ **The failure has no AVC and an intact signature**, so it looks like neither
SELinux nor a stripped module. 12 of 60 refused (6lowpan, can, can_dev,
ieee802154, l2tp_core, libarc4, mii, rfkill, slhc, tipc, usbserial, wwan);
everything depending on them cascades. Cost: WiFi (`cfg80211`→`rfkill`, no
`/dev/wlan`), Bluetooth (`btpower`, `bt_fm_slim`), mobile data
(`tipc`→AF_TIPC→dsi_init → `OEM_DCFAILCAUSE_4`, a **local** qcrilNr rejection —
the 4ms request/reject turnaround is the tell, no QMI round-trip).

Measured over `fastboot boot` on the unchanged ROM, kernel the only variable:

|                  | 6.1.128       | 6.1.145              |
|------------------|---------------|----------------------|
| `lsmod`          | 384           | **443**              |
| `/dev/wlan`      | absent        | present              |
| WiFi             | no networks   | `wlan0` PRIMARY      |
| SETUP_DATA_CALL  | DCFAILCAUSE_4 | **cause=NONE**       |
| ping 8.8.8.8     | unreachable   | 3/3, 29ms            |

**Why it hid so long:** the stale `out/` system_dlkm image held the *matching*
6.1.128 modules, so the pair was consistent by accident. `996f2e4` changed the
system_dlkm output path, forcing that image to regenerate against the current
6.1.145 prebuilts — and the accident ended. `996f2e4`'s mechanism is right and
stays; three of its claims were wrong and are corrected in `095834e`'s message.

The build now **hard-fails** if the kernel and `kernel_version` disagree, and
restores the seven `modules.dep` edges (`cfg80211`→`rfkill` etc.) that `996f2e4`
dropped by renaming the unsuffixed `BOARD_SYSTEM_KERNEL_MODULES`, which
`Makefile` passes as the vendor depmod "extra modules" argument.

---

## 0.18 THE ImsService WAS NEVER BOUND — inbound SMS, VoLTE, ATEL (2026-08-17)

Commit `f8e1ae7`. `config_ims_mmtel_package` / `config_ims_rcs_package` are empty
in AOSP and this tree never overrode them, so `ImsResolver` discovered both QTI
services and bound **neither**:

```
Device:  EMERGENCY_MMTEL ->     MMTEL ->     RCS ->        (all blank)
Cached:  org.codeaurora.ims/.ImsService  features: []
Active controllers:   (empty)
W Telephony: registerMmTelCapabilityCallback: ... no ImsService available
```

⚠️ **They live in `packages/services/Telephony` (`com.android.phone`), NOT in
`frameworks/base`.** An earlier pass grepped stock's `framework-res.apk`, found
zero hits, and concluded the mechanism was something else. Wrong APK.
`PhoneGlobals.java:554` reads them into `ImsResolver.make()`.

The empty feature list is a *consequence*: these services declare no feature
metadata, so features come from a dynamic query, and `scheduleQueryForFeatures()`
skips any service that is neither device-default nor an active carrier service.

⚠️ `cmd phone ims set-ims-service` **silently no-ops without `-f`** and still
returns `true` (`TelephonyShellCommand.java:1466` starts with an empty list). Use
`-f 0,1` for MMTEL and `-f 2` for RCS.

Fixed by a `PRODUCT_PACKAGE_OVERLAYS` overlay in sm8635-common (both apks ship
from there; `com.android.phone` is built from source and is not a mainline
module, so an RRO is unnecessary — contrast `rro_overlays/WifiOverlay`).
**Inbound SMS now reaches the inbox on a clean boot.**

---

## 0.17 INBOUND SMS WORKS — but the fix is a workaround (2026-08-17)

> **RE-TESTED 2026-08-18 AFTER THE ImsService FIX (`f8e1ae7`) AND THE KERNEL FIX
> (`095834e`): THE WORKAROUND IS STILL REQUIRED. `4891f64` STAYS. Do not revert
> it, and do not re-open this without reading the trap below.**
>
> The hypothesis was that `4891f64` only existed because `mIsImsStackUpForSlot`
> never became true, and that binding the ImsService would fix it at the source.
> **Refuted.** With the ImsService bound and IMS fully up, a *fresh* start of
> `com.qti.phone` still reports:
>
> ```
> trySendPhoneReady for slot: 0
> Not sending ATEL ready: States: [0: {true, false, false, false}]
> ```
>
> `mIsRilConnectedForSlot` and `mIsImsStackUpForSlot` are still false, on both
> slots. `QtiRadioProxy` is demonstrably alive at the time (NR icon events
> flowing), so this is not a dead channel — the specific ExtPhone callbacks that
> write those two flags simply never fire. That remains unexplained and is the
> only thing that would make `4891f64` removable.
>
> ⚠️ **THE TRAP THAT NEARLY PRODUCED THE WRONG ANSWER.** Mid-test I ran
> `setprop ctl.restart vendor.qcrild` to pick up a logging change. With
> `poweron_opt=1` the next SMS then arrived normally and the RIL logged
> `known ATEL UI STATUS Valid 1, value 1` — which reads exactly like "the ready
> signal now works, the workaround is obsolete". It is an ARTEFACT: restarting
> the RIL under an already-running, already-registered `com.qti.phone` makes the
> ExtPhone callbacks fire, flipping the flags that never flip during boot.
> A COLD BOOT with `poweron_opt=1` gives the opposite and correct result:
> **96 occurrences of `value 0`, zero of `value 1`**, and the gate closes.
> Only a cold boot measures this. A RIL restart does not.
>
> ⚠️ Second confound in the same test: one SMS appeared to be swallowed, but the
> user confirmed it was delivered together with the next one — the SMSC had been
> backing off after the day's unacked deliveries. A single missing message here
> proves nothing. Send two, or corroborate with the RIL log.
>
> **ROOT CAUSE FOUND 2026-08-18 — `4891f64` IS NOT A WORKAROUND, IT IS THE
> CORRECT CONFIGURATION. THIS QUESTION IS CLOSED.**
>
> `PowerUpOptimization.registerForIntents` registers for exactly five actions
> (read out of QtiTelephony.apk's dex). Two are Qualcomm-proprietary, and they
> are exactly the two that feed the two flags that never become true:
>
> | intent | feeds |
> |---|---|
> | `org.codeaurora.intent.action.RADIO_POWER_STATE` | `handleRadioPowerStateChanged` -> `mIsRilConnectedForSlot` |
> | `org.codeaurora.intent.action.ESSENTIAL_RECORDS_LOADED` | `onSimLoadedOrLocked` -> `checkImsState` -> `mIsImsStackUpForSlot` |
>
> Verified four ways for each: ZERO occurrences in a cold-boot log, ZERO in an
> 8.4 MB all-buffer capture, ZERO files in the entire source tree, and PRESENT in
> stock's `framework.jar` / `telephony-common.jar` (+ extphonelib, ims-ext-common,
> qcom-moto-ims-ext). Motorola ships a QTI-PATCHED telephony framework that
> broadcasts them; LineageOS builds stock AOSP telephony, which has no such code.
>
> The chain, fully traced in the dex:
>   - the receiver gets `SIM_STATE_CHANGED: iccState=LOADED` and does NOTHING --
>     its only branch on that intent is the `NOT_READY` deactivation path;
>   - `onSimLoadedOrLocked` is reachable ONLY via `ESSENTIAL_RECORDS_LOADED`;
>   - therefore `checkImsState`/`getImsState` are NEVER CALLED. Confirmed by zero
>     occurrences of their own log strings, including `Reach the max retry time:`.
>     The IMS check is not failing -- it never runs.
>
> So the ATEL ready signal is STRUCTURALLY unreachable on an AOSP-telephony ROM,
> and disabling power-on optimisation is the right answer rather than a patch-up.
> It is coherent on both sides: the same `poweron_opt` disables the feature in the
> RIL and in the app (`ExtTelephonyServiceImpl.startPowerUpOptimizationIfRequired`
> reads it back through the RIL).
>
> Only reopen this if someone wants to PATCH `frameworks/opt/telephony` to emit
> the two intents at the points QTI does. That would buy back nothing but a
> boot-time modem optimisation we do not need, and it would put a vendor-specific
> broadcast into the framework. Not recommended.
>
> ⚠️ To see any of this you need `persist.vendor.radio.adb_log_on 1` and a RIL
> restart; without it there are no `QCRIL_*` lines at all and the radio buffer
> holds only framework-level `RILJ`/`DNC` output. Device left with
> `adb_log_on 0` and `poweron_opt 0`, i.e. the committed state.


Commit `4891f64` (sm8635-common). Inbound SMS had never worked on this port.

**The gate.** QCRIL's power-on optimisation holds every MT SMS until the
telephony UI declares itself ready, releasing it only when the feature is off or
the cached ATeL UI status is non-zero. Ours is zero, so each message was buffered
and dropped without the framework ever seeing it:

```
QCRIL_SMS qcril_qmi_sms_unsolicited_indication_cb_helper:
          msg_id (0x0001) QMI_WMS_EVENT_REPORT_IND
qcril_qmi_nas_get_atel_ui_status_from_cache:
          .. known ATEL UI STATUS Valid 1, value 0
QCRIL_SMS qcril_qmi_sms_update_mt_sms_with_ack_needed_power_opt_buffer:
          MT SMS ACK NEEDED Power Opt buffer length 1
```

**The lever is the RIL's config DB, NOT an Android property** — this is the part
worth remembering. `persist.vendor.radio.poweron_opt` is namespaced exactly like
a system property but lives in `qcril_properties_table` inside `qcrilNr.db`.
Stock's own `/vendor/bin/qtisetprop` writes that table and falls back to
`setprop` only when the property is *absent* from it. It is present
(`def_val=1`), so `setprop` is inert — `qcril_config_get` reads the DB and has no
property fallback at all. An earlier session tested this with `setprop`, saw no
effect, and recorded it as REFUTED. The conclusion was right; the lever was
wrong. **When a vendor ships its own get/set helper, read it before assuming the
standard mechanism.**

The fix patches the shipped prebuilt DB from `fix-vendor-blobs.sh` (fixup 4), so
it survives `fastboot -w`: `init.qcom.rc:394` copies the prebuilt every boot and
`qcril_db_copy_from_prebuilt` streams it into place by raw file copy when /data
has no version row, preserving the `value` column. `preflight.sh` now BLOCKS if
the fixup is missing.

⚠️ **THIS IS A WORKAROUND. The sender exists and we ship it.** The first analysis
claimed nothing sends `QCRIL_EVT_HOOK_SET_ATEL_UI_STATUS` (524314) — that was a
coverage failure in a dex scan and it is wrong.
`com.qti.phone.powerupoptimization.PowerUpOptimization.trySendPhoneReadyForSlot`
→ `QtiMsgTunnelClient.sendAtelReadyStatus` sends it, and it fires only when ALL
FOUR of `mIsOemHookConnected`, `mIsRilConnectedForSlot`, `mIsImsStackUpForSlot`,
`!mIsAtelReadySentForSlot` hold. One of them never becomes true here. The apk
only began installing at all with `e9af8e9`, which is how "nothing sends it"
looked true.

**THE DIAGNOSTIC HAS NOW BEEN RUN — here is the answer.** On a clean boot with
power-opt temporarily re-enabled (`qtisetprop persist.vendor.radio.poweron_opt 1`):

```
PowerUpOptimization: PowerUpOptimization started
PowerUpOptimization: QcRilHook Service ready
PowerUpOptimization: SIM_STATE_CHANGED: iccState= LOADED slotId= 0
PowerUpOptimization: trySendPhoneReady for slot: 0
PowerUpOptimization: Not sending ATEL ready: States: [0: {true, false, false, false}]
PowerUpOptimization: trySendPhoneReady for slot: 1
PowerUpOptimization: Not sending ATEL ready: States: [1: {true, false, false, false}]
```

The four booleans are {oemHookConnected, rilConnected, imsStackUp, atelReadySent}.
**The OEM hook is fine; `mIsRilConnectedForSlot` and `mIsImsStackUpForSlot` never
become true**, on BOTH slots, and they stay false indefinitely with voice
IN_SERVICE. Reproduced identically from a clean boot and from a mid-session
restart of `com.qti.phone`, so it is not a missed-event artifact.

Where those two flags are written (dex, QtiTelephony.apk):
  `mIsRilConnected` <- `PowerUpOptimization.handleRadioPowerStateChanged(II)V`
  `mIsImsStackUp`   <- `onImsStackReadyForSlot(I)V` / `checkImsState` / `getImsState`
Both are driven by ExtPhone callbacks. **That is where to look next**: find why
the radio-power-state and IMS-stack callbacks never reach this app. Fixing them
would let power-opt stay enabled and make commit `4891f64` unnecessary.

⚠️ **One switch drives BOTH sides, which is why the fix is coherent rather than a
hack.** `ExtTelephonyServiceImpl.startPowerUpOptimizationIfRequired()` reads the
SAME `persist.vendor.radio.poweron_opt` through
`QtiRadioProxy.getPropertyValueInt` -> `IQtiRadioConnectionInterface` -> the RIL
-> the qcril DB. So setting it to 0 disables the feature in the app AND in the
RIL: the RIL stops buffering, and the app stops trying to send a readiness signal
it cannot produce. Consistent on both sides.
⚠️ Corollary: with the fix applied the app logs `PowerUpOptimization is not
enabled.` — that is EXPECTED and is caused by our own change. Do not mistake it
for the root cause; re-enable the property first or the diagnostic is confounded.

⚠️ **Trap that cost a whole test cycle:** `logcat -G 32M` does NOT resize the
`radio` buffer. Without `-b`, `-G` applies only to main/system/crash/kernel;
`radio` is separate and was 256 KiB — about 50 seconds of verbose RIL logging.
`logcat -g` does not even list it. Use `logcat -b radio -G 32M` before any RIL
test, or the evidence is gone before you read it.

---

## 0.16 22 VENDOR SERVICES CANNOT START — unlabelled binaries (2026-08-12)

**Biggest remaining functional gap.** Full write-up and porting recipe in
`UNLABELLED-SERVICES.md`.

22 of the 128 services declared in `/vendor/etc/init` have binaries labelled
generic `u:object_r:vendor_file:s0`, so init refuses to exec them:

```
E init: Could not ctl.start for 'vendor.motosxf': File /vendor/bin/hw/motosxf
  (labeled "u:object_r:vendor_file:s0") has incorrect label or no domain
  transition from u:r:init:s0 to another SELinux domain defined.
```

Binaries, `.rc` files and configs **all ship**. Only the `file_contexts` lines
and the domains were never ported. Same class of bug as `init.oem.hw.sh` — which
turned out to be what unblocked UTAGs — and `init.mmi.usb.sh`, still deferred.

⚠️ **`init.svc.<name>` does not exist for a service that has never been
started**, so its absence is NOT evidence the rc failed to parse. Prove it with
`start <service>` and read init's error. (This cost me a wrong intermediate
conclusion.)

19 of 22 have a stock label; 18 have domains in stock's cil (12–43 rules each,
~330 total). Three — `vendor.diagcommd`, `vendor.face-default`,
`vendor.mot.camera.desktop-hal-2-0` — have **no stock `file_contexts` entry at
all**, so stock cannot start them either. Do not invent labels for those.

⚠️ **Impact is LOWER than it first looked — my initial ranking is retracted.**
I called wireless charging and powershare "plausibly dead features". They are
not: `/sys/class/power_supply/wireless` exists, reports `type=Wireless`, is
already correctly labelled, and AOSP's own health HAL reads it
(`dumpsys battery` → `Wireless powered: false` with nothing on the pad). Battery,
touch, display, sensors and input likewise all work through AOSP/QCOM paths. And
**nothing on the framework side ever asks for these interfaces** — a full-logcat
grep for `motorola.*` service lookups returns zero, because LineageOS does not
ship the Motorola framework components that would bind them.

**The real defect is an inconsistency, not a dead feature.** Our vendor manifest
*declares* 19 of these HALs and `device_framework_matrix.xml` lists 19 motorola
entries, while not one of the services can start. `checkvintf` never caught it
because it compares manifest against matrix — declarations against declarations
— and has no idea whether anything serves the interface. Same shape as the
codec2 lesson below: a manifest entry is a promise, not a service.

So there are **two** consistent end states, and (b) may well be the better one:
  a. port the domains so the declarations become true, or
  b. drop the declarations for HALs we do not intend to run.
(b) is cheaper and carries no boot risk.

Low value regardless: mot vibrator (haptics already work via the QTI service),
`ifaa`/`zui` (Chinese market), Dolby `dms-hal` (dolbycodec2 already dropped).

**Not implemented on purpose.** 18 new domains at once is real boot risk on a
device whose only channel is adb. Land them in small batches, keep
`m selinux_policy` green at each step, fastboot ready.

---

## 0.15 TELEPHONY IS SOLVED — it is the SIM, not the ROM (2026-08-12)

**Do not re-open telephony as a porting defect.** The stack works end to end.
Two commits landed this day (`450fd3e` sepolicy, `43ee7ef` dpmd), **not yet
built into a full image and not flashed**.

### The finding

`AT+COPS=?` issued straight to the modem over **`/dev/at_mdm0`** — bypassing
Android and qcril entirely — returns four operators on LTE *and* GSM:

```
(1,"O2 - SK","23106",7) (1,"O2 - SK","23106",0) (3,"Telekom SK","23102",7)
(1,"Orange SK","23101",7) (3,"SWAN SK","23103",0) ...
```

status 1 = available, 3 = **forbidden**. The RF receiver is fine.

The SIM's forbidden-PLMN list (`EF_FPLMN`, 6F7B) held `232-03` (Austria),
`208-20` (France), `231-02` and `231-03` — roaming rejections across three
countries. **With every reachable network blacklisted the modem had stopped
transmitting registration requests at all**, which produced empty cell lists,
INT_MAX signal and `rejectCause=0` — indistinguishable from dead RF.

Clearing the list restored the attempts immediately:

```
AT+CRSM=214,28539,0,0,12,"FFFFFFFFFFFFFFFFFFFFFFFF"
  -> registrationState=DENIED  rejectCause=8  rRplmn=23106 (O2-SK)
  -> then rRplmn=23102 (Telekom SK)
```

**3GPP cause #8** = "EPS/GPRS services and non-EPS/non-GPRS services not
allowed" — the network explicitly refusing this subscriber.

The SIM is **O2 Czech** (`gsm.sim.operator.numeric=23002`); the phone is in
**Slovakia** (`gsm.operator.iso-country=sk`, every visible PLMN is MCC 231), so
it must roam. O2 CZ and O2 SK are different operators.

Writing to `EF_FPLMN` proves TX, RX and SIM write all work.

**Owner action, not a ROM action:** check the subscription with O2 CZ — active?
roaming enabled? prepaid lapsed? An unused prepaid SIM deactivated for
inactivity fits every piece of evidence.

### Two dead ends, both closed — do not spend time on them

* **FSG / `mot_open_gzfsg`.** The modem never requests `/boot/modem_fsg` (proven
  twice with continuous `dmesg -w`: across a cold boot and a clean modem SSR,
  only `modem_fs1`/`modem_fs2` are ever served). Irrelevant — the RF works
  anyway. `ro.vendor.fsg-id` being empty is **stock parity**: this unit's
  bootloader supplies no `androidboot.fsg-id` at all.
* **diag / FTM / `diag_mdlog`.** Unavailable on this device **and on stock**: no
  `/dev/diag`, no `CONFIG_DIAG_CHAR` in the running kernel, no `diagchar` module
  anywhere in our tree or the stock dump. Shipping `vendor/etc/diag_mdlog/*`
  would achieve nothing.

### Structural facts worth keeping

* Our kernel is the **stock prebuilt, byte-identical** — md5
  `4209d7b42497e2a47020a4afbcdcffba` vs the stock boot image. Every modem, RF,
  remoteproc, IPC-router and `rmt_storage` driver is stock's.
* `qrtr-lookup` shows the modem advertising its full QMI service set: NAS, Voice,
  WDS, UIM, **SAR**, **Coexistence**, **RF radiated performance enhancement**,
  **ANT SWITCH**, **Smart Transmit**.
* `qcrilNrd`'s transitive DT_NEEDED closure: 112 libs, **zero** missing.
* `/vendor/rfs` symlinks: a superset of stock's 74.
* Correct carrier MBN selected: `persist.vendor.radio.mcfg_version=O2_CZE`.
* SELinux is not involved (`setenforce 0` changed nothing).

### ⚠️ A methodological warning worth more than the fix

The first pass concluded "the modem sees zero RF energy" from passive
indicators. That was **wrong**. A subsystem that has *given up* looks identical
to one that *cannot* — no measurements, no errors, no cause codes. Before
concluding "cannot", prove it recently *tried*: clear the blacklist / backoff /
cache and re-measure.

---

## 0.14 UTAGs WORK (2026-08-10 afternoon) — and two claims below are RETRACTED

Committed as `4856a0e` in sm8635-common, **BUILT AND FLASHED**, verified on a cold
boot with no overlay.

Motorola's UTAG factory-data store now loads at early-init. `/proc/hw` has 14
entries, `/proc/config` 31, `reload` status 0, and the whole family is derived
from the unit's own factory data: `ro.vendor.hw.{radio=ROW, ram=12GB,
storage=512GB, dualsim=true, esim=true, esimid, fps=true, uwb=false, wlc=true,
felica=false, frontcolor=navyblazer, barometer=false, ecompass=true, nfc=ese_st,
cli_video_panel=false}`, `ro.vendor.product.{device=arcfox, name=arcfox_g,
hardware.sku.variant=dne}`, `ro.vendor.mot.gki.path`, `vendor.hw.touch.status`.
The store also holds carrier=reteu, sku=XT2451-3, both IMEIs, and
version.baseband — readable under `/proc/config`.

### TWO independent defects, either one sufficient

1. **init could not exec the script.** `File /vendor/bin/init.oem.hw.sh (labeled
   "u:object_r:vendor_file:s0") has incorrect label or no domain transition from
   u:r:init:s0`. Note this is **init, not vendor_init** — 0.11 said vendor_init.
   `init.mmi.rc` is byte-identical to stock and its early-init block demonstrably
   runs (`ro.vendor.mot.factory=false` proves it), so only the label stopped it.
2. **The driver could not open its own partitions, even from root.** Writing 1 to
   `/proc/hw/reload` gave `failed get block device` with **nothing logged** —
   the denial is dontaudit'ed. `setenforce 0` made the identical write succeed. A
   kretprobe pinned it: `blkdev_get_by_path` returned `-EACCES` from
   `load_work_func`, and probes on `blkdev_get_by_dev`/`blkdev_put` never fired,
   so it failed inside `lookup_bdev`'s path walk. The open runs on a WORKQUEUE, so
   the subject is `u:r:kernel:s0`, not the writer.

### ⚠️ RETRACTION 1: "zero AVC denials device-wide" was NEVER TRUE

auditd writes `avc:` + **TWO** spaces + `denied`. Every check in this project
grepped `"avc: denied"` with one space and matched nothing. The real count on a
healthy boot is **~860–940**. Use `logcat -b all -d | grep -cE "avc: +denied"` —
and `logcat`, not `dmesg`, whose ring buffer wraps ~14 s into boot here.

This mattered: it was used as the acceptance criterion for the first version of
this very change, and it passed a version that had `rild` denied a property read
every five seconds. An independent reviewer caught it. Relabelling
`ro.vendor.hw.*` / `ro.vendor.product.*` to types of their own silently removes
the blanket read that `system/sepolicy/private/domain.te:509` hands out for
`vendor_default_prop` — `restricted`/`internal` only emit neverallows, they grant
nothing. The read grants are now explicit in `sepolicy/vendor/property.te`.

### ⚠️ RETRACTION 2: init.oem.hw.sh does NOT set ro.vendor.fsg-id

0.13 below reopened this as "UNPROVEN and overstated". It is now settled by
reading `vhw.xml` directly: its ONLY `export=` attributes are
`ro.vendor.hw.{cli_video_panel,felica,sku_variant,variant,wlc}` and
`ro.vendor.product.{display,hardware.sku.variant,profile}`, plus one
`append=` list and one `writeback=`. There is no `fsg` string in the file at all.
The original claim was right; the retraction of it was wrong.

### TELEPHONY IS UNCHANGED — but the lead is much sharper

`RADIO_POWER error 71 / NO_RF_CALIBRATION_INFO` on both slots, identical before
and after. **Do not spend more time on UTAGs for telephony.** What was learned:

- `/mnt/vendor/persist/rfs/msm/mpss/` holds `cal_rfs/rf00029618.bin` (154566 B,
  factory-dated 2024-06-06), `shob.bin`, `dhob.bin` — Motorola's HOB (hardware
  object block) NV store.
- **The RFS transport WORKS.** `tftp_server` runs as `vendor_rfs_access`,
  `server_check.txt` ("hello") and `ticf.bin` are rewritten every boot.
- `hob_report.txt` records `"HOB not yet created at the factory"`,
  `"Can't access HOB file, errno = 3"` and `ERR: HOB NV 4212/4953/4954/22982/
  29618/29620/29622/29650/29720/30006 inactive`. NV 29618 is exactly
  `rf00029618.bin`, so the NV ↔ cal_rfs mapping is confirmed. **CAVEAT: that
  report names modem ver ...60.23R while we run ...60.112R and its mtime is
  epoch, so it may predate this ROM entirely. Verify before building on it.**
- `modemst1`/`modemst2` carry valid `IMGEFS1`/`IMGEFS2` headers — **not erased**.
  Our scripts only ever `fastboot erase metadata userdata`, never modemst. So
  "the calibration data is absent from this unit" is looking LESS likely, not
  more.
- Stock service binaries we do not ship that could matter: `ssgqmigd`, `mmid`,
  `mmi_watchdogd`, `init.mmi.qrtr-lookup.sh`.

### Still open, cheap, and now unblocked

- **16 more Motorola services** fail with the same "no domain transition" error
  (batt_health, capsense_reset, diagcommd, init.mmi.boot.sh, init.mmi.wls.sh,
  mbm_spy, mot_flip_count, hardware_revisions.sh, …). `init.mmi.rc` defines 32
  services; how many you see depends on the boot. `mmi_boot` also reads
  `proc_hwconf`, so it shares the type added here — and it will hit the same
  property-read trap, so grant reads explicitly.
- **Face unlock looks feasible.** Both stock HAL binaries, stock's init rc and a
  VINTF fragment are already shipped, and every `DT_NEEDED` resolves. Blocked on:
  the binary being `vendor_file` (same fix as above), the dlopen'ed
  `libFace3D_hlos.so` / `libFace3DTA.so` / `libface3d_dev.so` not being extracted,
  no `android.hardware.biometrics.face` feature XML, and stock's `MotoFaceUnlock`
  priv-app. ⚠️ We currently declare `IFace/default` with nothing serving it — the
  declared-but-absent trap — and our fragment says **version 4** while stock's
  `face-default_3.xml` says **version 3**. Unexplained.

### Flashing note

`fastboot flash super` MUST be run backgrounded. The Bash tool's timeout is capped
at 600 s no matter what is passed; a foreground call was SIGTERM'd mid-write, the
bootloader wedged (enumerates but every `getvar` times out), and it took a
hardware power cycle (Power + Vol Down, 15–20 s) plus a re-flash. `/data` survived.

---

## 0.13 TELEPHONY: root cause NARROWED, not fixed (2026-08-10) — READ BEFORE RETRYING

**Do not re-derive any of this.** Committed as `a95a412` in sm8635-common,
**NOT built and NOT flashed** — the corrected labels still need one build.

The failure is precise and unchanging:

```
RILJ: RADIO_POWER error 71
CommandException: NO_RF_CALIBRATION_INFO
AnomalyReporter: "No RF calibration data"
```

### What was fixed (real, verified from a cold boot)

`rmt_storage` — the daemon that serves the modem's EFS over QMI — was **denied
its own storage** on `sdd18` (`fsg_a`). Labelled per stock; result: zero
`rmt_storage` denials, zero AVC denials device-wide, `rmt_storage` serving the
EFS from boot. Also fixes a silent `e2fsck` failure on `/vendor/fsg` every boot.

⚠️ **CORRECTION (fact-checked 2026-08-10).** An earlier draft of this section and
the `a95a412` commit body claim *"every partition fell through to the generic
block_device label"*. **That is false.** QCOM's `sepolicy_vndr` already ships ~78
`1d84000.ufshc/by-name/…` entries and ~72 of ~102 partitions were correctly
labelled all along. The **single genuinely missing entry was `fsg_[ab]`** —
QCOM lists the modem partitions under their *unsuffixed* names, but this is an
A/B device where only `fsg_a`/`fsg_b` exist. `modem_[ab]` and `bluetooth_[ab]`
in that commit are **no-op duplicates** of entries already present, and the
unsuffixed `fsg` line is **dead code** (no such partition). Do not go re-deriving
block-device contexts; that area is essentially done.

⚠️ **Slot-suffixed partitions take a DIFFERENT type.** Stock carries both
`fsg` → `vendor_modem_efs_partition_device` and `fsg_[ab]` →
`vendor_modem_block_device`. Extrapolating the suffix (done here first) denies
`e2fsck`. Take stock's list verbatim.

### ❌ The hypothesis was TESTED AND DISPROVED

The theory — EFS starvation causes the missing calibration, so a cold boot with
labels in place fixes it — was flashed and tested. Labels applied, denials zero,
EFS served from boot, **and `RADIO_POWER` fails identically**.

So the modem has working EFS access and still reports no calibration. That points
at the data being **absent from this unit's `modemst`/`fsg`**, which sepolicy
cannot reach. This ROM has never had working telephony, so any loss predates all
of this.

### 🔴 START HERE NEXT SESSION: UTAGs are dead, and that is the best open lead

**The plumbing is NOT done — this was missed on the first pass and is the single
largest untested hypothesis for `NO_RF_CALIBRATION_INFO`.**

Motorola's UTAG store is this device's factory-data mechanism, and on this ROM it
is completely unpopulated:

```
$ ls /proc/hw        $ ls /proc/config
all                  all
reload               reload
```

`utags.ko` **is** loaded, but no UTAG directories exist, because
`/vendor/bin/init.oem.hw.sh` is labelled `vendor_file` so `vendor_init` can never
exec it. Consequence: the whole `ro.vendor.hw.*` / `ro.boot.hw.*` family that
stock derives from UTAGs is missing (only 5 such props are set here, all from our
own `vendor.prop`). The `utags` / `utagsBackup` partitions are also still generic
`block_device`.

⚠️ **The earlier claim that `init.oem.hw.sh` "never touches fsg-id" is UNPROVEN
and was overstated.** It contains no *literal* `fsg-id`, but it has
`set_ro_hw_property()` and `process_mappings()` which `setprop` **arbitrary**
names driven by UTAG data and by the 40 `export=` attributes in
`/vendor/etc/vhw.xml`. A grep for a string is not a proof. What *is* proven is
only that the bootloader supplies no `androidboot.fsg-id` (`/proc/cmdline` has no
`androidboot.*` at all; all 35 bootconfig entries enumerated without it).

So the `init_hw` domain work (59 allow rules, six Motorola property types, a
`proc_hwconf` genfscon) is **no longer just hygiene** — it is the way to populate
UTAGs, and it may well be the telephony fix. Do this before concluding anything
about missing calibration data.

`ro.vendor.fsg-id=0` remains a deliberate override, not stock parity, and is
**unproven** — it registered the FSG once in a mid-session restart and did not
from the cold boot after.

### Where things genuinely stand

The modem side is healthy: `vendor.peripheral.modem.state=ONLINE`, both `qcrild`
running, all 15 radio HALs registered, `remoteproc1` (mss) restarts cleanly, and
`rmt_storage` holds `modemst1`/`modemst2`/`fsc`/`fsg_a` open with zero denials.

"The calibration data is absent from this unit" is a **hypothesis, not a
finding** — do not treat it as settled while UTAGs are unpopulated.

---

## 0.12 SOFTAP / Wi-Fi TETHERING WORKS ON ALL THREE BANDS (2026-08-10)

Supersedes §0.11's "next steps" 1 and 2. Both of §0.11's step-1 items turned out
to be **already settled by the owner using the phone** — no work was needed:

* **STA association is proven**, not just scanning: connected to a WPA2-PSK AP at
  5260 MHz, 11ax, DHCP `192.168.1.234`, `IS_VALIDATED`, DNS and traffic all fine.
* **Fingerprint enrolment works and persists.** `dumpsys fingerprint` shows
  `"count":1` with 2 successful authentications and `HAL deaths since last
  reboot: 0`. **The `/data/vendor/.fps` denial question is closed** — enrolment
  survived without it, and there were **zero** AVC denials in a 46,595-line
  logcat over 3h45m uptime. Do not spend more time on it.

### hostapd: the blob was dead on arrival, exactly like wpa_supplicant

`/vendor/bin/hw/hostapd` imports `sk_dup`. Of the eight bare BoringSSL stack
symbols it wants, ours exports seven — `sk_dup` is the only gap, and one is
enough. So `IHostapd/default` had never registered and every tethering attempt
died at `numSetupSoftApInterfaceFailureDueToHostapd`.

**There were TWO sufficient blockers, not one.** hostapd was also never
VINTF-declared at all — no fragment was ever extracted, and `HostapdHal` gates
the whole AIDL path on `ServiceManager.isDeclared()`. A perfectly linkable blob
would still have been unreachable. Source-building fixes both, because the
cc_binary brings its own `vintf_fragment_modules` and its own `init_rc`.

`BOARD_HOSTAPD_DRIVER := NL80211` is the **on switch**, not a driver selector:
it sets soong's `wpa_build_hostapd`, and every hostapd module is
`enabled: select(...)` defaulting to **false** without it.

### hostapd was only the first of three gates

The other two are framework-side and would have left tethering half-working:

| Gate | Symptom | Resolution |
|---|---|---|
| Blob cannot exec + not declared | no `IHostapd` at all | build from source |
| `config_wifi5ghzSupport` defaults **false** in AOSP | `Can not start softAp with band 5Ghz not supported` | new RRO |
| ACS offload rejected by driver on 6 GHz | `kernel reports: Unknown attribute type` | leave ACS **undeclared** |

New RRO at `sm8635-common/rro_overlays/WifiOverlay` (module `SM8635WifiOverlay`),
targeting `com.android.wifi.resources` / overlayable `WifiCustomization`. **This
tree shipped no Wi-Fi overlay at all**, so the framework believed a Wi-Fi 7
tri-band radio was 2.4 GHz-only. STA never noticed; SoftAP did.

**Measured, all three bands `Soft AP is started`:** 2.4 GHz 2427 MHz
`wifiStandard=6` (11ax) · 5 GHz 5805 MHz `wifiStandard=6` · 6 GHz 6055 MHz
`wifiStandard=8` (**802.11be**). STA+AP concurrency confirmed: hotspot on `wlan2`
while `wlan0` held its address throughout, and Wi-Fi still worked after stopping.

**The ACS trade-off is deliberate and measured both ways.** Declaring ACS gains a
driver-side channel survey on 2.4/5 GHz and loses the entire 6 GHz band; it also
forecloses bridged/dual-band SoftAP. Full reasoning is in the overlay's
`config.xml` — read it before flipping the value.

### ⚠️ KNOWN LIMITATION: hotspot is 2.4 GHz-only until telephony works

5 and 6 GHz SoftAP require a Wi-Fi country code. The modem does not come up, so
`WifiCountryCode` gets an empty string from telephony. **Both** bands are refused
explicitly by `SoftApManager.setCountryCode()` (`SoftApManager.java:869-877`),
which tests `TextUtils.isEmpty()` and runs *before* channel selection. (An
earlier draft blamed the `countryCode == null` check in
`ApConfigUtil.updateApChannelConfig` — that one is **null-only and does not fire
on an empty string**, so it is not the gate.) All three bands were proven by
forcing a code with `cmd wifi force-country-code enabled <CC>` — **an in-memory
override that does not survive a reboot**.

**A default country code was deliberately NOT hardcoded.** It is a regulatory
decision, one image spans regions, and 6 GHz is where regions diverge most. If
one is ever wanted, the clean opt-in is `androidboot.wificountrycode=XX` on
`BOARD_KERNEL_CMDLINE` (read as `ro.boot.wificountrycode`, still overridable by
telephony). **This makes telephony a higher-value target than it looked** — it
now blocks two features, not one.

### Display: three fixes, all verified on the flashed image (`68bddfd`)

The cover panel kept the **bootloader splash** until the first fold, and its
digitiser stayed live so cover touches landed in the inner UI. Every layer
believed the panel was already off while the bootloader had it lit, so the one
`STATE_OFF` the framework emits was swallowed by SurfaceFlinger's
`currentMode == mode` early return. **An OFF cannot blank a panel nothing ever
saw as ON.**

**Stock does not blank it — it draws on it**, via `bootanim-cli` (Motorola's
markers are still in `system/etc/init/bootanim.rc`) plus a patched
SurfaceFlinger. We needed no patches: AOSP grew the same foldable capability
behind an aconfig flag that LineageOS already ships a value set for. One line in
`BoardConfig.mk`. `Setting power mode 0 on ...764` now appears once per boot and
never did before; **splash confirmed gone without folding**.

⚠️ **A SurfaceFlinger patch for this was written, reviewed and REVERTED.** The
argument was that SDM's `DisplayBase::state_` is born `kStateOff` and
short-circuits `setPowerMode(OFF)`. That is confirmed **in the sm8650 SDM
source**, but this device runs Motorola's **composer blob** — there is no sm8635
SDM source in-tree — so read it as *plausible by lineage, unverified for the
shipped `libsdmcore.so`*, not "proven". The flag fix works regardless; don't
retry the patch without new evidence.

Note also a caveat the commit body understates: `initializeDisplays()`
(`SurfaceFlinger.cpp:6091-6104`) drives every display in `mPhysicalDisplays` OFF
then ON. The "no layer ever saw it ON" story therefore only holds **if the cover
display hotplugs after that runs**.

**Clock clipped by the rounded corner**: we shipped no corner or cutout config at
all, so both panels were treated as plain rectangles. Values taken with `aapt2`
from Motorola's own overlays. SystemUI keeps its **own** pair (103px/27px)
separate from the framework's 100px — both files must change together.
**Confirmed correct on screen.**

**Cover touches**: stock ships `/vendor/usr/idc/gdx_cli_0.idc` and we omitted it.
With it the digitiser binds to the cover viewport, which is `isActive=[0]` while
open, so TouchInputMapper disables it — inert open, live folded, no policy code.

### Process notes

* **No sepolicy work was needed.** AOSP core already labels
  `/vendor/bin/hw/hostapd` → `hal_wifi_hostapd_default_exec` and
  `/data/vendor/wifi/hostapd(/.*)?` → `hostapd_data_file`; all three data dirs
  were created correctly and there were zero denials across all SoftAP activity.
* ⚠️ **ALWAYS assemble super with `./build-super-mix.sh all`, never
  `./build-super.sh`.** The latter hardcodes STOCK `system_dlkm`/`vendor_dlkm`,
  whose modules are built for kernel **6.1.145** while ours runs **6.1.128**.
  `modprobe` resolves `/lib/modules/$(uname -r)/`, so `rfkill.ko` never loads →
  `cfg80211: Unknown symbol rfkill_alloc` → no `qca_cld3` → no `/dev/wlan` →
  **WiFi completely dead**, with nothing in the failure naming dlkm or the
  kernel. This cost a full flash cycle today. Note `build-super-mix.sh`'s own
  line 14 says dlkm "are ALWAYS stock" while line 57 says the opposite and the
  code follows line 57 — that stale comment is what made the wrong script look
  right. Check the `=== composition ===` output prints `OURS` six times.
* **check_vintf results cache for DAYS.** Ours had been stale since 2026-08-07;
  adding a VINTF fragment invalidated it and 82 accumulated vendor HALs surfaced
  at once, blaming the wrong change. When regenerating
  `device_framework_matrix.xml`, **merge** — checkvintf lists only what is not
  yet covered, so replacing drops the entries currently working.
* ✅ **OTA zip generation is FIXED** (2026-08-12, commit `743f146`). It had failed
  with `Cannot find partition vendor_dlkm`; the diagnosis recorded here was
  correct — both dlkm partitions were in
  `BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST` but omitted from
  `AB_OTA_PARTITIONS`, and `delta_generator` requires every dynamic partition to
  have a payload entry. Adding `vendor_dlkm` + `system_dlkm` fixed it:
  `mka otapackage` now exits 0 in ~5 min and produces `lineage_arcfox-ota.zip`
  (2.21 GB), with the payload manifest listing all nine partitions and still
  correctly excluding `dtbo`/`vendor_boot` (built but deliberately never flashed).
  ⚠️ The old comment in `common.mk` claiming this ROM "does not build"
  vendor_boot/vendor_dlkm/system_dlkm/dtbo was **false for all four** — the build
  produces every one. What is true: the 287 + 60 modules are stock (our
  `prebuilt/` copies are byte-identical to the dump, all 287 checked) but the
  build STRIPS them, so the images we pack into super are ours, not stock's.
* ⚠️ **Several dlkm comments in the tree are STALE and contradict the code**:
  `BoardConfigCommon.mk:251-257` says dlkm are "deliberately EXCLUDED… the stock
  ones are kept", and `common.mk:41-43` says "this ROM does not build them" —
  both false as of `:298`. Also `proprietary-files.txt:1270-1275` says the display
  HAL is built from source when the composer is a blob. Trust the code.
* **The independent reviewer again paid for itself**, and its single most useful
  find was a *comment* defect: my claim "it was not a missing declaration" was
  flatly false. It also corrected the RRO rationale (a static overlay *would*
  have worked; the real argument is that mainline updates discard it) and showed
  `hostapd_cli` is safe because of `prefer:true`, not because "nothing depends on
  it". **Re-verify comments, not just code** — third cycle running that this is
  the highest-yield review target.
* `setup-makefiles.py` is a shebang stub (`#!./extract-files.py
  --regenerate_makefiles`). Running it as `python3 ./setup-makefiles.py` executes
  a file containing one comment and **exits 0 having done nothing**. Use
  `PYTHONPATH=<tree>/tools/extract-utils ./extract-files.py
  --regenerate_makefiles`.
* The host's `/usr/bin/adb` is broken (`libprotobuf.so.35.1.0` missing; system
  has 34.1.0). Use `/opt/android-sdk/platform-tools/adb`. Check `fastboot` the
  same way before a flash.
* `cmd wifi start-softap` requires **root** adbd; as shell it throws
  `SecurityException: Uid 2000 does not have access`.
* An `adb remount` overlay reverts to **read-only on every reboot** — re-run
  `adb remount` after each one, and `adb root` too.

---

## 0.11 WIFI AND NFC WORK (2026-08-09 evening, cycles bc27/bc28)

Supersedes §0.10's "next steps" 1 and 3. Committed as `e907d87` in sm8635-common.
Everything below was verified LIVE on the device over an `adb remount` overlay
BEFORE it was written into the tree, then re-verified on the flashed image.

**Verified on the flashed bc28 image, clean flash, wiped /data:**
`sys.boot_completed=1`; `IWifi/default`, `ISupplicant/default` and `INfc/default`
all registered; `wlan0`/`p2p0`/`wifi-aware0` present; "Wifi is enabled"; scan
returns networks on 2.4 GHz and 5 GHz; zero `CANNOT LINK` failures;
`navigation_mode=2`. The `qccsyshal@1.2-service` and `vendor.qsap.location` crash
loops are gone.

### Two process traps this cycle, both worth more than the code

1. **`adb remount` overlays survive reboots AND survive flashing `super`.** They
   live on a scratch partition. Prove fixes over the overlay (it turns a 30-minute
   cycle into 30 seconds) but run `adb enable-verity`, reboot, and confirm a file
   you pushed is GONE before flashing, or the overlay silently shadows the new
   image and you get a false pass.
2. **A wedged bootloader mid-flash corrupts `super` while fastboot still prints
   "Finished".** bc28's flash printed `Finished. Total time: 102.842s` for
   `flash super` and then every later fastboot command timed out. The device never
   left the bootloader, and `boot-cycle.sh` scored it `dropped to bootloader --
   FAILED`, which reads like a boot regression and is not one. After a manual power
   cycle the vendor filesystem was demonstrably corrupt:
   `ls /vendor/lib64/...: Structure needs cleaning` (EUCLEAN) from TWRP. Re-flashing
   `super` fixed it and the same build booted.
   **Diagnostic that settled it:** the harvested ramdump snapshots still contained
   the PREVIOUS cycle's signature error, proving the logger never ran and the boot
   died in first-stage init, not in any HAL. Always fingerprint a harvested log
   against a known-unique string from the previous build before trusting it.

Also note `boot-cycle.sh` runs `fastboot erase userdata` every cycle, so every
flash returns to the setup wizard and loses the "Rooted debugging" toggle (which
is why `adb root` stops working after a cycle).

| | §0.10 | now |
|---|---|---|
| `wlan0` | absent | present, with a real Motorola MAC |
| `IWifi/default` | registered | registered |
| `ISupplicant/default` | absent | **registered**, `wpa_supplicant` running |
| WiFi scan | impossible | **networks on 2.4 GHz and 5 GHz**, WPA2/WPA3-SAE parsed |
| `INfc/default` | 1 Hz retry storm forever | **registered**, real NCI traffic with the chip |

### Three independent WiFi defects, in the order they had to be fixed

1. **`WCNSS_qcom_cfg.ini` was missing entirely**, so the qca_cld3 host driver never
   probed (`cnss: Failed to probe host driver, err = -1`). On stock the
   `vendor/firmware/wlan/qca_cld/kiwi_v2/` entries are symlinks into
   `vendor/etc/wifi/kiwi_v2/`, and extract_utils drops symlinks — so neither the
   links nor the target directory was ever extracted. Now shipped as four real
   files. **This alone produced `wlan0`.**
2. **The wpa_supplicant blob can never run on this build.** It needs `sk_dup` from
   Motorola's own older `/vendor/lib64/libcrypto.so`; ours exports `OPENSSL_sk_*`.
   Now built from source (`external/wpa_supplicant_8` + `lib_driver_cmd_qcwcn`).
3. **The wifi HAL blob was relinked across an AIDL version** (V1 to V4). It built
   and registered, then SIGABRTed on the first `IWifiStaIface` transaction. Now we
   ship `android.hardware.wifi-V1-ndk.vendor` and declare `IWifi/default` with no
   `<version>`, exactly as stock does.

Full detail, including the two hypotheses this replaces, is in `logs/wifi-next.md`.

**The old `logs/wifi-next.md` conclusion was wrong** and is worth knowing about:
it said the driver "rejects the value" written to `/dev/wlan`. Timing the write
showed `OFF` returns instantly and `ON` blocks for **21.6 seconds** before EINVAL —
a timeout bringing the module up, not a rejected value. The fix it proposed
(compiling the state write out) would have returned success over a dead driver.

### NFC

`ro.vendor.hw.nfc` was empty because `/vendor/bin/init.oem.hw.sh`, which derives
every `ro.vendor.hw.*` from `vhw.xml`, is unlabelled and init refuses to exec it.
`vhw.xml` maps arcfox to `ese_st` for every hwid and SKU, so it is now hardcoded in
`vendor.prop`, plus `init/init.arcfox-nfc.rc` to supply a start trigger the blob rc
cannot satisfy. No VINTF change — `INfc/default` was already declared.

### Also in this cycle

* sepolicy `rild -> vendor_thermal_socket` (a denial twice a second; stock has the
  identical rule).
* sepolicy for the FPC fingerprint HAL: it runs but is denied `/dev/smcinvoke`, so
  it never reaches its TA and never registers. Unverified — this is the one change
  in bc27 that was not proven live first.
* `sched_get_priority_min/max` + `sched_setscheduler` added to
  `gnss@2.0-qsap-location.policy` (SIGSYS crash loop).
* `qccsyshal@1.2-service`'s init rc dropped — nothing declares or waits on it and
  it was forking every 5 s.

### Structural fact worth knowing before touching any VINTF file

`ro.boot.product.vendor.sku` is **`cliffs`**, so libvintf reads
`/vendor/etc/vintf/manifest_cliffs.xml` and **`device/motorola/sm8635-common/manifest.xml`
is dead at runtime.** Only `manifest_cliffs.xml` and the merged
`/vendor/etc/vintf/manifest/*.xml` fragments count. Editing `manifest.xml` to add or
remove a declaration will appear to do nothing.

### Fingerprint also works now (`c14db95`)

`IFingerprint/default` registers, `dumpsys fingerprint` shows sensorId 1 with
"HAL deaths since last reboot: 0". The HAL was never crashing — it was denied
`/dev/smcinvoke`, so it could not reach its QTEE trusted app, then (once granted)
`uhid_device` for the virtual input device it creates. Note the method: a denied
process stops at its FIRST denial, so expect to need two or three rounds and
pre-grant stock's whole set rather than one rule per boot cycle.

Left alone deliberately: three `com.motorola.hardware.biometric.fingerprint.IMoto*`
services fail to register against `default_android_service` (Motorola extensions
this ROM has no use for), and a `/data/vendor/.fps` write denial that may matter
for enrolment persistence — it needs a properly labelled type, not a blanket
`vendor_data_file` grant, and an actual enrolment attempt to judge.

### Next, in priority order

1. **Associate to a real AP.** Only scanning has been proven; a PSK connection and
   DHCP have not. Also try enrolling a fingerprint — that is what settles the
   `/data/vendor/.fps` question.
2. **hostapd / SoftAP** is not built at all (`BOARD_HOSTAPD_*` unset), so WiFi
   tethering cannot work. Same source-build treatment as the supplicant.
3. USB gadget HAL, telephony modem, audio, thermal — unchanged from §0.10.
4. Remaining log storms that were analysed but deliberately deferred:
   `vendor.dpmd` (also the sole provider of `INwMgr`), `IQesdSys`, and the Dolby
   `IComponentStore/default3`/`default9` fqnames. Each has a written patch
   proposal; none is user-visible beyond log noise.

---

## 0.10 STATE AT END OF 2026-08-09 — read this first

Nine cycles today (bc20 → bc26). The port went from **never boots** to a device
that boots in ~19 s, is driven entirely over adb, and has sensors, GNSS, telephony
links, codecs, gesture navigation and a registered WiFi HAL.

| | start of day | now |
|---|---|---|
| Boot | never completes | ~19 s, stable, `sys.boot_completed=1` |
| Display | wizard on cover panel | inner display; outer OFF |
| Sensors | none | 68, incl. hinge posture |
| Fold | no posture | `OPENED` committed, lid tracked |
| GNSS | 254 crashes | working, doing QMI |
| Telephony | `qcrilNrd` dead, 104 link failures | links; `qcrild` stable; modem still powered off |
| Codecs | c2 HAL dead, `media.swcodec` wedged | `IComponentStore/default` registered |
| adb | never enumerated | authorised at t=32 s, no prompt, 480 Mbit/s |
| Navigation | no nav bar, back gesture dead | gestural, `mIsGestureHandlingEnabled=true` |
| WiFi | absent | `IWifi/default` **registered**; no `wlan0` yet |
| Crash loops | 8 services | 3 |

### Commits (7 repos-worth, all with evidence in the message)

```
sm8635-common  7d31221  ship the two vendor libs libsensorndkbridge needs  (THE boot fix)
sm8635-common  134ca03  sepolicy: binder_call sensors -> sensorext          (sensors + display)
sm8635-common  d2ea733  declare sensors in VINTF + init.arcfox-usb.rc       (68 sensors, adb)
sm8635-common  d575497  wifi: start the HAL (init rc)
sm8635-common  88d52db  wifi: declare in VINTF
arcfox         ef2e940  logger: record sys.boot_completed
arcfox         9a68137  enable the navigation bar
arcfox         3eb7845  default to gesture navigation
arcfox         e1f9229  BRING-UP ONLY: WITH_ADB_INSECURE
frameworks/native cfc2e9d728  export legacy binder::atrace_begin/end        (4 services)
frameworks/av     b75d71346c  codec2 CreateSyncFence(int) ABI shim          (codecs)
```

Two AOSP projects are patched (`frameworks/native`, `frameworks/av`). That is
rebase debt for LineageOS upgrades; both are commented in place with the exact
failing symbol so a future rebase can tell whether they are still needed.

### Remaining crash loops — only three

```
qccsyshal@1.2-service   protobuf CopyWithSourceCheck; a PARTITION problem, deferred
vendor.dpmd             hardware::Parcel::setData; API deleted upstream, deferred
vendor.qsap.location    SIGSYS, blocked syscall sched_get_priority_min
```
Reasoning for the two deferrals is in `logs/cannot-link-cluster.md` — neither is a
one-liner and both are low value. `qsap.location` genuinely is a one-liner
(add the syscall to its seccomp policy) but is near-zero impact.

### Next, in priority order

1. **WiFi last mile** — `logs/wifi-next.md`. HAL registers; `wifi_change_driver_state`
   gets EINVAL writing `/dev/wlan`. Leading hypothesis: `qca_cld3_kiwi_v2` is
   already loaded from `modules.load`, so the state write is redundant. Needs
   `adb root` to confirm.
2. **USB gadget HAL** — `setCurrentUsbFunctions` fails for EVERY function
   (`dumpsys usb` → `current_functions_applied=false`), which is why MTP and
   tethering are dead and why adb drops for ~3 min at a time. Note this refutes the
   "flaky cable" story; a bad cable existed too, but the HAL is genuinely broken.
3. **NFC** — `ro.vendor.hw.nfc` is empty so no start trigger fires, and the rc has
   no `interface aidl ... INfc/default` line. Two lines. Stops a 15 s ANR storm.
4. **Telephony modem** — all radio HALs registered but `mVoiceRegState=POWER_OFF`,
   `gsm.sim.state=NOT_READY`. The plumbing is alive; the modem is not powered on.
5. **Audio** — NOT "entirely dead" as an earlier note said. The HAL runs and
   `IDevicesFactory` @7.0/@7.1 are registered; the defect is that
   AudioPolicyManager enumerates **zero devices**.
6. **Thermal sanity** — CPU7 reads 93.5 °C at ~95 % idle with `Thermal Status: 0`.
   Either a wrong sensor map or a real problem. Check before anyone relies on this.
7. **Dolby c2** — `IComponentStore/default3` declared, service has an rc, never
   starts; `mediaserver` polls it on a worker thread.

### Process changes made today (keep them)

* `validate-xml.sh`, wired as **step 0** of `boot-cycle.sh`. A `--` inside an XML
  comment is a documented trap here and still broke the build three times; aapt2
  reports it with no line number.
* `boot-cycle.sh` captures A/B slot health while in fastboot each cycle. Current:
  `slot-successful:a: yes`, `retry-count 6`, `unbootable no` — nothing is burning
  retries, contrary to an earlier worry.
* The logger records `BOOTSTATE sys.boot_completed=...` in every snapshot header,
  which is what turned "it probably booted" into a measurement.
* Boot-test window 400 s → 600 s, verdict takes 3 probes, and says
  `PROVISIONAL PASS` rather than `BOOTED`.
* **Cap parallelism (`-j12`) for any change touching
  `overlay-lineage/frameworks/base/core/res`.** It invalidates framework-res and
  rebuilds SystemUI, Settings, every app and all API stubs; the default job count
  on this 32-core box exhausted 125 GB RAM + 7 GB swap and the OOM killer took out
  ninja (and the user's browser). Vendor-side changes build incrementally in ~2 min
  and are unaffected.

---

## 0.9 adb WORKS AND SENSORS WORK (2026-08-09 ~12:10)

Full writeup: **`logs/bc23/RESULT.md`**. Build: sm8635-common `d2ea733`.

**`<device-serial> device`.** adb is up, so state is now verified live instead of by
harvesting a ramdump, and **the manual power-cycle is gone from the iteration
loop** — the single biggest brake on this project.

The fix was one line, and it was pure timing. `init.mmi.usb.rc` blanks
`persist.sys.usb.config` at `load-bpf-programs` (init.rc:579); AOSP's
`init.usb.rc:109` copies that blank into `sys.usb.config` at `on boot`
(init.rc:589); the restorer `/vendor/bin/init.mmi.usb.sh` cannot run because it is
unlabelled. `init.arcfox-usb.rc` restores it at `early-boot` (588) — the only
window that works. This is why `27a4c6d`'s vendor.prop properties never could:
they are set *before* the blanking.

**68 sensors register**, including `Hinge Posture  Wakeup`, `Hinge Angle`,
`Flip Hall Effect` and the rest. `vendor.sensors-hal-multihal` is gone from the
crash-loop list. Fold works properly:

```
mCommittedState = DeviceState{identifier=5, name='OPENED'}   mIsLidOpen = true
"Inner Display" displayId 0 layerStack 0 state ON
"Outer Display" displayId 6 layerStack 6 state OFF  FLAG_OWN_CONTENT_ONLY
```

The two-step mattered: bc22's `binder_call` proved the multihal reaches
`addService`, and only then was declaring the HAL safe. Declaring it earlier is
exactly what cost bc18 its boot.

### Still broken — seven crash-loopers, down from eight

```
vendor-qti-media-c2-hal-1-0  exits 0 in ~60ms -> media.swcodec MAIN thread wedged, no codecs
vendor.dpmd / cnd / qms / qcc-vendor / qccsyshal@1.2-service   CANNOT LINK (symbol-level ABI)
vendor.qsap.location         SIGSYS (seccomp)
```
Audio entirely dead (`audioserver.rc` services `service not found`). NFC HAL never
starts, so `com.android.nfc` ANR-loops. User reports the back gesture (left-edge
swipe) does not work while recents does.

Next: media.c2 → the CANNOT-LINK five → audio → NFC. All now debuggable live.

---

## 0.8 IT BOOTS. PROVEN, NOT INFERRED (2026-08-09 ~11:11)

Full writeup: **`logs/bc21/RESULT.md`**.

bc21 (sm8635-common `7d31221`, arcfox `ef2e940`) **booted at ~47 s and stayed up
13½ minutes with no system_server restart.** From the new `BOOTSTATE` header:

```
iteration 1   uptime  16.09   sys.boot_completed=    zygote=running
iteration 2   uptime  47.16   sys.boot_completed=1   dev.bootcomplete=1   zygote=running
iteration 26  uptime 814.78   sys.boot_completed=1   dev.bootcomplete=1   zygote=running
```

Corroborated by the user: the screen dims on the inactivity timeout and wakes on
the power key — PowerManagerService inside a healthy system_server. Every earlier
"BOOTED" on this project was inferred from the *absence* of a fastboot device;
this one is recorded.

The one change did both jobs:

| | bc20 | bc21 |
|---|---|---|
| gnss tombstones | 127 | **0** |
| `Waited …IGnss/default` (dedup) | 244 | **0** |
| `CANNOT LINK …/qcrilNrd` | 104 | **0** |
| `Blocked in handler on main thread` | 3 generations | **0** |

### The device is still hard to USE, and that has one root cause

The wizard renders on the **cover panel** laid out for the inner display, so the
lower-right Next/Done button sits physically under the camera glass. That looks
like a freeze and is not one.

`hal_sensors_default` was never allowed to make a binder **call** into
`hal_graphics_composer_default` — sensorext's domain. `service_manager find` only
yields a handle; libbinder's next act is an `INTERFACE_TRANSACTION`, which was
denied 325×, so the descriptor came back `''`, `associateClass` failed, the
`ISensorExt` proxy was NULL and `sensors.qsh.so` SIGSEGV'd. No sensors ⇒ no
`com.motorola.sensor.hinge_posture` ⇒ `DeviceStateManagerService` never commits a
posture ⇒ never switches to the inner display. Not a mirroring problem, so
`bcfacb9` was never going to help.

Fixed in `134ca03` with `binder_call(hal_sensors_default,
hal_graphics_composer_default)`, verified present in the built policy.

~~**FALSIFIED:** the "sensorext SIGABRT in `SensorExt::initAlsComp`" theory carried
in this document. `vendor.moto_sensorext` starts once (pid 2338), never aborts,
never restarts.~~

⚠️ **THAT FALSIFICATION WAS ITSELF WRONG, and it is now FIXED (2026-09-01).**
The SIGABRT in `SensorExt::initAlsComp` is real and reproduced on every boot --
four tombstones per boot, ~5 s apart, all with the same backtrace:

```
abort <- libtinyxml2_1.so <- SensorExt::initAlsComp <- ISensorExt_onTransact
```

The reason the earlier note saw a healthy process is that the crash is in a
BINDER TRANSACTION handler, not at startup. init restarts the service, the
caller retries, and once the caller gives up the service stays alive -- so any
snapshot taken later shows one running pid and no restarts. `init.svc.*` and a
single `ps` cannot see this; only the tombstones can.

**Root cause: a blob fixup, not sepolicy.** `device/motorola/arcfox/extract-files.py`
carried `.replace_needed('libtinyxml2.so', 'libtinyxml2_1.so')` for this binary
on the stated grounds that it "was built against 10.x". It is built against
11.x. The discriminator is the offset of `tinyxml2::XMLElement::_rootAttribute`,
read out of `XMLElement::FindAttribute()` in each library --
`libtinyxml2_1.so` (10.x) uses `[x0, #0x68]`, `system/lib64/libtinyxml2.so`
(11.x) uses `[x0, #0x70]` -- and the faulting instruction is
`ldr x21, [x27, #0x70]`, immediately followed by the `__cfi_slowpath` that
aborts. Pointed at 10.x the blob reads a member that is something else in that
layout and hands the result to cross-DSO CFI.

⚠️ The fixup's other justification was also false: it claimed stock's
`vendor/lib64/libtinyxml2.so` is a symlink to `libtinyxml2_1.so` that
extract_utils drops. No such symlink exists in the W1UXS36H dump, and symlinks
ARE preserved there (`vendor/lib64` has three). The fixup is removed; the blob
now binds the 11.x `vendor/lib64/libtinyxml2.so` we already install.

The `sm8635-common` tinyxml2 fixup is a DIFFERENT case and stays -- those
display blobs really are 10.x. Run the 0x68-vs-0x70 test per blob before adding
to it, rather than assuming one vendor image was built alike.

**Still unverified:** that ALS compensation now initialises. The fix is proven
at the linkage level; it needs a flash plus a check that no sensorext tombstone
appears.

### Next

1. bc22 — the sensorext rule above (flashing now).
2. **USB gadget / adb.** Promoted: with the panel awkward to drive, adb buys
   `input tap`, live `dumpsys` and harvesting without a power-cycle per iteration.
3. The declared-but-unregistered HAL tier: IQHDC, IFingerprint, IQesdSys,
   IFactory, IDpmService, INfc — all spinning on worker threads today, none fatal
   yet, but that is not guaranteed to hold as more of the framework runs.

---

## 0.7 HOW THE BOOT WAS FIXED (2026-08-09 ~10:20) — history, superseded by §0.8

Full writeup: **`logs/bc20/ANALYSIS.md`**. Summary:

**`system_server`'s MAIN thread hangs in `OnBootPhase_600` waiting for
`android.hardware.gnss.IGnss/default`, and Watchdog kills it at 65 s. Three
instances in a row. `sys.boot_completed` is never set, so the on-device logger
reboots to the bootloader and `boot-cycle.sh` calls it FAILED.**

`android.hardware.gnss-aidl-service-qti` SIGSEGVs 127× in its *constructor*
(`Gnss::Gnss()+1068`), so it can never `addService`. Disassembled: it is
`ldr x19, [x0]` right after `LocationControlAPI::getInstance()` returned NULL.
That NULL is explained by a single missing library:

```
liblocation_api.so --dlopen--> libgnss.so --NEEDED--> libsensorndkbridge.so
    --NEEDED--> android.frameworks.sensorservice-V1-ndk.so   <-- built, but installed
                                                                 ONLY to /system/lib64
```

Same class as `71cd7f9` (33 vendor copies of interface libs); missed because
nothing needed it until `libsensorndkbridge.so` was shipped by `27a4c6d`
with `;DISABLE_DEPS`, which is exactly what suppressed that dependency.

### Two corrections to the previous handoff/checkpoint

1. **`/tmp/arcfox-boot-*.txt` were bc20's logs, not bc18's.** `boot-cycle.sh`
   step 6 `rm -f`s them before every harvest, so bc20 (09:57) overwrote bc18
   (06:23) in place. bc18's logs are gone for good. Logs are now archived per
   cycle under `logs/bcNN/` instead of left in `/tmp`.
2. **The "718× `Waited one second for ISensors`" reading was from replaced
   files.** The real bc20 capture has *zero* ISensors waits — the sensors VINTF
   revert (`7a9cb32`) worked. The batch's remaining suspects were being chased on
   bad evidence.

### RESOLVED: the regression is `27a4c6d`, and it is a source-module replacement

The apparent contradiction (bc16 booted with the same gnss artifacts installed)
had a wrong premise. **In bc16 `libsensorndkbridge.so` was present, built from
AOSP source.** `frameworks/hardware/interfaces/sensorservice/libsensorndkbridge`
is a `cc_library_shared` of that exact name with `proprietary: true`, and *its*
`shared_libs` are what installed `android.frameworks.sensorservice-V1-ndk.so`
into `/vendor/lib64`.

`27a4c6d` added the Motorola blob under the same module name. extract_utils
emits it with **`prefer: true`** (overrides the source module) and, thanks to
`;DISABLE_DEPS`, **no `shared_libs`** — so the dependency edges disappeared and
the NDK lib dropped out of `vendor.img`. Proof: the 2026-08-07 target-files
snapshot of the vendor image contains `VENDOR/lib64/android.frameworks.
sensorservice-V1-ndk.so` (101 968 B) and the *AOSP* `libsensorndkbridge.so`
(85 000 B); today the first is absent and the second is the 62 400 B blob.

The blob is still the right file — only it exports `ASensorManager_getCurInstance`
— so the fix ships the missing libs rather than reverting:

```make
PRODUCT_PACKAGES += \
    android.frameworks.sensorservice-V1-ndk.vendor \
    android.hardware.sensors-V2-ndk.vendor
```

(`sensors-V2` is the blob's other unmet `DT_NEEDED`; the AOSP module used V3.)

**This also fixes telephony.** `27a4c6d` never achieved its own goal: `qcrilNrd`
still fails 104× in bc20 with `library "android.frameworks.sensorservice-V1-ndk.so"
not found`, and `vendor.qcrild` restarts 52×.

### Do not trust a "BOOTED" verdict, and do not trust seeing the wizard

Two things learned here, both now fixed in the tooling:

* **SystemUI fully comes up in a FAILING boot.** In bc20, pid 4423 reaches
  `SystemUIBootTiming: StartServices` in the same second system_server enters the
  gnss wait, and is killed ~90 s later. So the wizard/home screen appearing on the
  panel is *not* evidence of boot, and neither is live-looking `dumpsys` output in
  logcat. Only `sys.boot_completed=1` is.
* **bc14 and bc16 were scored BOOTED from the absence of a signal** — one 8 s
  `getvar` probe, with a give-up that is iteration-based rather than time-based and
  a last-resort `sysrq` that resets into Android rather than the bootloader.

Fixed: the logger now writes `BOOTSTATE sys.boot_completed=… dev.bootcomplete=…
init.svc.zygote=…` into every snapshot header (it previously tested the property
and never recorded it); `boot-cycle.sh`'s window went 400 s → 600 s, its verdict
takes three probes instead of one, and it now says `PROVISIONAL PASS`.

### Second confirmed defect (costs sensors, not the boot)

`sensors-service.multihal` SIGSEGVs 23× in
`ambient_light_alt::ambient_light_alt()` because
`associateClass: Expecting binder to have class
'motorola.hardware.sensors.ISensorExt' but descriptor is actually ''` — the
sensorext service registers a binder with an **empty interface descriptor**, so
the proxy is NULL. This refines the older "SIGABRT in `SensorExt::initAlsComp`"
note: the multihal is not blocked, it is crashing on a bad binder.

---

## 0.0 THE BLOCKER IS FOUND AND FIXED (2026-08-08 ~21:20)

**`device/motorola/sm8635-common/vendor.prop` was 0 bytes. That was the boot
blocker.** (`system.prop` is empty too.) BoardConfigCommon.mk wires both via
`TARGET_VENDOR_PROP`/`TARGET_SYSTEM_PROP`, so the built
`vendor/build.prop` had **81 lines against stock's 487** — 393 device properties
that simply did not exist.

The one that stopped the boot:

```
vendor.gatekeeper.is_security_level_spu=0
```

`libqtikeymint.so` imports `android::base::WaitForPropertyCreation` and calls it
from `AndroidKeyMintDevice`'s constructor — **before** `addService` — with an
**infinite** timeout. With the property absent, `keymint-qti` started, waited
forever for it to be *created*, and never registered `IKeyMintDevice/default`.
keystore2 then failed its six retries and aborted; init never left `late-fs`.

The same missing property is why `android.hardware.gatekeeper-service-qti` never
started: its `.rc` is `disabled` and enabled only by
`on property:vendor.gatekeeper.is_security_level_spu=0`.

**The /proc forensics said this all along and I misread them.** `futex op 0x0`
is `FUTEX_WAIT` *without* the private flag — which no pthread mutex or condvar
uses — on uaddr `page_base+4`, and that address is `prop_area::serial_`, i.e.
`__system_property_wait` on a property that does not exist. The four threads
parked in `smcinvoke_ioctl` were **normal idle callback threads** (stock's own
keymint has the identical 1+4 thread shape). I read "blocked in the TEE" into a
process that was blocked on a missing string.

**Result:** the boot now clears `late-fs` and `post-fs-data` and reaches the
system_server era — keystore2 starts, `wificond` and `hwservicemanager` run. It
still does not complete (zygote appears to restart repeatedly), but that is a
new and much later failure.

### 0.0a WHAT CAME AFTER: the display stack

With keymint fixed the boot reached the **system_server era** and the blockers
became display ones. In order:

1. **No display HAL existed at all.** Nothing declared
   `android.hardware.graphics.composer3.IComposer/default` (nor the HIDL 2.1
   fallback), so SurfaceFlinger aborted in `HidlComposer`'s constructor
   (`failed to get hwcomposer service`) every 5 s. Cause: an earlier pass removed
   the composer/allocator blobs "because they are built from source" and added
   them to `add-missing-hals.sh`'s EXCLUDE list — **but never added the packages
   that build them**, so the exclusion held and nothing replaced them.

2. **Building them from source was the wrong fix.** Every SDM support library in
   the image is a **bit-identical stock blob** (`libsdmcore.so`,
   `libsdmutils.so`, `libgralloc.qti.so`, `libdisplayconfig.qti.so` …, verified
   by md5 against the dump), and `sdm::CoreInterface`/`DisplayInterface` are
   **private, unversioned C++ vtables**. The source-built composer SIGSEGV'd six
   frames inside the stock `libsdmcore.so`, on its first
   `core_intf_->CreateDisplay()`, with zero log output — 82 times in 402 s. Its
   `.rc` has `onrestart restart surfaceflinger`, and SF's has
   `onrestart restart zygote`, so it tore down SF → zygote → system_server every
   5 s. (system_server *did* start each time and reach `StartActivityManager`.)

   **Rule, same as the keymint V3/V4 break: never mix a source-built consumer
   with prebuilt providers of a private interface. Ship the whole subsystem from
   one tree.**

3. **Now: the whole display stack is stock blobs**, byte-identical and unpatched
   — composer/allocator/demura services, their `.rc` and vintf fragments, the QTI
   mapper impl, and `init.qti.display_boot.rc`/`.sh`, which set 14
   `vendor.display.*`/`vendor.gralloc.*` properties for soc_id 614 *before* the
   composer starts and were previously in **neither** image.

   Their AIDL interface libraries are the exception: those are generated by
   `aidl_interface` modules already in the tree, so a prebuilt of the same name
   fails with `partition is different: system(...) != vendor(prebuilt_...)`.
   They are built as `.vendor` variants (`composer3-V2`, qti `composer3-V1`,
   `display.config-V11`). AIDL generated code at a **fixed** version is
   ABI-stable, so unlike `libsdmcore` this is not a mixed-tree hazard. Shipping
   `composer3-V2` also let the `composer3 V2->V3` `.replace_needed` be deleted.
   The composer blob carries `;DISABLE_DEPS` (it links V2 while its closure
   pulls V4) — exactly how peridot ships the same binary.

**Traps hit while doing this, worth not repeating:**
- `add-missing-hals.sh`'s EXCLUDE list is dangerous when it excludes something
  nothing builds. Only exclude a blob if a package actually replaces it.
- `android.hardware.sensors-multihal.xml` **cannot** be shipped as a blob — AOSP's
  `hardware/interfaces/sensors/aidl/multihal` already defines it and kati fails
  with `already defined by`. But nothing installs it either, so no VINTF entry
  declares `android.hardware.sensors` and the multihal service aborts on
  `addService` ~184 times. Declare it in `sm8635-common/manifest.xml` instead.
- Source-module-vs-blob install collisions (`overriding commands for target …`)
  are mechanical: `/tmp/decollide.sh` loops build → drop the blob → regenerate
  until clean. It resolved four in one pass.
- **`pkill -f <script>` matches your own shell** if the command line contains the
  script name — the trap already documented in §7 — kill by PID from
  `ps -eo pid,cmd` instead.

### 0.0b CORRECTIONS TO THE SECTIONS BELOW

Sections 0.1b–0.5f were written before this was found. Several claims in them
are **wrong** and are corrected here; read them with this in mind:

- "vold blocks waiting for KeyMint" — **no**. vold waits on **keystore2**
  (`Since 'android.system.keystore2.IKeystoreService/default' could not be
  found…`). §0.1b had it right; §0.5c/0.5d-bis regressed it.
- "It is blocked, not looping; after 3.3 s nothing else happens" — **no**.
  keystore2 **SIGABRTs at ~63.7 s** and is never restarted, because init pid 1 is
  itself wedged inside `mount_all --late` (its last line is
  `Calling: /system/bin/vdc cryptfs encryptFstab …`), so it cannot reap children
  or drain its control queue.
- "the TA call never returns / QTEE does not answer keymint" — **no**. There was
  never a stuck TEE call.
- "Only six distinct AVC denials" and "122 vs 6" — the real counts are 68 raw
  (13 unique) enforcing vs 122 raw (20 unique) permissive. The permissive
  *conclusion* still stands; the contrast was overstated.
- "`IBootControl/default` registers, so the source-built boot HAL works" — the
  quoted line was **vold looking the service up**, not the HAL registering.
- The stock-vendor mix (§0.5d-ter) was invalid for the TEE question, but it did
  show init stopping at the byte-identical `encryptFstab` line with a completely
  different vendor — a useful control that the stall was not vendor-determined.

**Method lesson:** hours went into md5-diffing TEE binaries — a healthy
subsystem — while the fault sat in the build's property layer. An independent
reviewer found it in one pass. Run one over the logs after every failed boot.

---

## 0. UPDATE 2026-08-08 ~10:50 — read before anything below

### 0.1 The keymint diagnosis in §6.4 is WITHDRAWN

§6.4 concluded the keymint HAL "appears never to be started" because the log
contained no init lines for it. **That conclusion was an artifact of the logger,
not a finding.** Two defects in the old `arcfox-logger.sh`:

- **Truncation.** init logs to the *kernel* ring buffer, not to logd, so init's
  messages reached us only through `dmesg | tail -100`. At the sampled uptime
  that window covered ~176–186s of a 1 Hz repeating message. The entire
  early_hal era — the only window in which keymint would start, succeed or
  abort — was cut off. The logcat section contained **zero** `init:` lines at
  all, so the absence of keymint lines said nothing.
- **Stale tail.** `dd conv=notrunc` writes only as many bytes as the input has,
  so a shorter record left the previous, longer one's tail in place. The
  harvested file was a *splice of two different boots* — which is why a log
  headed "iteration 17, uptime 91.66" carried dmesg timestamps of 186s.

What was positively verified instead, statically against the built image:
keymint's `.rc`, binary, VINTF manifest (`<version>4</version>`, matching the
`keymint-V4-ndk` the ELF links) and its SELinux domain (`vendor_hal_keymint_qti`
in `vendor_sepolicy.cil`, exec label in `vendor_file_contexts`) are **all
present and consistent**, and its full transitive `DT_NEEDED` closure resolves
inside the image (only bionic is "missing", which lives in the Runtime APEX).
So keymint is not failing to exec, and the sepolicy port (§3 step 5) is *not*
the fix for it — QCOM's `sepolicy_vndr` already supplies its domain.

### 0.1b ROOT CAUSE, from the first EARLY log (harvested 10:55)

The EARLY snapshot was taken at **uptime 2.60 s** with the full kernel ring
buffer, and it settles the question. keymint is fine; **its TEE backend is
what dies.**

```
[2.295588] init: processing action (init) from (…keymint-service-qti.rc:5)
[2.295877] init: starting service 'vendor.keymint-qti'...
[2.298099] init: ... started service 'vendor.keymint-qti' has pid 995
[2.298449] init: starting service 'vendor.qseecomd'...        -> pid 996
[2.300876] init: starting service 'qseecom-service'...        -> pid 997
[2.307110] init: Service 'qseecom-service' (pid 997) exited with status 1
[2.318546] init: Service 'vendor.qseecomd'  (pid 996) exited with status 255
[2.498589] init: service 'vendor.keymint-qti' … already running (pid 995)
```

keymint-qti **starts and stays alive**. Both of its TEE providers die within
20 ms of each other, for two *different and independently fixable* reasons:

**(1) `qseecom-service` — a missing shared library.** From the crash buffer:
```
F linker: CANNOT LINK EXECUTABLE "/vendor/bin/hw/vendor.qti.hardware.qseecom@1.0-service":
    library "vendor.qti.hardware.qseecom-V1-ndk.so" not found: needed by main executable
```
That library is shipped, but to the wrong partition — `proprietary-files.txt`
installs it as `system_ext/lib64/vendor.qti.hardware.qseecom-V1-ndk.so`, and a
`/vendor` process cannot link against `/system_ext`. Confirmed in the built
image: it exists **only** under `system_ext/lib64`. Fix: also install it to
`vendor/lib64`.

**(2) `vendor.qseecomd` — SELinux, during its GPT scan.** It gets as far as
`/dev/smcinvoke` OK (`rpmb_init succeeded`, `ssd_init_service succeeded`), then
`gpt_init_service` enumerates the UFS LUNs and is blocked reading every one:
```
E gpt_ufs_bsg: failed to open dev /dev/0:0:0:0 (error no: 13)   # EACCES
E gpt: read_lba: ufs_bsg_read failed 13, fallback to try block device
E gpt: failed to open dev /dev/block/sda (error no: 13)
```
two distinct denials, both against domain `tee`:
```
avc: denied { read write } comm="qseecomd" name="0:0:0:0" tclass=chr_file
     scontext=u:r:tee:s0 tcontext=u:object_r:device:s0          (x15)
avc: denied { read } comm="qseecomd" name="sda" tclass=blk_file
     scontext=u:r:tee:s0 tcontext=u:object_r:vendor_gpt_block_device:s0  (x6)
     … also vendor_xbl_block_device (x6), boot_block_device (x3)
```
- The UFS BSG char nodes `/dev/0:0:0:N` are **unlabeled** — they fall back to
  generic `u:object_r:device:s0`. Our `vendor_file_contexts` labels only the
  `/sys/…/0:0:0:N/…` paths, never the `/dev` nodes. (peridot does not label
  them either, so this needs a Motorola-specific rule or a ueventd entry.)
- `tee` is not allowed to read the gpt/xbl/boot block devices.

Both are precisely what a device sepolicy directory supplies, and
`sm8635-common/sepolicy/vendor` is still **EMPTY** — so §3 step 5 IS on the
critical path after all, just for `tee`/qseecomd rather than for keymint.

**The full chain, end to end:** unlabeled UFS nodes + missing `tee` block-device
rules -> `qseecomd` dies (255); missing `-V1-ndk.so` in /vendor ->
`qseecom-service` dies (1) -> no TEE -> `keymint-qti` runs but never registers
`IKeyMintDevice/default` -> keystore2 fails 6 retries, "Failed to construct
mandatory security level TEE", exits -> `vold` waits on keystore2 forever ->
init's control queue overflows ("Too many pending control messages, dropped
'interface_start' for keystore2") -> boot never completes.

Other things the EARLY log shows, worth fixing but not blocking:
`e2fsck` denied on `vendor_modem_block_device` / `vendor_custom_ab_block_device`
/ `block_device`; `modprobe` denied `sys_nice`; `init.qti.ufs.debug.sh` exits
127 (script not shipped); `gki.modprobe` and the `msm_11ad_proxy` modprobe exit
1; `recovery-refresh` exits 254.

### 0.2 The logger has been rewritten; kpan is split in two

`kpan` is now zeroed at start and split: `[0,4MiB)` is an **EARLY** snapshot
taken at the first opportunity and never overwritten (full `dmesg`, untailed);
`[4MiB,8MiB)` is the rolling **LATE** snapshot. `boot-cycle.sh` reads all 8 MiB
and splits it into `/tmp/arcfox-boot-early.txt` and `/tmp/arcfox-boot-late.txt`.

`boot-cycle.sh` now also builds `systemimage`. It previously built only
`vendorimage`, and **the logger installs to `/system/bin`** — so every "improved
logging" change had been silently reflashing the previous logger.

### 0.3 A real defect found: ten HAL binaries shipped with NO init .rc

Measured on the built image: `android.hardware.health-service.qti`,
`android.hardware.usb-service.qti`, `android.hardware.wifi-service`,
`vendor.qti.hardware.memtrack-service`, `vendor.qti.hardware.vibrator.service`
and five more shipped as blobs with no `.rc` anywhere in the image, so **init
never started any of them**. This is the §7 trap ("extract_utils does not
auto-install a HAL's .rc") biting silently rather than loudly.

This is direct, measured evidence for the §1 headline, and it is what the
restructure fixes structurally: a Soong HAL module carries its own `init_rc` and
`vintf_fragments`, so binary, `.rc` and VINTF entry cannot drift apart.

### 0.4 Restructure increment 1 is DONE, built and committed

`device/motorola/{arcfox,sm8635-common}` are now **git repos** (they were not —
a multi-hour restructure had no way back). Baseline commit is
`snapshot before peridot-shape restructure`; increment 1 is the commit after it.

Now built from source (blobs removed from `proprietary-files.txt`, and added to
`add-missing-hals.sh`'s EXCLUDE so it cannot resurrect them):
`android.hardware.boot-service.qti` (+`.recovery`), `health-service.qti`
(+`_recovery`), `usb-service.qti`, `usb.gadget-service.qti`,
`vendor.qti.hardware.memtrack-service`, `vendor.qti.hardware.vibrator.service`,
`vendor.qti.qspa-service`, `vndservice`, `vndservicemanager`.
`hardware/qcom-caf/bootctrl` had to be added to `PRODUCT_SOONG_NAMESPACES` —
it declares its own namespace, which is why boot-service.qti looked unavailable.

**The `inject-vendor-mountpoints.sh` hack is obsolete.** Soong has a `mkdir`
module type; `hardware/qcom-caf/common` already declares bt_firmware, dsp and
firmware_mnt that way, and `sm8635-common/Android.bp` now declares the
Motorola-specific `fsg`. All four directories come from the build. (device.mk's
long comment claiming soong cannot do this is now wrong — `mkdir` is the answer
it was missing.)

Verified in the built vendor image: all four mount points present; rc + vintf +
binary present for all six HALs; the "no rc" list is down from 10 to 6
(remaining: `wifi-service`, `keymaster@4.0-service-qti`, `nqnfc-service.nxp`,
`capabilityconfigstoretest`, `fmradio`, `health.storage`).

### 0.5 Two traps that cost real time this session

- **`grep` is a ugrep-backed shell function.** It makes `breakfast`/`lunch` fail
  *silently* (exit 0, `TARGET_PRODUCT` empty), and the build then dies with
  "Cannot locate config makefile for product lineage_arcfox-bp4a-userdebug" and
  "release is one of: ." — which looks exactly like a broken device tree.
  Always `(unset -f grep; source build/envsetup.sh && breakfast arcfox && mka …)`.
  Setting `TARGET_PRODUCT`/`TARGET_RELEASE` by hand is *not* a substitute: it
  gets past product config, then fails in soong with
  `unknown variable '$(TARGET_KERNEL_PLATFORM_TARGET)'`.
- **Removing a line from `proprietary-files.txt` is not enough.** The generated
  `vendor/motorola/sm8635-common/Android.bp` still declares the blob module, and
  soong fails with `found in multiple namespaces`. Run
  `device/motorola/sm8635-common/extract-files.py --regenerate_makefiles`
  after every blob-list edit.

### 0.5b THE TWO ROOT-CAUSE FIXES ARE IN (commit `e87d80f`)

**Fix 1 — `vendor.qti.hardware.qseecom-V1-ndk.so` now installs to /vendor.**
Stock ships this library to **both** `system_ext/lib64` and `vendor/lib64`, and
the two copies are **different binaries** (119120 vs 93504 bytes, different
md5) — so do NOT "fix" this by copying the system_ext one across. The real
vendor copy was staged from the dump
(`$HOME/android/firmware/W1UXS36H/extracted/vendor/lib64/`).

The module-naming detail that matters: extract_utils names a prebuilt after its
basename, so both copies want the module name
`vendor.qti.hardware.qseecom-V1-ndk`. Both *consumers*
(`vendor.qti.hardware.qseecom@1.0-impl` and `…@1.0-service`) are **vendor**
modules and nothing on system_ext consumes it, so the plain name must be the
vendor copy. The system_ext entry therefore carries `;MODULE_SUFFIX=_system_ext`
(`MODULE_SUFFIX` changes only the module name — the installed filename is
unchanged).

**Fix 2 — `sm8635-common/sepolicy/vendor/` is no longer empty.**
`file_contexts` labels `/dev/0:0:0:[0-9]+` as `vendor_bsg_device`; `tee.te`
grants `tee` read-only access to `vendor_gpt_block_device`,
`vendor_xbl_block_device` and `boot_block_device`.

Two things worth knowing for future sepolicy work here:
- QCOM's `sm8650/generic/vendor/common/file_contexts` already labels
  `/dev/0:0:0:4` and `/dev/0:0:0:49476` **as literals**, and an exact path beats
  a regex in `file_contexts` regardless of order — so the LUN4-specific
  `vendor_ufs_lun4_bsg_device` label survives the new pattern.
- `tee` already had `allow tee vendor_bsg_device:chr_file rw_file_perms`, so the
  char-device half needed *labelling only*, no new allow rule.
- When checking the built policy, grep `vendor_sepolicy.cil` for the
  **versioned** type name (`tee_202504`, `boot_block_device_202504`), not the
  bare one — a grep for `allow tee …` finds nothing and looks like failure.

Verified before flashing: lib present in `vendor/lib64` with stock's md5; label
and all three allow rules present in the built policy; `sepolicy_neverallows`
passes; and the full transitive `DT_NEEDED` closure of `qseecom@1.0-service`,
`qseecomd` and `keymint-service-qti` resolves with **nothing** missing.

### 0.5c THE TEE CHAIN IS NOW HEALTHY; keymint ALONE IS THE BLOCKER

Later cycles (11:38–13:15) moved the failure forward three times. Current state,
from the timeline logs:

**Fixed and verified on-device:**
- `qseecomd` no longer exits. `QSEECOM DAEMON RUNNING`, `Total listener services
  to start = 10`, `rpmb_init`/`ssd_init_service`/`gpt_init` all succeed, and all
  six UFS LUNs read (`Successfully read 512 bytes from dev /dev/0:0:0:{0..5}`).
- `qseecom-service` links and registers: `Registered QSEECom HAL service
  successfully`, and servicemanager confirms
  `vendor.qti.hardware.qseecom.IQSEECom/default`.
- All four `/vendor` mounts succeed **including fsg** (the `fsg_file` fix).
- `android.hardware.boot.IBootControl/default` registers — the source-built boot
  HAL works.
- **No HAL crashes anywhere.** Remaining non-zero exits are all benign:
  `init.qti.ufs.debug.sh` 127 (script not shipped), `gki.modprobe` and
  `msm_11ad_proxy` 1, `recovery-refresh` 254.
- Only **six** distinct AVC denials in the whole boot, none on the boot path:
  `crash_dump→keystore ptrace` (AOSP b/376065666), `e2fsck` on
  `vendor_modem_block_device` (advisory — the mount succeeds anyway),
  `fsck.f2fs`/`make_f2fs` sysfs `getattr`, `modprobe sys_nice`.

**The one remaining blocker — exactly located:**

init reaches **`late-fs`** and never reaches `post-fs-data`. `late-fs` runs
`mount_all --late`, which triggers vold:
```
vold: fscrypt_mount_metadata_encrypted: /data encrypt: 1 format: 1 ...
vold: Creating new key in /metadata/vold/metadata_encryption/key
vold: Generating wrapped storage key      <-- blocks here forever
```
A wrapped storage key needs KeyMint. `vendor.keymint-qti` **starts on time, stays
alive, emits exactly three `TimedRetryForwarder_release` lines at ~2.6 s and then
says nothing for the remaining 93 s** — identical in all 18 timeline snapshots.
It never reaches `AServiceManager_addService`: servicemanager logs registrations
for qseecom and boot-control but never for keymint. No crash, no restart, no
denial. It is *blocked*, not looping.

After 3.3 s the machine does nothing else at all — diffing iteration 00 against
iteration 17, the only new activity in 93 s is the charger polling once a second,
keystore2's retry loop and servicemanager's lazy-start attempts. One blocking
dependency, not a cascade.

**What was tried and did NOT change it:** reverting the keymint V3→V4 ELF rewrite
and shipping keymint-V2/V3-ndk (commit `69c1163`). That change is still correct on
its own merits — the blobs are compiled against V3, stock ships V2 and V3 in
/vendor/lib64, and the blanket manifest rewrite had pushed
`IRemotelyProvisionedComponent` to 4 which the 202504 matrix does not allow
(rkp 1-3) — but keymint's behaviour is byte-identical before and after. So the
ABI mismatch was *not* what wedges it.

**Ruled out:** no keymaster TA missing (there is none on the modem partition on
this SoC — QTEE-resident; the modem `image/` dir does hold ops/widevine/fingerpr/
faceauth etc.); `hal_uuid_map_*.xml` all six shipped; `ssgtzd` never starts but
it is `class late_start` on `early-boot`, so it would not have started on stock
at this point either; keymint's full transitive `DT_NEEDED` closure resolves.

**Next instrument (built, flashed, not yet read):** the logger now dumps `/proc`
forensics for keymint/qseecomd/vold/keystore2 every iteration — per-thread
`wchan`/`syscall`/`state`, the kernel stack, and which `keymint-V*-ndk.so` is
actually mapped. A process that is not logging cannot be diagnosed from logs;
this asks the kernel where it is parked. **That log is sitting unread on
`ramdump` and needs one manual power-cycle to collect.**

### 0.5d A GENERAL TOOL THAT KEEPS PAYING OFF

Sweeping **every** ELF in the vendor image for unresolved `DT_NEEDED` — not just
walking down from a service binary — found the `libops.so` →
`display.config-V7-ndk` break that a link-time walk structurally cannot see
(`libops.so` is reached by `dlopen`). It listed 27 broken ELFs at once instead of
one per boot cycle; the display AIDL commit cleared 18 of them. Nine remain, none
on the boot path: audio (`pal@1.0`, `AGMIPC@1.0`), `libwifi-hal-qcom`, and
`libcom.android.tethering.connectivity_native`. Re-run it after any blob change:

```sh
cd out/target/product/arcfox
SEARCH="vendor/lib64 vendor/lib64/hw vendor/lib64/vndk vendor/lib64/vndk-sp \
        vendor/lib64/egl vendor/lib64/soundfx system/lib64 system/lib64/vndk-sp system_ext/lib64"
declare -A HAVE
for d in $SEARCH; do for f in $d/*.so; do [ -f "$f" ] && HAVE["$(basename $f)"]=1; done; done
for b in libc.so libm.so libdl.so libdl_android.so ld-android.so; do HAVE[$b]=1; done
for f in vendor/bin/* vendor/bin/hw/* vendor/lib64/*.so vendor/lib64/hw/*.so; do
  [ -f "$f" ] || continue; miss=""
  for n in $(readelf -d "$f" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/'); do
    [ -z "${HAVE[$n]}" ] && miss="$miss $n"; done
  [ -n "$miss" ] && echo "$f ->$miss"
done
```

Diffing our vendor filesystem against stock's is the other one: 2733 files vs
3021, **440 missing**, and that is how the keymint-V2/V3 libs were found.

### 0.5d-bis WHERE keymint IS BLOCKED — the /proc forensics answer

Harvested 19:4x. The logger's `/proc` dump settles it. `keymint-service-qti`:

```
state:   S (sleeping)     wchan: futex_wait_queue        (main thread)
threads: tid 1045..1048   wchan: smcinvoke_ioctl  syscall=29   (all four)
libs:    /vendor/lib64/android.hardware.security.keymint-V3-ndk.so
         /vendor/lib64/android.hardware.security.rkp-V3-ndk.so
         /vendor/lib64/libQSEEComAPI.so  /vendor/lib64/libqtikeymint.so
fds:     /dev/binderfs/binder, /dev/null x3, anon_inode:smcinvoke x2
```

**It is not failing to reach the TEE — it reached it and the call never
returns.** Four worker threads are parked in `smcinvoke_ioctl` (the QTEE
invoke path) and the main thread waits on a futex for a result that never
arrives. It holds two open `smcinvoke` handles. The mapped libraries also
confirm the V3 revert took effect at runtime.

For contrast, `qseecomd` in the same dump is healthy: main thread in
`sigsuspend`, ~28 listener threads parked in `smcinvoke_ioctl` (that is the
normal idle state for a listener), no errors. `vold` is in `futex_wait_queue`
with three binder threads — waiting on keymint, as expected.

So the remaining question is narrow and specific: **why does QTEE not answer
keymint's invoke?** Everything on the userspace side is now verified good —
the TEE daemons run, all 10 listeners started, no dlopen failures, no denials,
and every blob on the keymint path is byte-identical to stock (verified by
md5-diffing our vendor against the dump: 64 blobs differ from stock and none
of them is on the TEE path; the differing ones are camera libs plus the
fingerprint/sensors/wifi/face blobs that still carry version fixups).

Ruled out along the way: `com.qti.qseeutils.so` differs from stock (its
`graphics.allocator-V1 -> V2` rewrite) and the name makes it look like a TEE
library, but it is only linked by `com.qti.qseeaon.so` (camera always-on), sits
in a camera fixup block, and was **not mapped into keymint or qseecomd** at the
hang. Not the cause.

### 0.5d-ter AN INVALID EXPERIMENT — do not repeat it as-is

Tried: `./build-super-mix.sh system system_ext product` (STOCK vendor + our
system), to test whether the fault is inside our vendor. **The result is
meaningless** and must not be read as evidence:

```
F linker: CANNOT LINK EXECUTABLE "/vendor/bin/qseecomd":
    library "libandroidicu.so" not found: needed by /system/lib64/libxml2.so
```

Stock's Android-14-era `qseecomd` cannot link against our Android-16 system's
`libxml2`. It died with status 1, and so did `qseecom-service` and
`vendor.ipacm`. With no TEE daemon at all, keymint sat in `nanosleep` retrying
and never opened smcinvoke — a *different* failure from the one under
investigation. Stock vendor and our system are simply not a compatible pairing.

The one useful contrast: under this mix keymint never reaches the TEE, whereas
under **our** vendor it does (opens smcinvoke, four threads in the invoke path).
Our vendor's TEE stack is the more functional of the two.

If a control is wanted, the valid one is `./build-super-mix.sh none` (all
stock) — the configuration the handoff records as known-good — but note it
carries no logger, since the logger lives in our system.

### 0.5f TWO THINGS DEFINITIVELY RULED OUT

**1. The device, QTEE and our boot chain are all fine.** The all-stock control
(`./build-super-mix.sh none`, flashed over **our** boot/init_boot/vbmeta) boots
to Android in ~112 s. So the dtb/vendor_boot/vbmeta work is not the problem and
QTEE answers keymint perfectly well on this handset — on stock,
`service list` shows `IKeyMintDevice/default` registered. The fault is inside
our super. Firmware also matches: the bootloader reports fingerprint
`W1UXS36H.72-45-10-7/33779`, exactly the dump our blobs come from, so a
TZ-vs-blob version mismatch is out.

**2. SELinux is not the cause.** The permissive test was re-run properly (the
earlier one, noted in BoardConfigCommon.mk, ran with 15 HALs and proved
nothing). The flag was verifiably active: **122 AVC denials logged vs 6 under
enforcing**. The boot hangs **identically**, and keymint's `/proc` state is
unchanged — main thread in `futex_wait_queue`, four threads in
`smcinvoke_ioctl`. Not one of the 122 denials involves keymint, tee, qseecom or
smcinvoke.

This is stronger than it sounds: permissive also neutralises `dontaudit`, which
*enforces* a denial while suppressing its log line — the only mechanism by which
a policy gap could have produced a silent hang. It did not. The denial list is
saved as `workspace/permissive-denials.txt`; it is the sepolicy work-list for
after the ROM boots, not a set of blockers.

A supporting datum from a live stock boot (USB debugging was enabled on it):
stock's keymint has **exactly the same thread shape as ours** — one main thread
plus four workers. So four threads parked in `smcinvoke_ioctl` is the NORMAL
idle state for this HAL, not evidence of a stuck TEE call. That re-reads the
forensics: the thing that is actually stuck is the **main thread on its futex**,
waiting for a result its workers never deliver. (`wchan` cannot be read on a
stock user build without root, so the two cannot be compared directly.)

Also checked and dismissed: `/dev/qseecom` does not exist on stock at all —
only `/dev/smcinvoke` (`crw-rw---- system drmrpc`) — so any theory involving
qseecom device-node access is void. And stock's `qseecomd.rc` is byte-identical
to the one we ship.

### 0.5e THE WORK-LIST FOR §3 STEP 3, WITH EVIDENCE

§3 step 3 says to delete the `.replace_needed` version bumps. Here is *why* they
exist and which ones are provably wrong, from diffing our vendor filesystem
against stock's (2733 files vs 3021, **440 missing**).

Stock ships a whole set of **older** AIDL/HIDL interface libraries in
`/vendor/lib64` that we do not. Motorola's blobs are compiled against those older
versions; because we did not ship them, a previous session rewrote each blob's
`DT_NEEDED` to a version we *did* ship. **8 of the 13 remaining rewrites point
away from a library stock actually ships**, i.e. they are all the same defect the
keymint one turned out to be:

| rewrite | stock ships the original in /vendor/lib64? |
|---|---|
| `biometrics.fingerprint-V3` → V4 | **yes** |
| `graphics.allocator-V1` → V2 | **yes** |
| `graphics.composer3-V2` → V3 | **yes** |
| `health-V2` → V4 | **yes** |
| `security.keymint-V2` → V4 | **yes** (now removed, see below) |
| `sensors-V2` → V3 | **yes** |
| `wifi-V1` → V4 | **yes** |
| `wifi.supplicant-V2` → V5 | **yes** |
| `biometrics.common-V3` → V4 | no |
| `biometrics.face-V3` → V4 | no |
| `bluetooth.audio-V3` → V5 | no |
| `keystore2-V1` → V5 | no |

The correct fix for each "yes" row is the one applied to keymint: add
`<interface>-V<original>-ndk.vendor` to `PRODUCT_PACKAGES`, delete the rewrite,
restore the affected blobs unpatched from the dump, and drop the matching vintf
manifest `regex_replace`. Also missing and in the same family:
`authsecret@1.0`, `gatekeeper@1.0`, `graphics.composer@2.1/2.2/2.3`,
`audio.common-V1-ndk`, `cas-V1-ndk`, `media.bufferpool2-V1-ndk`,
`libwifi-hal-qcom.so`, the ANGLE EGL libs, and `lib64/rfs/dsp/*`.

**Done so far:** keymint (commit `69c1163`) and the identity-credential pair
`libqtiidentitycredential.so` + `android.hardware.identity-service-qti`, whose
`keymint-V2 → V4` rewrite became free to remove once `keymint-V2-ndk.vendor` was
shipped. Both build clean.

**Deliberately NOT done yet:** the other six. Each needs its own package, blob
restore and manifest revert, and two of them (`libjc_keymint-thales`, `libtpa`)
showed that reverting can surface soong's fatal "depends on multiple versions of
the same aidl_interface" — which needs either dropping the blob or tagging it
`;DISABLE_DEPS`. Doing all six blind, with no way to boot-test, would stack six
unverified changes and destroy attribution if the boot then broke differently.
Do them one at a time once the phone can be cycled again.

### 0.6 WHERE IT STANDS RIGHT NOW

A cycle ran at 10:28–10:44 and flashed **the rewritten logger** (old vendor
image). The boot failed — no adb and no USB enumeration at all for the whole
400 s window — and the phone did not come back to the bootloader, so
`boot-cycle.sh` exited 2 (`NEEDS PHYSICAL`) and harvested nothing at the time.

The device was then power-cycled **by hand** and the EARLY snapshot harvested
via TWRP; that log is what §0.1b is built on. Note for anyone reading the
timings later: the phone does **not** recover by itself. Every time it came
back to fastboot in this session it was because a human held Power ~20 s and
then Volume Down + Power. Budget one manual power-cycle per failed cycle.

Five more cycles followed (11:02, 11:38, 12:05, 12:38, 12:58). **Every one
flashed cleanly and every one failed identically** — no adb and no USB for the
full 400 s, then `NEEDS PHYSICAL`, one manual power-cycle, harvest via TWRP.
The phone sits at the Motorola logo the whole time (confirmed visually), i.e.
alive with init running, which is consistent with the `late-fs` stall in §0.5c.

What each cycle bought is in §0.5b–0.5c: the TEE chain went from "both providers
dead" to fully healthy, and the blocker narrowed to keymint alone.

**The last cycle's log (13:15, carrying the `/proc` forensics) has NOT been
harvested — the phone never came back and needs a manual power-cycle.** That log
is the next thing to read; see §0.5c for what it should answer.

Worth noting about that failure mode: the logger's own self-reboot
(`GIVE_UP_AFTER=18`, ~90 s) does not fire either. Its first route is
`setprop sys.powerctl reboot,bootloader`, which goes *through init* — and init
is exactly what is wedged, drowning in "Too many pending control messages". The
`/system/bin/reboot` fallback needs `misc`, and only the final
`echo b > /proc/sysrq-trigger` needs nothing from userspace. If unattended
cycles matter, reorder those three: sysrq first.

If the boot still fails, harvest by hand as below and start from the EARLY
snapshot — that is now the primary instrument. Note `boot-cycle.sh` does all of
this itself when the phone returns to the bootloader on its own; the manual
route is only for the `NEEDS PHYSICAL` case:

1. Power-cycle by hand: hold Power ~20 s, then Volume Down + Power. That lands
   in the bootloader.
2. Get into **TWRP** — the ROM has never booted, so TWRP's root shell is the
   only place `kpan` is readable:
   ```sh
   FB=/opt/android-sdk/platform-tools/fastboot
   A=/opt/android-sdk/platform-tools/adb
   timeout 15 $FB getvar product      # liveness probe, NOT `fastboot devices`
   $FB reboot recovery
   ```
3. Harvest *before* flashing anything (a flash does not touch kpan, but do not
   risk it). `adb devices` should show `<device-serial> recovery`:
   ```sh
   $A shell 'dd if=/dev/block/by-name/kpan bs=4096 count=2048' > /tmp/kpan.raw
   dd if=/tmp/kpan.raw bs=4096 count=1024 | tr -d '\000' > /tmp/early.txt
   dd if=/tmp/kpan.raw bs=4096 skip=1024 | tr -d '\000' > /tmp/late.txt
   ```
4. Read `early.txt` for what init did with `vendor.keymint-qti`.
5. Then run `./boot-cycle.sh` to test increment 1. It self-heals from TWRP
   (reboots to the bootloader over adb) and harvests both halves by itself —
   the manual steps above are only needed because this cycle exited at
   `NEEDS PHYSICAL` without reaching its harvest step.

Note `/usr/bin/adb` is broken (android-tools 37.0.0 wants libprotobuf 35.1.0,
Manjaro ships 34.1.0). Use `/opt/android-sdk/platform-tools/` (36.0.2, what the
scripts already use) or `~/Android/Sdk/platform-tools/` (34.0.5).

---

## 1. THE HEADLINE: the port is built the wrong way round

We have **8 `PRODUCT_PACKAGES` entries**. The official LineageOS device for the
**same SoC** has **220**. We declare **zero HAL services built from source**.

That single gap caused nearly every problem of the last two days. When HALs were
missing from our vendor image, the fix applied was to **copy 340 files out of
stock's vendor partition**. That substitutes Motorola's Android-14-era binaries
for a layer LineageOS is supposed to *compile*, and everything downstream
follows from it:

| symptom | actually caused by |
|---|---|
| `depends on multiple versions of the same aidl_interface` | blob built against old AIDL vs platform building current |
| ~12 `.replace_needed` version bumps | papering over the above |
| VINTF manifests declaring V3 while the ELF links V4 | the bumps, applied without updating manifests |
| endless `already defined by an in-tree source module` | our blobs colliding with what the tree already builds |
| keystore2 never starting (current blocker) | the VINTF/ELF mismatch |

**Do not continue patching blob-by-blob.** Restructure to the peridot shape.

---

## 2. THE REFERENCE DEVICE: peridot (not zeekr)

**Correction to earlier work: zeekr is NOT official.** No wiki page (404) and
absent from `LineageOS/hudson/lineage-build-targets`. Its tree lives in the
LineageOS GitHub org, which is not the same as official support. Treat it as a
useful but unverified reference.

**peridot IS official** — `peridot userdebug lineage-23.2 W` in
`lineage-build-targets`. Xiaomi, **SM8635 — the same SoC as arcfox** — on **our
exact branch**. This is the authoritative model.

Cloned at:
`<scratchpad>/peridot` (from `LineageOS/android_device_xiaomi_peridot`, branch `lineage-23.2`)
Re-clone with:
```sh
git clone --depth 1 --branch lineage-23.2 \
  https://github.com/LineageOS/android_device_xiaomi_peridot.git
```

### peridot vs us

| | peridot | ours |
|---|---|---|
| PRODUCT_PACKAGES | **220** | **8** |
| HAL services from source | many | **none** |
| `vendor/bin/hw` blobs | **18** | **73** |
| `vendor/etc/init/hw` blobs | 3 | 16 |
| device sepolicy files | **55** | **0** |
| own init scripts in `rootdir/` | init.target.rc, init.qcom.rc, init.qcom.factory.rc, init.peridot.rc, ueventd.qcom.rc, fstab.qcom | fstab only |
| blob list entries | 2436 | 2106 |

HALs peridot **builds from source** that we ship as blobs:
`android.hardware.boot-service.qti`, `health-service.qti`, `usb-service.qti`,
`wifi-service`, `sensors-service.*-multihal`, `drm-service.clearkey`,
`vendor.qti.hardware.display.allocator-service`,
`android.hardware.graphics.mapper@4.0-impl-qti-display`, audio impls, and more.

peridot's own `rootdir/etc/init.target.rc` contains the exact symlink we
discovered was missing — independent confirmation of that fix:
```
on init
    wait /dev/block/platform/soc/${ro.boot.bootdevice}
    symlink /dev/block/platform/soc/${ro.boot.bootdevice} /dev/block/bootdevice
```

Note peridot DOES ship `vendor.qti.hardware.display.composer-service;DISABLE_DEPS`
as a blob (we dropped it as a source duplicate — revisit).
It also uses genuine **version bumps** (`graphics.allocator-V1-ndk.so →
V2-ndk.so`), so version bumping IS distributable practice — but only when the
VINTF manifest is bumped with it.

---

## 3. PROPOSED PLAN (in order)

1. **Adopt peridot's `PRODUCT_PACKAGES` HAL list**, adapted: drop Xiaomi-specific
   entries (`displayfeature`, `batterysecret`, `touch-service.xiaomi`,
   `fingerprint-service.xiaomi`), keep the QCOM/AOSP ones.
2. **Delete the corresponding blobs** from `proprietary-files.txt` — the ones
   now built from source. Expect the list to shrink from ~2100 toward ~1000.
3. **Delete the `.replace_needed` version bumps and the VINTF `.regex_replace`
   fixups** they forced (in `sm8635-common/extract-files.py`). Source-built HALs
   link the right versions natively. Keep only naming fixes and genuinely
   missing deps.
4. **Author `rootdir/etc/init.target.rc` + `ueventd.qcom.rc`** from peridot's,
   instead of shipping Motorola's 16 `etc/init/hw` blobs.
5. **Port `peridot/sepolicy/vendor`** (55 files) as the base for
   `sm8635-common/sepolicy/vendor` (currently empty). Same SoC, so
   `file_contexts`/`genfs_contexts` should mostly apply.
6. Rebuild, run `./boot-cycle.sh`, iterate on logs.

Expect this to *remove* more than it adds. It is several hours but strictly less
work than continuing blob-by-blob, and it is the only shape that could ever be
published.

---

## 4. CURRENT STATE OF THE TREE

- Blob list: `device/motorola/sm8635-common/proprietary-files.txt` ~2106 entries
- `vendor.img` 2.57 GB, **73** `bin/hw` binaries, builds clean
- QCOM vendor sepolicy wired (`-include device/qcom/sepolicy_vndr/SEPolicy.mk`,
  `BOARD_VENDOR_SEPOLICY_DIRS` → 12 dirs incl. `generic/vendor/pineapple`);
  `sm8635-common/sepolicy/vendor` exists but is EMPTY
- `vendor_boot` built by us (dtb + 282 modules + our fstab)
- **dtb was silently wrong for hours** — `out/.../dtb.img` is copied at config
  time and ninja does NOT regenerate it. After changing `prebuilt/dtb/*`, always
  `rm out/target/product/arcfox/dtb.img` and verify md5. Same trap as
  `out/.../kernel` vs `TARGET_PREBUILT_KERNEL`.
- Permissive cmdline: **removed** (build is enforcing)
- Parked/dropped, all documented in the blob list: StrongBox keymint chain,
  `libkeystore-engine-wifi-hidl` (enterprise EAP only), clearkey/cas,
  qcom-caf-built composer + allocator services

## 5. THE INSTRUMENT THAT FINALLY WORKED

`device/motorola/arcfox/logger/` (+ wired in `arcfox/device.mk`) — a system-side
init service that dumps logcat/dmesg to the **raw `kpan` partition** every 5s,
and reboots to the bootloader itself if `sys.boot_completed` never turns 1.

Read it with:
```sh
adb shell 'dd if=/dev/block/by-name/kpan bs=4096 count=512' | tr -d '\000' > log.txt
```

**REMOVE BEFORE PUBLISHING** (`device.mk`, the `logger/` dir).

Why it was needed: this device has **no obtainable kernel log** — pstore/ramoops
is zeroed by the bootloader every boot, `/proc/last_kmsg` absent, `kpan` and
`ramdump` empty, `androidboot.console=0`. Only the bootloader's own log
(`logfs`, FAT16, `CurBoot.txt` + `Log*.txt`) is readable, and it stops at the
kernel handoff.

The clue that made it worth building: the bootloader log of the session AFTER a
failure showed `PM: Reset by PSHOLD` / `WARM_RESET_REASON1: "SOFT"` — a
**software** reset, i.e. init ran for minutes before giving up.

## 6. FAILURES FOUND WITH IT (chronological)

1. `android.hardware.boot-service.qti: failed to stat /dev/block/bootdevice/by-name/misc`
   → `Check failed: bootcontrol_init()` → SIGABRT → restart loop → init reboots
   at ~328s. **Fixed** by shipping `vendor/etc/init/hw/` (16 files) which create
   the `bootdevice` symlink. **The ~328s reboot loop is gone.**
2. `vold` blocking on `android.hardware.boot.IBootControl` — gone after (1).
3. VINTF fixups (manifest `<version>3</version>` vs binary linking
   `keymint-V4-ndk`) were applied and the manifest now reads `<version>4</version>`.
   **Result: still no boot**, and the boot now stalls EARLIER — the logger only
   reached `iteration 17, uptime 91s` (previous run reached `uptime 1096s`), and
   its self-reboot never fired, so the stall is at/near `post-fs`.

4. **CURRENT BLOCKER (exact, from the kpan log):**
   ```
   keystore2: Failed (attempt 1..6) to get_interface
       android.hardware.security.keymint.IKeyMintDevice/default: NAME_NOT_FOUND
   keystore2: Failed to construct mandatory security level TEE
   keystore2: Failed to create service android.system.keystore2.IKeystoreService/default
   ```
   Chain: **keymint HAL never registers -> keystore2 cannot build the TEE
   security level -> keystore2 dies -> vold blocks forever -> boot never
   completes.**

   Notably the log contains **no init lines for the keymint HAL service at all**
   (no "starting service", no exit/SIGABRT) - it is not merely crashing, it
   appears never to be started. Check, in order:
   - is `vendor/etc/init/android.hardware.security.keymint-service-qti.rc`
     actually in the built image, and what `class`/`disabled`/lazy attributes
     does it carry?
   - does the QCOM vendor sepolicy we wired actually provide a domain for it?
     `sm8635-common/sepolicy/vendor` is still EMPTY, and peridot carries 55
     device sepolicy files including per-HAL `.te` rules. A HAL with no domain
     transition cannot start when enforcing.
   - peridot ships `android.hardware.security.keymint-service-qti` as a BLOB
     (it is in its 18-entry `vendor/bin/hw` list), so blob is the right choice
     here - the problem is the surrounding policy/init, not the binary.
   - keymint depends on QSEECom/TEE; `qseecom-service` and `vendor.qseecomd`
     were seen exiting non-zero in an earlier log. Verify they run.

## 7. AUTOMATION (all in `workspace/motorola-lineageos/`)

| script | purpose |
|---|---|
| `boot-cycle.sh` | build → inject mount points → super → flash → boot test → auto-harvest logs. Self-heals from TWRP via adb. Exits 2 only if the phone needs a physical power-cycle. |
| `resolve-hal-deps.sh` | iterates the build, auto-handling 9 failure classes (see HANDOFF.md). Analysis-only via `mka nothing` (~11s/round vs ~90s). |
| `add-missing-hals.sh` | syncs missing files from stock's vendor. **Has an EXCLUDE list — respect it.** |
| `build-super-mix.sh` | assemble super from any mix of our/stock images (`all`, `none`, or partition names; `STOCK_DLKM=1`) |
| `inject-vendor-mountpoints.sh` | creates `/vendor/{firmware_mnt,dsp,bt_firmware,fsg,rfs}`. MUST run after `mka vendorimage` — soong cannot create these dirs. |
| `restore-stock.sh --full` | escape hatch, ~90s |

### Traps that cost real time
- `pgrep`/`pkill -f <script>` **matches its own wrapper** — kill by PID instead.
  Cost two 3-hour zombie loops and one self-killed job.
- `fastboot devices` only proves USB enumeration. **Probe `fastboot getvar
  product`** before long flashes (already in project memory).
- Stale `out/` artifacts (`dtb.img`, `kernel`) are NOT regenerated by ninja.
- `extract_utils` does **not** auto-install a HAL's `.rc`/vintf `.xml` — the
  generated `cc_prebuilt_binary` has no `init_rc`. If it is not in
  `proprietary-files.txt`, it does not ship. A bulk removal of 90 such files
  broke the boot HAL and cost hours.
- Blob fixups only apply in the extract script that **owns the blob list** —
  putting them in `arcfox/extract-files.py` for a blob listed in
  `sm8635-common/` silently does nothing.

## 8. DEVICE STATE / SAFETY

Phone is a spare; daily driver is a Pixel on GrapheneOS. Bootloader always
reachable (Power ~20s → Volume Down + Power). `./restore-stock.sh --full`
restores stock Android. TWRP 4.3.2 is on the recovery partition and gives a root
shell — it is the standing diagnostic instrument.

A/B retry: `fastboot getvar slot-retry-count:a` (7 fresh); `fastboot
--set-active=a` resets it. `misc` is write-protected over fastboot, so a BCB
recovery loop can only be escaped by flashing stock recovery and exiting via its
menu.

## 9. STILL TRUE / STILL UNKNOWN

- ROM has **never booted**. Everything structural is proven good (our
  boot/init_boot/vbmeta boot stock's super); the failure is userspace bring-up.
- Wi-Fi, fingerprint, face unlock were parked then restored via fixups — status
  after the restructure needs re-checking.
- Missing vs stock: `pvmfw` vbmeta descriptor (not in fstab, likely irrelevant),
  `manifest_cliffs.xml` SKU selection (merged 5 entries, unverified),
  `BOARD_SEPOLICY_VERS` 202504 vs stock 34.0 (unexplained, may resolve itself
  once HALs are source-built).

---

## 0.29 FIRST FLASH OF THE FROM-SOURCE KERNEL (2026-08-29) — SUCCESS

**Flashed and verified on two cold boots.** Kernel
`6.1.145-20325-g68aa901c5c56` (Motorola source + ACK r34 merge), built entirely
from source, with all 287+60 modules built from source. The 629 committed `.ko`
prebuilts are gone — the official-support charter blocker is cleared on-device,
not just in the tree.

Measured, identical on boot 1 and boot 2:

| | |
|---|---|
| modules loaded | 439 |
| system_dlkm | 58/60 (missing: `zram`, `zsmalloc` — load on demand) |
| vendor_dlkm | 282/285 (`ipclite_test`, `llcc_perfmon` blocklisted; `icnss2` is the unused alternate WLAN attach mode) |
| WiFi | `wlan0`, `p2p0`, `wifi-aware0` present; `qca_cld3_kiwi_v2` loaded |
| data | 8 `rmnet` interfaces, `tipc` loaded, SIM `LOADED` |

### ⚠️ NEW HARD RULE: fastbootd cannot flash anything on arcfox

`fastboot flash vendor_dlkm` from fastbootd fails
`Writing … FAILED (remote: 'No such file or directory')`, and
`getvar partition-size:super` fails `Could not open partition` — as does every
other logical partition AND `super` itself. Reproduced on two fresh entries.
The identical getvar from the **bootloader** returns `0x0000000632700000`.

So a failure there is **not** damage to the partition being flashed; nothing is
written. Use the bootloader, always. **Full procedure now in `FLASHING.md`** —
read it before any flash.

### The three latent bricks caught pre-flash (all from one removed config block)

1. `system_dlkm.img` 348 KB with **0 modules** — all 60 (incl. `tipc`,
   `rfkill`, `bluetooth`) had fallen into vendor_dlkm. Cause: missing
   `SYSTEM_KERNEL_MODULES`.
2. Modules installed **flat**. `/vendor/bin/system_dlkm_modprobe.sh:15` requires
   `${dir}/*/modules.load`; flat silently loads nothing. Cause: missing
   `TARGET_KERNEL_VERSION`.
3. Still flat — `GKI_SUFFIX` is *also* gated on `BOARD_USES_QCOM_HARDWARE`, and
   setting that breaks soong (`vendor.qti.hardware.display.composer-service.xml`
   found in multiple namespaces). Set `GKI_SUFFIX` **directly** instead.

Each would have booted a device with no WiFi/BT/data — the §0.19 disaster again.
Proof the fix took: 58/60 system_dlkm modules load. A flat layout loads **zero**.

### Coherence: vendor_boot must now be flashed too

The old "vendor_boot stays stock by design" note is **void**. It held only while
we shipped the prebuilt GKI, whose vermagic matched stock's. With our own
kernel, stock's first-stage ramdisk modules belong to a different kernel.
`vendor_boot.img` was rebuilt (`m vendorbootimage` — note: **not**
`vendor_bootimage`) and flashed. All four vermagic now match exactly.

### OPEN — not verified

* **The bootarg MAC parser is UNPROVEN.** `/proc/cmdline` does carry
  `wifimacaddr=AA:BB:CC:DD:EE:01,AA:BB:CC:DD:EE:02`, but `wlan0`'s actual MAC
  could not be read: sysfs, `ip`/netlink and `dmesg` are all denied to the shell
  user, and `adb root` is refused ("disabled by system setting"). Writing
  `settings put global adb_root 1` did not take — the device is still
  pre-provisioning (`device_provisioned=0`). **To verify: finish the setup
  wizard, enable Developer options → Rooted debugging, then**
  `adb root && adb shell cat /sys/class/net/wlan0/address` — expect
  `aa:bb:cc:dd:ee:01`. Do not claim the parser works before this.
* **628 AVC denials** on a clean boot (excluding self-inflicted `shell` ones).
  Dominated by `batt_health`/`hal_health_default`/`hal_sensors_default` file
  reads. Notable: `hal_fingerprint_default service_manager { add }` ×6 and
  several `rild` denials. Not triaged.

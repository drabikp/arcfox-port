# arcfox hardware contract — findings

Motorola Razr 50 Ultra / Razr+ 2024. Captured 2026-08-06 from stock Android 14,
fingerprint `motorola/arcfox_ge/arcfox:14/U3UXS34.56-124-1-1/37063f-d7f623:user/release-keys`.

Everything below is read off the device, not inferred. Raw captures are in
`contract/`, and the reasoning that motivated them is in the design doc at
`~/.gstack/projects/motorola-lineageos/peyko-unknown-design-20260806-155136.md`.

## Identity

| Property | Value |
|---|---|
| `ro.product.device` | `arcfox` |
| `ro.board.platform` | `pineapple` |
| SoC | SM8635 (Snapdragon 8s Gen 3) |
| Stock Android | 14 |
| Build ID | `U3UXS34.56-124-1-1` |
| Variant | `arcfox_ge` (global edition) |

`U3UXS34.56-124-1-1` matters beyond identification: Motorola names its published
kernel branches after build IDs (see the `android-15-release-v1tl35.73-60-3`
style branches in `MotorolaMobilityLLC/kernel-kernel_device_modules-6.6`). This
is the string to search when hunting for matching kernel sources.

## Displays

| Address | Port | Resolution | Type | Density | Cutout |
|---|---|---|---|---|---|
| `local:4630947043778501763` | 131 | 1080x2640 | INTERNAL, "Built-in Screen" | 420 | yes, `M -45,0 L 45,0 L 45,108 L -45,108 Z` |
| `local:4630947043778501764` | 132 | 1080x1272 | EXTERNAL, "HDMI Screen" | 360 | none |

**...763 is the inner display. ...764 is the cover display.** Both report
`model=0x40446dccee101c`. Both support 24/30/60/90/120/165Hz. Rounded corner
radius 63 on both. The cover display carries `FLAG_PRESENTATION`,
`FLAG_OWN_CONTENT_ONLY` and `FLAG_OWN_DISPLAY_GROUP`, and sits in
`displayGroupId 1` with `layerStack 1`.

### The trap

zeekr (Razr 40 Ultra) uses `...762` for the inner display and `...763` for the
cover. **arcfox is shifted by one.** The consequence of copying zeekr's
`fold/display_layout_configuration.xml` unmodified:

- `defaultDisplay` in the OPENED layout points at `...762`, **which does not
  exist on arcfox**
- the same layout sets `enabled="false"` on `...763`, **which is arcfox's inner
  display**

That does not fail loudly. It produces a device with no valid default display
and the main panel disabled, with nothing in the log naming an address.

(An earlier draft of this document guessed that this trap was what stopped the
December 2025 attempt at `Motorola-Pineapple/android_device_motorola_arcfox`.
The gap analysis below disproves that: both blob manifests there are empty, so
no build ever existed to boot, and the tree has no `fold/` directory at all.
The trap is ahead of that work, not behind it.)

**`display_layout_configuration.xml` must be authored from these addresses.**

### And there is no stock reference for it

`find /vendor /system /product /odm /system_ext -iname '*display_layout*'`
returns nothing. Stock does not use AOSP's display-layout config; `mCurrentLayout`
stays pinned to `port=131` in every hinge position. Motorola routes the cover
display through its own layer.

So: stock tells you the device-state half of the fold and tells you **nothing**
about the display-routing half. zeekr is the only reference for that file and its
values are wrong here. This is the hardest open problem in the port.

## Device states

Stock drives AOSP's `DeviceStateManager` directly. Verified live:

```
open    → DeviceState{identifier=5, name='OPENED',      app_accessible=true}
closed  → DeviceState{identifier=0, name='CLOSED_HALL', app_accessible=false}
```

The full stock table, pulled verbatim to
`contract/common/devicestate/device_state_configuration.xml`:

| id | name | condition |
|---|---|---|
| 0 | `CLOSED_HALL` | lid-switch open=false |
| 1 | `CLOSED` | lid open + posture [0,45) |
| 2 | `TENT` | lid open + posture [0,90], `value[1] >= 1` |
| 3 | `HALF_OPENED_QVD` | lid open + posture [45,90) |
| 4 | `HALF_OPENED_MAIN` | lid open + posture [90,180) |
| 5 | `OPENED` | lid open + posture [90,180] |
| 6 | `OPENED_HALL` | lid open |

States 0-3 carry `FLAG_APP_INACCESSIBLE`.

### arcfox does not detect the fold the way zeekr does

| | zeekr LineageOS config | arcfox stock |
|---|---|---|
| closed detection | `com.motorola.sensor.hall`, value 2 | `<lid-switch><open>false</open></lid-switch>` |
| angle source | `android.sensor.hinge_angle` (scalar degrees) | `com.motorola.sensor.hinge_posture` (vector) |
| state count | 4 | 7 |

`hinge_posture` emits a vector, not a scalar. `value[0]` is the angle in degrees,
`value[1]` distinguishes TENT, `value[2]` is a third flag (unobserved so far,
always 0 in the captures taken). Motorola computes posture in the sensor instead
of making the framework threshold a raw angle.

Both of zeekr's mechanisms *do* exist on arcfox, so zeekr's approach might work.
But stock's approach is known-good on this exact hardware and should be preferred.

### Sensors present

```
0x0000016a  Hinge Angle  Wakeup      Motorola     android.sensor.hinge_angle(36)
0x000100b6  Flip to Mute  Wakeup     Motorola     com.motorola.sensor.ftm(65554)
0x000100de  Flip Position  Wakeup    Motorola     com.motorola.sensor.flip(65558)
0x000101ba  Flip Hall Effect Wakeup  haechitech   com.motorola.sensor.hall(65580)
0x000101d8  Hinge Posture  Wakeup    Motorola     com.motorola.sensor.hinge_posture(65583)
0x0001025a  Flip Approach  Wakeup    Motorola     com.motorola.sensor.fip_approach(65596)
0x00010264  Flip Presence  Wakeup    Motorola     com.motorola.sensor.fip_presence(65597)
```

Note the **double space** in `Hinge Angle  Wakeup`, `Hinge Posture  Wakeup` and
the rest. `DeviceStateManager` matches sensors on this name string exactly, so
the double space must be preserved in any config file.

### Lid switch

Real kernel input device, from `getevent -il`:

```
name: "MotFlip_LID"
  SW (0005): SW_LID*
```

### Observed posture values

All three hinge positions captured live, with timestamps across each transition,
so these are real readings rather than defaults.

| position | reported state | `hinge_posture` | `com.motorola.sensor.flip` |
|---|---|---|---|
| open (flat) | `5 / OPENED` | `180.00, 0.00, 0.00` | `1.00, 1.00` |
| ~90° standing | `4 / HALF_OPENED_MAIN` | `90.00, 0.00, 0.00` | `1.00, 3.00` |
| closed | `0 / CLOSED_HALL` | `0.00, 0.00, 0.00` | `2.00, 2.00` |

### What the three samples prove about the state machine

`HALF_OPENED_MAIN` is `[90,180)` and `OPENED` is `[90,180]`. Those overlap on
everything except the endpoint, so **the only thing separating them is whether
the angle is exactly 180**. Conditions are evaluated in identifier order and the
first match wins, which is confirmed by observation: at 90 the device reports 4,
at 180 it reports 5. So "half opened main" means anything from 90 up to but not
including fully flat.

`TENT` did not trigger at 90°. It requires `hinge_posture value[1] >= 1`, and
`value[1]` stayed `0.00` throughout. So `value[1]` is not an angle refinement,
it is an orientation flag: TENT is the phone resting inverted on both edges, not
merely a hinge angle. `value[2]` was `0.00` in all three positions and its
meaning remains unobserved.

`com.motorola.sensor.flip` is a separate, simpler signal that stock does **not**
use in the device-state config: `value[0]` is binary (1 = not closed, 2 = closed)
and `value[1]` is three-way (1 = open, 2 = closed, 3 = half). Available as a
fallback if posture proves awkward.

### hinge_posture is quantized — verified by physical sweep

Suspecting quantization from three identical-looking readings, the hinge was swept
slowly through its full range while `dumpsys sensorservice` was polled. During
continuous physical motion the sensor emitted only discrete values.

**The complete observed set is `{0, 70, 90, 110, 180}`.** Five rungs. Nothing
between 0 and 70, nothing between 110 and 180, and 20 degrees apart in the middle
cluster. It is a sparse ladder, not uniform bucketing and definitely not a
continuous angle.

A single closed-to-open motion produced `0 → 90 → 180`, **skipping 70 and 110
entirely**. So a transition may skip rungs depending on how fast the hinge moves,
and you cannot rely on observing every value.

Consequence for authoring the config, and this is the important part:

| Stock state | Range | Reachable values |
|---|---|---|
| `CLOSED` | [0,45) | `0` |
| `HALF_OPENED_QVD` | [45,90) | **`70` only** |
| `HALF_OPENED_MAIN` | [90,180) | `90`, `110` |
| `OPENED` | [90,180] | `180` |

Every stock bucket contains one or two reachable rungs, and `HALF_OPENED_QVD`
contains exactly one. **Thresholds written against an assumed continuous angle can
produce states that are silently unreachable**, because no quantized value falls
inside them. Nothing in any log will say so.

This is the second reason not to port zeekr's fold config by analogy: it uses
`android.sensor.hinge_angle` with ranges like `[0,5)` for CLOSED and `[5,120]` for
HALF_OPENED. Against a five-rung ladder, `[0,5)` is reachable only at exactly 0.
Keep stock's thresholds unless you have re-derived the ladder yourself.

## What this means for the device tree

1. **Author `fold/display_layout_configuration.xml` from the addresses above.**
   Never copy zeekr's. This is the finding that justified the whole spike.
2. **Start `fold/device_state_configuration.xml` from the stock file**, not from
   zeekr's, then decide how to collapse 7 states into what LineageOS overlays
   expect.
3. **Map identifiers in `overlay-lineage`.** AOSP keys folded/half/open behavior
   off `config_foldedDeviceStates`, `config_halfFoldedDeviceStates` and
   `config_openDeviceStates`, which are integer arrays referencing the
   identifiers above. Names are arbitrary; the identifiers are what matter.
4. **The inner display has a cutout, the cover display does not.** zeekr has
   commits both adding and later removing cutout definitions ("Remove cutout def
   for now", "Disable cutout for outer screen"), so expect to iterate here.

## Gap analysis: zeekr's tree vs arcfox's

Both device trees and both common trees were cloned and compared on 2026-08-06.

### The headline: the arcfox tree never booted, and could not have

Both blob manifests are empty. Not sparse. Empty:

```
$ cat android_device_motorola_arcfox/proprietary-files.txt
# TODO: Bringup proprietary-files.txt

$ cat android_device_motorola_sm8650-common/proprietary-files.txt
# TODO: Bringup proprietary-files.txt
```

zeekr's equivalents are **496 lines** (device) and **1177 lines** (common). So
`extract-files.py` against the arcfox tree pulls **zero** blobs, and
`device.mk` inherits `vendor/motorola/arcfox/arcfox-vendor.mk`, a file that only
exists once blobs have been extracted.

**This retires an earlier hypothesis in this document.** The display-address trap
was called "a strong candidate for whatever stopped the December 2025 attempt."
That is almost certainly wrong. With an empty blob list there was never a build
to boot, and the tree has no `fold/` directory at all, so display routing was
never reached. The tree is scaffolding that was published and then abandoned
before bringup began. The display trap is real and still waiting, but it lies
ahead of that work, not behind it.

Practical consequence: **do not read the December stall as evidence of a hardware
wall.** Nothing in the tree suggests anyone hit one.

### Device tree: what arcfox has vs what zeekr has

arcfox has 9 files. zeekr has those plus everything below.

| Missing from arcfox | Files | What it does |
|---|---|---|
| `fold/` | 4 | device-state + display-routing config. The whole foldable behavior. |
| `resource-overlay/` | 18 | per-SKU framework resource overrides |
| `audio/` | 9 | audio policy and mixer paths |
| `manifests/` | 4 | VINTF manifest fragments |
| `sepolicy/` | 2 | SELinux policy |
| `overlay-lineage/` | 2 | LineageOS-specific overlays |
| `permissions/` | 1 | feature declarations |
| `rootdir/` | 1 | init `.rc` files |
| `product.prop`, `system.prop`, `vendor.prop` | 3 | build properties |
| `proprietary-files-carriersettings.txt` | 1 | carrier config blobs |
| `reorder-libs.py` | 1 | blob fixup helper |

Line counts on the files that *do* exist in both:

| File | zeekr | arcfox |
|---|---|---|
| `BoardConfig.mk` | 68 | 37 |
| `device.mk` | 110 | 36 |
| `proprietary-files.txt` | 496 | **1** |

### Common tree: sm8475-common vs sm8650-common

Worse. `sm8650-common` has 7 files; `sm8475-common` has roughly 35 entries.

Missing includes `lineage.dependencies` (so **the kernel is never fetched**),
`modules.load` / `modules.load.vendor_boot` / `modules.blocklist` (so no kernel
modules load), plus `audio`, `sensors`, `touch`, `wifi`, `gps`, `location`,
`media`, `vibrator`, `fingerprint`, `livedisplay`, `recovery`, `sepolicy`,
`rootdir`, `overlay-lineage`, `resource-overlay`, the VINTF matrix and manifests,
`ims-patches`, and the `sm8475.mk` product makefile.

| File | sm8475-common | sm8650-common |
|---|---|---|
| `BoardConfigCommon.mk` | 264 | 43 |
| `proprietary-files.txt` | 1177 | **1** |

### The four fold files, with arcfox's exact names

From zeekr's `device.mk`, the fold config is wired via `PRODUCT_COPY_FILES` into
two vendor directories. The `display_id_*.xml` filenames **encode the display
address**, so arcfox's differ:

| Source | Destination | arcfox filename |
|---|---|---|
| `fold/device_state_configuration.xml` | `/vendor/etc/devicestate/` | same name |
| `fold/display_layout_configuration.xml` | `/vendor/etc/displayconfig/` | same name |
| `fold/display_id_<inner>.xml` | `/vendor/etc/displayconfig/` | `display_id_4630947043778501763.xml` |
| `fold/display_id_<outer>.xml` | `/vendor/etc/displayconfig/` | `display_id_4630947043778501764.xml` |

zeekr also copies `android.hardware.sensor.hinge_angle.xml` and
`android.hardware.sensor.hifi_sensors.xml` into `vendor/etc/permissions/sku_cape/`.

The `display_id_*.xml` files are small, roughly 20 lines. zeekr's inner one sets
a name and enables auto-brightness. The outer one adds a
`canSetBrightnessViaHwc` quirk and a `densityMapping`. For arcfox the outer
mapping should read `1080 x 1272 → density 360`, which matches the captured
`DisplayDeviceInfo`.

**Note that arcfox stock has no `/vendor/etc/displayconfig/` directory at all**
(verified: `ls` fails, and a `find` across `/vendor /odm /product` returns
nothing). So all four files are authored by the port, not adapted from stock.
Stock supplies only the device-state half, via `/vendor/etc/devicestate/`.

### Suggested order

1. `proprietary-files.txt` for both trees, then `extract-files.py`. Nothing else
   can be tested until blobs exist.
2. `lineage.dependencies` in the common tree so the kernel is actually fetched.
3. `modules.load` / `modules.blocklist`, then attempt a `bootimage`.
4. Only then `fold/`, once there is something that boots to observe.

## UPDATE 2026-08-06 (evening): re-captured on Android 16

The handset was updated and everything below was re-verified on the build
machine (`hypnone`, Ryzen 9 5950X, 32 threads, 125GB RAM, 457GB free).

```
motorola/arcfox_ge/arcfox:16/W1UXS36H.72-45-10-7/33779-0863b:user/release-keys
vendor security patch  2026-07-01     (was 2024-12-01)
kernel                 6.1.145-android14-11-geaa643a2c0ee-ab14763719
```

### Correction: the vendor API level did NOT move

An earlier section of this document argued for updating on the grounds that it
would take vendor from API 34 to API 36 and remove Treble skew. **That reasoning
was wrong.**

```
ro.board.api_level      34
ro.product.first_api_level  34
ro.vndk.version         34
```

Vendor stays frozen at 34 across an OS upgrade. That is Android's vendor-freeze
design working as intended: the system and framework move to Android 16, the
vendor interface does not get re-based. The GKI ABI is likewise still
`android14-11`.

The update was still the right call, for a better reason: **Motorola now ships
and tests Android 16 against this exact vendor image.** LineageOS builds the
system image while the vendor image stays Motorola's, so "does an Android 16
system work on this API-34 vendor" is now answered by the OEM rather than by you.
Plus 19 months of security patches, and blobs extracted from an
Android-16-shipping image.

### Display addresses: unchanged

`local:4630947043778501763` port 131 inner, `local:4630947043778501764` port 132
outer. The address-shift trap versus zeekr still applies exactly as documented.

### The cover display is now a first-class internal display

| | Android 14 | Android 16 |
|---|---|---|
| name | `"HDMI Screen"` | `"Built-in Screen"` |
| type | `EXTERNAL` | **`INTERNAL`** |
| flags | identical | identical |

On Android 14 Motorola presented the cover panel as an external display, a
workaround for a framework without real flip support. Android 16 treats it as a
genuine internal secondary display.

### The fold config schema changed, and it carries display routing now

The seven-state table is **identical**: same identifiers, names, conditions and
thresholds. Only the schema moved. Android 16 replaced `<flags>` with
`<properties>`:

| Android 14 | Android 16 |
|---|---|
| `FLAG_APP_INACCESSIBLE` | `com.android.server.policy.PROPERTY_APP_INACCESSIBLE` |
| `FLAG_CANCEL_OVERRIDE_REQUESTS` | `...PROPERTY_POLICY_CANCEL_OVERRIDE_REQUESTS` |

**Third trap:** zeekr's `device_state_configuration.xml` uses the old `<flags>`
schema, including `FLAG_CANCEL_OVERRIDE_REQUESTS` and `FLAG_EMULATED_ONLY`.
Copying it onto a LineageOS 23 build writes a deprecated schema against an
Android 16 framework.

**And the good news.** The new properties encode display routing directly:

```
0 CLOSED_HALL        FOLD_IN_CLOSED     + OUTER_PRIMARY  + APP_INACCESSIBLE
1 CLOSED             FOLD_IN_CLOSED     + OUTER_PRIMARY  + APP_INACCESSIBLE
2 TENT               FOLD_IN_CLOSED     + OUTER_PRIMARY  + APP_INACCESSIBLE
3 HALF_OPENED_QVD    FOLD_IN_CLOSED     + OUTER_PRIMARY  + APP_INACCESSIBLE
4 HALF_OPENED_MAIN   FOLD_IN_HALF_OPEN  + INNER_PRIMARY
5 OPENED             FOLD_IN_OPEN       + INNER_PRIMARY
6 OPENED_HALL        FOLD_IN_OPEN       + INNER_PRIMARY  + APP_INACCESSIBLE
```

`PROPERTY_FOLDABLE_DISPLAY_CONFIGURATION_OUTER_PRIMARY` / `_INNER_PRIMARY`
declare which panel is primary per state. **This is the display-routing
information that the section above says must be authored from scratch into
`display_layout_configuration.xml`.** `/vendor/etc/displayconfig/` still does not
exist on the device, which is now consistent rather than mysterious: on Android
16 the properties carry the routing.

So the "hardest open problem in the port" is materially smaller than assessed
this morning. Verify empirically whether `display_layout_configuration.xml` is
needed at all on a LOS 23 build before authoring one.

The A16 config is saved at
`contract/common/devicestate/device_state_configuration.xml`; the A14 baseline
remains at `contract-android14/common/devicestate/`.

### Sensors

All seven still present, same names including the double spaces.

### Complete state set, verified on Android 16

Four physical positions captured. Every state matches Motorola's XML.

| Position | State | id | `app_accessible` | `hinge_posture` |
|---|---|---|---|---|
| fully open, flat | `OPENED` | 5 | true | `180.00, 0.00, 0.00` |
| ~110°, hinge at bottom | `HALF_OPENED_MAIN` | 4 | true | `110.00, 0.00, 0.00` |
| ~70°, crease UP, on both edges | `TENT` | 2 | false | **`70.00, 1.00, 0.00`** |
| lid shut | `CLOSED_HALL` | 0 | false | `0.00, 0.00, 0.00` |

**`value[1]` is resolved.** It reads `1.00` in tent and `0.00` in every other
position ever measured. It is an orientation flag, not an angle refinement,
exactly as stock's `<min-inclusive>1</min-inclusive>` on the second value
implied. TENT and `HALF_OPENED_MAIN` can share a hinge angle; orientation is
what separates them.

Practical consequence for anyone reproducing this: **the capture positions are
about orientation, not just angle.** `capture-contract.sh` now takes a `tent`
argument and documents the distinction.

Rung confirmations on Android 16: `0`, `70`, `110`, `180`. The ladder survived
the OS upgrade. One transition was observed as `0 → 180 → 110`, skipping rungs
again, which is the behavior that makes hand-authored thresholds fragile.

`value[2]` was `0.00` in all four positions and remains unexplained.

### Branch decision

LineageOS branches currently published: `22.1`, `22.2`, `23.0`, `23.1`, `23.2`,
`24.0`. Target **`lineage-23.x`** to match the Android 16 system, with `23.2`
being where the officially supported SM8635 device (`peridot`) sits.

## Blob manifest: tiered split

`split-manifest.sh` turns the candidate list into per-tree drafts. The split
reuses **zeekr's own device/common judgment** rather than inventing heuristics: a
working Motorola foldable port already decided which paths are SoC-generic, so
Tier 1 inherits that decision. Heuristics apply only to paths zeekr never had.

| Tier | Count | Destination |
|---|---|---|
| 1 device | **278** | `device/motorola/arcfox/proprietary-files.txt` |
| 1 common | **739** | `device/motorola/sm8635-common/proprietary-files.txt` |
| 2 device hardware | **81** | append to device manifest — camera/sensor tuning, panel, touch |
| 2 vendor on-demand | 2014 | hold; add only when a build failure names one |
| 3 excluded | **8822** | deliberately dropped |

### Tier 2 is where arcfox stops resembling zeekr

```
vendor/etc/camera/aec_golden_tele.bin        telephoto AEC calibration
vendor/etc/camera/dual_golden_tele.bin       dual-camera telephoto calibration
vendor/etc/sensors/config/lanai_*.json       29 sensor configs, lanai = SM8635
vendor/bin/hw/com.motorola.hardware.display.panel-service
vendor/bin/hw/com.motorola.hardware.display.touch-service
vendor/bin/init.mmi.touch.sh
```

zeekr cannot have the telephoto calibration: the Razr 40 Ultra has an ultrawide
where arcfox has a 2x tele. None of this was reachable from adb.

Known heuristic defect: `media_codecs_google_telephony.xml` and
`apq_excluded_telephony_features.xml` matched on "tele" as in *telephony*.
Mislabelled, harmless to include. Checked and cleared: three `mtplanai*` QVR
config files are a "lanai" substring coincidence, not misfiled sensor configs;
all 29 real sensor configs classify correctly.

### Tier 3 is the point of the project

8822 files under `product/`, `system/` and `system_ext/`, including 399 app
payloads. A sample of what gets dropped:

```
product/app/ARCore
product/app/com.amazon.mShop.android.shopping
product/app/com.google.mainline.telemetry
product/app/com.google.mainline.adservices
product/app/CLIGameHub
```

Excluded on purpose, listed so the exclusion is a decision on record rather than
an oversight. **Do not speculatively add Tier 2 on-demand entries either** —
adding a thousand blobs to silence one error hides the next twenty.

## Device tree: what has been authored so far

Under `device-tree/`, ready to drop into `device/motorola/arcfox`.

| File | Status |
|---|---|
| `fold/device_state_configuration.xml` | Motorola's stock A16 table verbatim, with a provenance and threshold-safety header. All 7 states physically reproduced. |
| `fold/display_layout_configuration.xml` | **Authored.** No stock reference exists and zeekr's is unusable (address shift). Maps all 7 states to the correct panel. |
| `fold/display_id_4630947043778501763.xml` | Inner panel, 1080x2640, density 420. |
| `fold/display_id_4630947043778501764.xml` | Outer panel, 1080x1272, density 360, `canSetBrightnessViaHwc` quirk (carried from zeekr, unverified here). |
| `overlay-lineage/.../config.xml` | `config_foldedDeviceStates` {0,1,2,3}, half {4}, open {5,6}, rear {} . |
| `fold-device.mk` | `PRODUCT_COPY_FILES` wiring with correct destination directories. |

All five XML files parse. Address audit confirms only `...763` and `...764`
appear — zeekr's `...762` never leaked in.

**Why the overlay is needed despite the new properties:** both mechanisms are
live in LineageOS 23.2. `PROPERTY_FOLDABLE_*` is defined in
`frameworks/base/core/java/android/hardware/devicestate/DeviceState.java`, but
the legacy arrays are still referenced across frameworks/base
(`config_foldedDeviceStates` in 22 files, `config_halfFoldedDeviceStates` in 6,
`config_openDeviceStates` in 8). Declaring only the properties leaves those paths
reading empty arrays. Verified by grepping the synced source, not assumed.

**Still to verify empirically:** whether `display_layout_configuration.xml` is
needed at all on Android 16, given the `INNER_PRIMARY` / `OUTER_PRIMARY`
properties may carry routing on their own. Stock ships without the file. Test
with it, then without.

## FLASHING: BLOCKED after 2 attempts — open problem

Both attempts ended in **"No valid operating system found"**, both fully
recovered with `restore-stock.sh` (~90s each). The phone is on stock Android 16
and healthy. `super` was never written; no data at risk at any point.

### Attempt 2 (the one that disproved my theory)

Patched the **stock, Motorola-signed** vbmeta directly instead of using ours:

```
flags at byte offset 120 (big-endian uint32) : 0 -> 3
   1 = AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED
   2 = AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED
verified: Public key sha1 fd29248b...  (Motorola's, preserved)
          Rollback Index 26, Flags 3
```

```
fastboot flash vbmeta     /tmp/stock_vbmeta_patched.img  -> OK
fastboot flash boot       our/boot.img                   -> OK
fastboot flash init_boot  our/init_boot.img              -> FAILED (remote: '')
fastboot flash recovery   our/recovery.img               -> OK
fastboot reboot recovery                                 -> "no valid OS"
```

So a Motorola-signed vbmeta with verification disabled is **not** sufficient.
My attempt-1 diagnosis (wrong signing key) was wrong, or at least incomplete.

### What the evidence actually says

**`init_boot` is rejected at FLASH time**, with verification disabled in vbmeta,
while the stock `init_boot.img` flashes without complaint seconds later. A
preflash rejection cannot be an AVB-at-boot problem — it means this bootloader
performs its **own** signature validation on write, independent of AVB flags.

That most likely explains the boot failure too: the bootloader is refusing our
`boot`/`recovery` for the same reason it refused `init_boot`, just at boot time
rather than flash time.

Also worth noting: `fastboot --disable-verity --disable-verification flash
vbmeta` fails with "Failed to find AVB_MAGIC at offset: 0" **even on the stock
image**, while the same flags work fine on `vbmeta_system`. That looks like a
fastboot 36.0.2 quirk specific to the `vbmeta` partition, not an image problem —
hence patching byte 120 by hand.

### The lead worth following

**TWRP has been run successfully on this exact handset.** Custom images therefore
CAN execute; the procedure is what differs. The most likely difference:

```sh
fastboot boot recovery.img     # loads into RAM, writes NOTHING
```

rather than `fastboot flash recovery`. RAM-booting bypasses whatever preflash /
boot-time validation is rejecting written images, it is completely
non-destructive, and it is how most people run TWRP on locked-down Motorola
bootloaders. If `fastboot boot our-recovery.img` brings up LineageOS recovery,
sideloading the ROM from there is the whole remaining path.

Second avenue: the arcfox XDA threads
(`xdaforums.com/t/...arcfox.4685914`) document the working flash procedure for
this device. Unreadable from here (bunny.net blocks agent tooling) but readable
in a normal browser.

## FLASH ATTEMPT 1 — the first failure

Result: **"No valid operating system found"**. Fully recovered by restoring the
stock boot chain (`restore-stock.sh`); phone is back on stock Android 16 with
`boot_completed=1` and the fold state machine working. Nothing was lost — the
`super` partition was never written, because the OTA never installed.

### What was flashed

```
fastboot --disable-verity --disable-verification flash vbmeta  our/vbmeta.img
        -> fastboot: error: Failed to find AVB_MAGIC at offset: 0
fastboot flash boot        our/boot.img        -> OK
fastboot flash init_boot   our/init_boot.img   -> Preflash validation failed
fastboot flash recovery    our/recovery.img    -> OK
fastboot flash vbmeta      our/vbmeta.img      -> OK   (plain, no flags)
```

### The mistake

**Our `vbmeta.img` is signed with the AOSP test key**
(`SHA256_RSA4096`, pubkey sha1 `2597c218aae470a130f61162feaae70afd97f011`).
Motorola's bootloader validates vbmeta against **its own fused key** and rejects
anything else, so the whole boot chain was refused.

`BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 2` sets VERIFICATION_DISABLED
*inside* the image, but that flag is only honoured once the image's signature is
trusted. On a device whose bootloader does not trust your key, it does nothing.

Corroborating evidence: `init_boot` was rejected with "Preflash validation
failed" while unsigned-by-Motorola, and the **stock** `init_boot.img` flashed
without complaint moments later. The bootloader was enforcing signatures the
whole time.

### The correct procedure

Flash the **STOCK** vbmeta and let fastboot patch the disable flags into it. That
keeps Motorola's signature intact while switching verification off:

```sh
STOCK=".../ARCFOX_G_W1UXS36H.72_45_10_7_..._CFC.xml"
fastboot --disable-verity --disable-verification flash vbmeta "$STOCK/vbmeta.img"
fastboot --disable-verity --disable-verification flash vbmeta_system "$STOCK/vbmeta_system.img"
# only then:
fastboot flash boot     out/.../boot.img
fastboot flash recovery out/.../recovery.img
# init_boot should now pass preflash; if not, leave stock and let the OTA write it
fastboot reboot recovery
# in LineageOS recovery: Factory reset -> Format data, then Apply update -> ADB
adb sideload out/.../lineage-23.2-20260807-UNOFFICIAL-arcfox.zip
```

The earlier `--disable-verity` error ("Failed to find AVB_MAGIC at offset: 0")
was fastboot refusing to patch **our** image; pointed at the stock image it has a
header it recognises.

`restore-stock.sh` restores the whole boot chain in one command and is the
escape hatch for every subsequent attempt.

## BUILD SUCCEEDED — 2026-08-07

```
lineage-23.2-20260807-UNOFFICIAL-arcfox.zip
1,111,500,385 bytes
sha256 5adeebb0fa72ae41ed7979ef9ecebe5fe053571844947ee09888441e2f8f669f

ota-type              AB
post-build            motorola/arcfox_g/arcfox:16/W1UXS36H.72-45-10-7/...
post-sdk-level        36
post-security-patch   2026-08-01
pre-device            arcfox
signed by             SignApk (+ META-INF/com/android/otacert)
payload.bin           1,111,493,082 bytes
```

`unzip -t` clean. Streaming-capable A/B package.

### Every fix, in the order the build demanded them

Each of these was a distinct build failure. The error message usually named
something other than the real cause, so both are recorded.

| # | Error said | Real cause / fix |
|---|---|---|
| 1 | `namespace device/motorola/sm8635-common does not exist` | No `Android.bp` in either device tree. Added `soong_namespace` to both. |
| 2 | `"libarcsoft_qnnhtp" depends on undefined module "libcdsprpc"` | arcfox namespace imported `device/...` but not `vendor/motorola/sm8635-common`. Added to `namespace_imports`. |
| 3 | `"libcdfw" depends on undefined module "libgps.utils"` (x40) | Blobs held back in tier-2. Resolved by `resolve-build-blobs.sh` over 20+ rounds; ~90 blobs added. |
| 4 | `found in multiple namespaces` | Same blob in both manifests. A dependency of a common-tree blob must live in common (common cannot see device). |
| 5 | `header_version: must be set` | `BOARD_INIT_BOOT_HEADER_VERSION` missing (GKI splits init_boot out). |
| 6 | `ccache: error: Not a directory` | `~/.cache/ccache` existed as a zero-byte **file**. |
| 7 | `make: *** kernel/motorola/arcfox: No such file` | `generated_kernel_includes` needs a kernel tree. Pointed `TARGET_KERNEL_SOURCE` at LineageOS's SM8635 kernel (headers only) + `TARGET_NO_KERNEL_OVERRIDE := true`. |
| 8 | `NO KERNEL CONFIG` | Having kernel source made `kernel.mk` demand a defconfig. Fixed by the override above. |
| 9 | `unknown type name '__uint128_t'` in `asm/sigcontext.h` | A **32-bit** variant was consuming arm64 kernel headers. Device is 64-bit only (0 libs in `system/lib`): switched to `core_64_bit_only.mk`, dropped `TARGET_2ND_ARCH`. |
| 10 | `Unable to decode GID for 'vendor_qti_diag'` | Missing custom AIDs. Took `config.fs` (25 AIDs) from Motorola-Pineapple's tree; wired `TARGET_FS_CONFIG_GEN`. |
| 11 | `panic: lstat .../vendor_ramdisk` | Boot header v4 forces vendor_boot unless `PRODUCT_BUILD_VENDOR_BOOT_IMAGE := false`. |
| 12 | `KeyError: 'partition_size'` (dlkm) | Declaring a filesystem type / copy-out dir for DLKM partitions is enough to make the build assemble them. Commented all four out. |
| 13 | `ln: cannot create hard link ... .zip` | Red herring. `build_ota_package` was silently false because **`recovery_fstab` was empty**. Added `TARGET_RECOVERY_FSTAB` (stock `fstab.qcom`). |
| 14 | `Fetch '.../vendor/etc/vintf/manifest.xml': NAME_NOT_FOUND` | Stock ships SKU-selected `manifest_pineapple.xml`, no plain `manifest.xml`. Wired it as `DEVICE_MANIFEST_FILE`. |
| 15 | `Cannot override existing value 34.0 with BOARD_SEPOLICY_VERS` | Stock manifest hardcodes `<sepolicy>`; `assemble_vintf` injects its own. Stripped the block. |
| 16 | `INCOMPATIBLE` (~30 unknown HALs) | Generated `device_framework_matrix.xml` from the exact checkvintf list (16 HIDL + 10 AIDL, all `optional="true"`). |
| 17 | `depends on multiple versions of ... graphics.allocator` | Motorola camera blobs link allocator V1; A16 `libui` pulls V2. `blob_fixup().replace_needed()` over **70** blobs found by scanning for the V1 soname. |
| 18 | `'sde_drm.h' file not found` | Qualcomm display UAPI lives in the kernel-modules repo. Copied 6 display uapi headers into the kernel tree's `include/uapi`. |
| 19 | `'QServiceUtils.h' / 'utils/debug.h' / 'linux/msm_audio.h' not found` | soong was building the whole qcom-caf display+audio stack from source because prebuilt-less module names resolved to source. Added **44** matching prebuilts (50 of 105 qcom-caf module names exist in the firmware). |
| 20 | `partition is different: system(...) != vendor(prebuilt_...)` | Two HIDL *interface* libs must come from source, not prebuilt. Removed those two. |
| 21 | `check_elf_file: Unresolved symbol` (x10) | Vendor blobs referencing symbols absent from a LineageOS tree (LHDC v5 codec, `atrace_begin`). Annotated `;DISABLE_CHECKELF`. |
| 22 | `sum of sizes of ['motorola_dynamic_partitions'] >= SUPER/2` | A/B keeps **both slots** in super, so a group must be < half. Was sized at the full super; set to 13.0GB (content is 1.56GB). |
| 23 | `AssertionError: META/ab_partitions.txt is required` | `AB_OTA_UPDATER := true` is not enough; must also declare `AB_OTA_PARTITIONS`. |

### Automation written along the way

- `resolve-build-blobs.sh` — loops build → parse `undefined module` → add prebuilt
  from the firmware → regenerate. ~90 blobs resolved unattended.
- `fix-checkelf.sh` — annotates `;DISABLE_CHECKELF` for blobs failing
  `check_elf_file`.
- `build-loop.sh` — drives both classes to convergence and **stops** on anything
  else, because those two are mechanical and everything else needs a decision.

Two bugs in that automation, both worth remembering:
- `set -u` aborts silently when sourcing AOSP's `envsetup.sh`.
- `set -o pipefail` + `grep -q` on a large `echo` makes a **successful** match
  report failure, because `grep -q` exits early and `echo` dies of SIGPIPE. That
  inverted every guard and stopped the loop prematurely.

### Known compromises in this first build

Honest list; none of these were verified on hardware.

- **`;DISABLE_CHECKELF` on ~10 blobs.** peridot solves several of these properly
  with `.add_needed('libbinder_shim.so')` instead. Disabling the check makes it
  *build*; whether those binaries resolve at runtime is untested.
- **Kernel UAPI headers come from LineageOS's Xiaomi SM8635 kernel** (6.1.174),
  not Motorola's (6.1.145). Same SoC and GKI line, but not the same tree.
- **vendor_boot, vendor_dlkm, system_dlkm and dtbo are not built or flashed.**
  The stock ones are retained. This is deliberate and consistent with the
  prebuilt GKI kernel, but it means the ROM depends on stock firmware being
  present.
- **`BOARD_SUPER_PARTITION_SIZE` was never cross-checked against the device**
  (`/sys/class/block` is SELinux-denied to shell). It comes from the merged
  super.img's declared size.
- **Nothing has been flashed.** The package is well-formed and signed; it has
  never been booted.

## Gotcha: AOSP `lunch` breaks under Claude Code's shell

Symptom: `breakfast arcfox` and `lunch lineage_arcfox-bp4a-userdebug` both fail
with

```
build/make/core/product_config.mk:226: error: Cannot locate config makefile
for product "lineage_arcfox-bp4a-userdebug"
```

with the WHOLE combo string as the product name. The message is a red herring —
the product resolves fine.

Cause: Claude Code's shell snapshot defines a `grep` **shell function** that
shadows GNU grep and routes to its bundled ugrep. AOSP's `lunch` detects the
legacy combo format with:

```sh
local legacy=$(echo $1 | grep "-")
```

GNU grep treats `-` as a literal pattern; ugrep rejects it (`no PATTERN
specified`) and returns empty. `legacy` is then empty, so `lunch` takes the
*new-format* branch and assigns `product=$1`, i.e. the entire
`product-release-variant` string.

This does NOT affect a normal terminal. `/usr/bin/grep` is GNU grep 3.12 and
works correctly.

Fix inside an agent shell:

```sh
unset -f grep
source build/envsetup.sh
breakfast arcfox
```

Second, unrelated red herring found the same way: setting `BOARD_API_LEVEL` in
BoardConfigCommon.mk makes `board_config.mk:1035` error with "must not be set
manually", but `lunch`'s `check_product` swallows the message and falls back to
roomservice, producing the same misleading "Cannot locate config makefile".
When that error appears, run the resolution directly to see the real cause:

```sh
TARGET_PRODUCT=lineage_arcfox TARGET_RELEASE=bp4a TARGET_BUILD_VARIANT=userdebug \
  get_build_var TARGET_DEVICE
```

## Build environment

LineageOS **23.2** synced to `~/android/arcfox`, 171GB, `repo sync` exit 0.

`repo sync -j16` **fails with HTTP 429**. A large share of the tree fetches from
`android.googlesource.com`, which rate-limits harder than GitHub; ~54 repos died
on `android-16.0.0_r4` tag fetches. `-j4` completes. The sync is incremental, so
a 429 failure is resumable rather than fatal.

Machine: Ryzen 9 5950X, 32 threads, 125GB RAM. Disk is the constraint, not CPU:
287GB free with `out/` still to come (~150GB). The 25GB `super.img` and the
`images/*.img` under `~/android/firmware/W1UXS36H/` are deletable once the
extracted tree is trusted; the original 11GB package remains on the Windows
partition.

## Blob source: solved by Motorola's own rescue tool

The blocker was never the manifest. It was **access**. Recorded here because the
chain of dead ends is worth not repeating.

### Why the device cannot be its own blob source

Android 16, unrooted, `u:r:shell:s0`:

- `find /vendor -type f` reports **103** files in `/vendor/lib64`; `ls` reports
  **1329**. A `-type` test needs `stat()`, and `shell` is denied `stat` on most
  of the vendor partition, so `find` silently discards what it cannot see.
- `/vendor/firmware` is **denied even for listing**. No enumeration trick
  reaches it.
- A list would not be enough anyway: a build needs the blob *files*, and
  `shell` cannot read them either.
- `/data/ota_package` and `/cache/ota` are denied, so the applied OTA cannot be
  recovered from the device.
- `/dev/block/by-name/*` is root-only.

### Why fastboot does not help

```
bootloader  (is-userspace: no) : max-fetch-size -> not found
fastbootd   (is-userspace: yes): max-fetch-size -> FAILED
                                 (remote: 'fetch not supported on user builds')
```

`fastboot fetch` exists and would have been ideal, reading partitions with
SELinux out of the picture. It is gated to userdebug/eng builds. This handset is
`user` / release-keys. Dead end, but a cheap and definitive one: two reboots.

### Why the public mirrors do not help

- No `arcfox` firmware dump exists on AndroidDumps or anywhere findable.
- lolinet mirrors arcfox only to **Android 15**; this handset runs
  `W1UXS36H.72-45-10-7`.

### What actually worked

**Motorola's Rescue and Smart Assistant caches the full firmware package it
flashes, and never cleans it up.** On the Windows install used to run Software
Fix:

```
C:\ProgramData\RSA\Download\RomFiles\
  ARCFOX_G_U3UX34.56_124_1_..._CFC.xml\     (Android 14)
  ARCFOX_G_W1UXS36H.72_45_10_7_..._CFC.xml\ (Android 16 — exact match, 11GB)
```

Contents: 23 `super.img_sparsechunk.*`, `boot.img`, `init_boot.img`,
`vendor_boot.img`, `recovery.img`, `dtbo.img`, `vbmeta.img`, `vbmeta_system.img`,
`bootloader.img`, `radio.img`, `flashfile.xml`, and an `.info.txt` confirming
`motorola/arcfox_g/arcfox:16/W1UXS36H.72-45-10-7/33779-0863b:user/release-keys`.

**Generalisable lesson: the RSA cache is an unindexed firmware mirror.** If a
build is not on lolinet, anyone who flashed it with the official tool has it on
disk.

This also retires the escape-hatch warning recorded further down. A full Android
16 image for this exact build now exists locally, so the "no way back" corner
described in that section no longer applies.

### The sparsechunk ordering trap

`simg2img super.img_sparsechunk.*` is wrong. Glob order is `.0 .1 .10 .11 ... .2
.20 ...`, and the resulting `super.img` is **silently corrupt**: `lpunpack` still
emits partitions of the correct *size*, because sizes come from metadata at the
head of the image, but contents are scrambled and nothing warns you.

`sort -t. -k3 -n` does not fix it either, and this was hit for real. Motorola's
directory name contains dots (`W1UXS36H.72_45_10_7`, `CFC.xml`), so dot-delimited
field indices do not line up, every record compares equal on the chosen field,
and sort falls back to lexicographic — reproducing the exact bug it was meant to
prevent. The tell was `first=...chunk.0 last=...chunk.9` for a 23-chunk set.

`extract-firmware.sh` splits on the literal string `sparsechunk.`, sorts the
trailing integer numerically, and then **asserts the indices form a contiguous
0..N-1 run** before spending minutes on a merge. Correct run:

```
23 chunks verified contiguous: 0..22
first=super.img_sparsechunk.0 last=super.img_sparsechunk.22
super.img: 11G
```

### Partition layout recovered

`lpunpack` output from the verified image (slot A is live; slot B mostly empty):

| Partition | Size |
|---|---|
| `product_a` | 6.4 GB |
| `vendor_a` | 2.1 GB |
| `system_ext_a` | 1.07 GB |
| `system_a` | 710 MB |
| `vendor_dlkm_a` | 32.5 MB |
| `system_dlkm_a` | 11.8 MB |

All erofs, extracted with `fsck.erofs --extract` — no root, no loop device, no
mounting.

## Firmware availability and the escape-hatch asymmetry

Checked 2026-08-06 against `mirrors.lolinet.com/firmware/lenomola/2024/arcfox/official/`.

This handset is `XT2451-3`, channel **`reteu`**, customer ID `global`, shipped on
`U3UXS34.56-124-1-1` with a 2024-12-01 vendor patch. Roughly 18 months stale.

Newest full images mirrored, per channel:

| Channel | Newest build | Android | Date |
|---|---|---|---|
| `RETEU` | `V2UXS35.47-37-3-5` | 15 | 2025-10-16 |
| `RETAIL` | `V2UX35.47-37-3-28` | 15 | 2025-11-18 |

**No Android 16 (`W`-prefix) image exists on the mirror for any channel.**
Secondary reporting says Android 16 reached this device around February 2026, but
no build ID or flashable image could be verified. Treat A16 availability as
unconfirmed.

The consequence is an asymmetry worth understanding before updating anything.
Motorola burns AVB rollback-index fuses on update, permanently, so a version you
leave is a version you can never return to:

- **A14 → A15**: safe. Fuses burn and 14 is gone, but a full A15 image exists and
  can be reflashed at any time.
- **A15 → A16** (OTA only): **cornered.** 15 becomes unreachable *and* there is no
  A16 image to restore to. The only configuration with no way back.

Practical guidance: reaching Android 15 is a clear win, taking vendor from API 34
to API 35 and **exactly matching LineageOS 22.x**, which is zero Treble skew
rather than the two generations implied by A14 plus LOS 23. Going further should
wait until an A16 image is actually mirrored.

Secondary argument for targeting 22.x: zeekr's `lineage-22.2` branch is the more
complete reference. It carries `lineage.dependencies`; the `23.0` branch dropped
it and picked up Miku UI work that was later reverted.

Device state prior to updating, for the record: `ro.boot.verifiedbootstate=orange`
(unlocked), `ro.boot.veritymode=enforcing` (partitions unmodified), no root
manager and no `su` binary, slot `_a`.

**Everything in this document was captured on Android 14 and must be re-verified
after any firmware change.** Re-run `./capture-contract.sh` in all three hinge
positions. Display addresses are likely stable; the stock
`device_state_configuration.xml` is not guaranteed to be.

## Still unknown

- Whether rungs exist between 0 and 70, or between 110 and 180, that the sweep
  was too coarse or too fast to catch. Five rungs is a floor, not a proven
  complete set.
- What `hinge_posture value[2]` signals. `0.00` in every reading taken.
- `TENT` and `HALF_OPENED_QVD` have not been reproduced. TENT needs the phone
  inverted on both edges; QVD needs the hinge between 45 and 90.
- Whether the 2x telephoto is exposed as an independent camera ID
  (`contract/common/media-camera.txt` is captured but not yet analyzed).
- Whether the cover display can act as a camera viewfinder under AOSP alone.
- Which kernel tree is correct. `ro.board.platform=pineapple` is consistent with
  both candidate repos and does not settle it.

## Before publishing

`contract/common/getprop.txt` and the pulled vintf tree contain the device serial
(`<device-serial>`), and likely the IMEI and MAC addresses. Run `./scrub-check.sh`
and review the hits by hand before pushing anything public.

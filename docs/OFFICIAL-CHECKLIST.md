# arcfox against the LineageOS Device Support Requirements

First walked on 2026-09-15 against the charter
(`LineageOS/charter/device-support-requirements.md`) on build 20260915. Updated on
2026-11-23 for LineageOS 24.0 (release 24.0-20261122), including the charter's
newer `ai-coding-assistants.md`.
Status words: **met**, **gap**, **untested**, **n/a** (no such hardware or feature on stock),
**verify** (evidence suggests met but not proven).

## Hardware

| Requirement | Level | Status | Evidence / note |
|---|---|---|---|
| Media playback, in-call audio, speaker | MUST | met | 24.0: speaker→mic loopback in the regression suite, calls with audio both ways |
| Extra audio configuration (echo cancel, extra mics) | SHOULD | verify | stock audio HAL and configs shipped; not measured |
| Other outputs supported by stock (USB-C, BT; no jack) | MUST | met | audio policy lists USB_HEADSET, USB_DEVICE, A2DP; A2DP offload verified on 24.0 |
| FM radio | SHOULD | n/a | no FM on stock |
| RIL calls and data | MUST | met | 24.0, Orange SK: VoLTE and VoWiFi calls both directions, SMS both ways, LTE data |
| Emergency call with SIM | MUST | untested on 24.0 | worked on 23.2; needs a test that does not reach a real emergency service (`cmd phone emergency-number-test-mode`) |
| Emergency call without SIM | SHOULD | untested | same procedure, UI path only |
| Hardware-backed encryption; FBE default | MUST | met | `ro.crypto.state=encrypted`, type `file`; PIN-locked CE storage survives the 23.2→24.0 update |
| Wi-Fi, same MAC as stock | MUST | verify | MAC is vendor-assigned and stable across builds (regression check A40); not yet compared with stock's Settings once |
| Wi-Fi tethering | MUST | untested | softap supported; not exercised end to end |
| MTP; USB tethering | MUST | met | MTP, PTP, NCM tethering checked from the host side (regression check P10) |
| GPS | MUST | verify | fixes observed in daily use on 23.2; no outdoor fix measured on 24.0 |
| Bluetooth, same MAC as stock | MUST | met | BT MAC equals `ro.boot.btmacaddr` (regression check A41) |
| Bluetooth tethering | SHOULD | verify | PAN NAP service registered; not exercised |
| aptX / aptX HD / aptX Adaptive as on stock | SHOULD | verify | codec capabilities identical to stock; needs an aptX sink to prove |
| Cameras front and rear, all rear cameras | MUST/SHOULD | met | 24.0: 8/8 Camera2 and 3/3 API1 camera ids stream (regression check P05) |
| Video recording front and rear | MUST | verify | hardware encoder verified (screen recording); camera-app recording not re-run on 24.0 |
| Hardware codecs as stock | MUST | met | stock `media_codecs*.xml` shipped; playback/recording verified |
| Display at stock resolution and density | MUST/SHOULD | met | inner 1080x2640@420, cover 1080x1272@360 |
| HDR10 playback | SHOULD | verify | both panels report HDR types 2,3,4; playback not measured |
| NFC | MUST | met | card read on 24.0 (regression step B05) |
| Fingerprint | MUST | met | unlock on 24.0 (regression step B04) |
| IR blaster / SD card / adoptable storage | SHOULD/MUST | n/a | none on this device |
| Accelerometer, gyroscope, proximity, light | MUST | met | present and declared; adaptive brightness reads both light sensors |
| Other stock sensors | SHOULD | verify | 24.0 lists 76 sensors (68 hardware); the 23.2 walk counted differently (84). Compare the list with stock's before claiming parity |
| Proprietary accessories | SHOULD | n/a | |
| Hardware deviations documented | MUST | met (README) | thermal profile switching is the one deviation; UVC and RNDIS explained as not-on-stock |

## Software

| Requirement | Level | Status | Evidence / note |
|---|---|---|---|
| Unique codename, `lineage_arcfox.mk` | MUST | met | |
| `lineage.dependencies`, LineageOS org only | MUST | partial | 2026-11-23: arcfox → sm8635-common; sm8635-common → kernel and devicetrees (roomservice dry run clean). Open: the kernel modules are assembled from about 20 repositories by `scripts/setup-kernel-repos.sh`; an official tree needs one `android_kernel_motorola_sm8635-modules` repository, and all repositories under the LineageOS organisation |
| userdebug build | MUST | met | `ro.build.type=userdebug`; `ro.debuggable=0` is set by LineageOS itself for userdebug (`vendor/lineage/config/common.mk`) |
| GKI: source-built kernel; all feasible modules from source | MUST | met | kernel 6.1.145 and the vendor_dlkm/system_dlkm modules built from source |
| No software touch-wake without firmware support | MUST | met | the Goodix ICs run their own gesture mode (command 0xA6, gesture ID 0xCC); see docs/DT2W.md |
| No forced fast charge, no register hacks, no custom KSM | MUST | met | nothing of the kind in the tree |
| Governors and I/O schedulers from the allowed lists | MUST | met | walt/conservative/powersave/performance/schedutil; mq-deadline/kyber/bfq |
| OEM hotplug drivers only | MUST | met | |
| SELinux enforcing | MUST | met | `getenforce` = Enforcing |
| Verity disabled on system for userdebug | MUST | met | `BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3`, as the official Motorola trees; no partition is verified on the device |
| Updater app upgrades + documented recovery | MUST | partial | recovery sideload verified end to end, including 23.2→24.0 with data kept; the Updater app needs an OTA server, which only official builds have |
| FRP with GApps | SHOULD | untested | `ro.frp.pst` set; needs a wipe-and-relock style test |
| Play Integrity responses not altered | MUST | met | stock fingerprint only; no spoofing |
| 64-bit binder; no su; PIE blobs | MUST | met | |
| Extraction script reproduces blobs; global extract-utils; sources noted | MUST/SHOULD | met | 2026-11-23: every blob fix lives in `extract-files.py` (the binary patches pinned by hash); extraction from the stock dump into an empty tree, over an existing tree, and from an already fixed tree all reproduce the vendor tree release 20261122 was built from, byte for byte |
| CVE patches | MUST/SHOULD | verify | platform 2026-11-01; vendor 2026-07-01 (stock files). The kernel is still 6.1.145, as on 23.2; LineageOS's SM8650 kernel is at 6.1.177. Kernel CVE merges are not tracked yet |
| Firmware: A/B both slots on known firmware | MUST | met | install docs require W1UXS36H.72-45-10-7 on both slots; the wiki draft uses the `ab_copy_partitions` template |
| exFAT | MAY | met | kernel 6.1 mainline exfat |
| In-kernel LiveDisplay colour adjustment | SHOULD | **gap** | no LiveDisplay HAL shipped; stock has `vendor.qti.hardware.display.color-service`, so the SDM LiveDisplay backend is feasible |
| Software deviations approved and documented | MUST | **gap** | 24.0 carries 15 platform forks (frameworks/av, base, native, opt/telephony; hardware/interfaces, qcom-caf/common; DeskClock, Dialer, Launcher3, Settings, SetupWizard, CarrierConfig; system/media; vendor/lineage; vendor/qcom/opensource/interfaces). Official builds take none of them: each must be upstreamed or replaced from the device tree. The Launcher3 cover hooks have no device-tree equivalent other than the zeekr-style cutout |
| Vendor image built; no modified prebuilt vendor | MUST | met | vendor image built from extracted blobs |
| GSI verification | SHOULD | untested | |

## Quality of life

| Requirement | Level | Status | Evidence / note |
|---|---|---|---|
| Authorship of non-original commits | MUST | verify | adapted files from zeekr are annotated in comments, not commit trailers |
| Copyright headers on original files | MUST | met | 2026-11-23: SPDX headers ("The LineageOS Project", Apache-2.0) on the original build files, scripts, init files, overlays and sources of both trees, as the official sm8550-common tree does. Stock-derived files (VINTF manifest and matrix, device state configuration, generated carrier XML) carry none, as there |
| No force pushes / backups | SHOULD | met | |
| GitLab account, triage | MUST | open | process, needs a maintainer identity |
| Licensing: kernel GPLv2, Android Apache-2.0 | MUST | met | |
| Wiki page with install instructions, deviations | MUST | draft | `docs/wiki/arcfox.yml` (device entry, unmeasured specs marked VERIFY); INSTALL-RELEASE.md and GAPPS.md hold the procedure |
| No screen of death, no abnormal drain | MUST | met / watch | the cover-panel boot race is fixed (SurfaceFlinger, proven by a forced-race build); unplugged standby with AOD on: CPU awake 1.6 % of 55 min (build 4). A full-day drain measurement on 24.0 is still open |
| LineageOS Recovery default; addon packages install through it | MUST | met | recovery and MindTheGapps 17 verified end to end on 24.0, including recovery started on the stock boot chain |

## AI-assisted contributions (charter `ai-coding-assistants.md`)

| Requirement | Level | Status | Note |
|---|---|---|---|
| `Assisted-by: LLM` tag on AI-assisted commits | MUST | **gap** | this port's commits carry no such tag; contributions to LineageOS would need it |
| Concise commit messages; comments only for the non-obvious | MUST | **gap** | many commits and comments here are long by design (they record root causes); trim for submission |
| Submitter understands and can explain every change | MUST | maintainer | reviewers will ask; docs/ and the CHANGELOG hold the reasoning |
| Fully AI-generated changes reviewed by a second human | MUST | open | |

## What is left, in order

1. **Hands-on checks** on 24.0: Wi-Fi hotspot, an outdoor GPS fix, emergency dialling through the test mode (with and without SIM), camera-app video recording, Wi-Fi MAC against stock.
2. **Kernel modules in one repository**, then `lineage.dependencies` can name it; and a plan for moving all trees under the LineageOS organisation.
3. **Kernel CVE cadence**: merge 6.1 stable/ACK updates and record how.
4. **LiveDisplay**: bring up `vendor.lineage.livedisplay` against the QTI color service (the sm8475 official tree is the template).
5. **Upstream the general platform fixes** through LineageOS Gerrit (with the `Assisted-by` tag): the codec_provenance audio opt-out, the Dialer landscape insets, the SurfaceFlinger hotplug race, the cover volume-key rotation, LHDC v5 types, the qcom-caf camera gate.
6. **Decide on the cover camera block**: the Launcher3 hooks (unofficial) or the zeekr-style cutout (official).
7. **SHOULD items**: BT tethering, aptX on a real sink, HDR10 playback, FRP with GApps, GSI, a full-day battery measurement.

# arcfox against the LineageOS Device Support Requirements

Walked on 2026-09-15 against the current charter
(`LineageOS/charter/device-support-requirements.md`) on build 20260915 (build 16).
Status words: **met**, **gap**, **untested**, **n/a** (no such hardware or feature on stock),
**verify** (evidence suggests met but not proven).

## Hardware

| Requirement | Level | Status | Evidence / note |
|---|---|---|---|
| Media playback, in-call audio, speaker | MUST | met | daily use; VoLTE/VoWiFi calls verified |
| Extra audio configuration (echo cancel, extra mics) | SHOULD | verify | stock audio HAL and configs shipped; not measured |
| Other outputs supported by stock (USB-C, BT; no jack) | MUST | met | audio policy lists USB_HEADSET, USB_DEVICE, A2DP |
| FM radio | SHOULD | n/a | no FM on stock |
| RIL calls and data; emergency call with SIM | MUST | met | README table |
| Emergency call without SIM | SHOULD | untested | needs a deliberate test procedure (no live 112 call) |
| Hardware-backed encryption; FBE default | MUST | met | `ro.crypto.state=encrypted`, type `file` |
| Wi-Fi, same MAC as stock | MUST | verify | MAC b0:c2:c7:bb:49:c1 is vendor-assigned and consecutive to the BT MAC; compare with the stock sticker/Settings once |
| Wi-Fi tethering | MUST | verify | softap supported (WPA3 SAE feature reported); not exercised end to end |
| MTP; USB tethering | MUST | met | README: MTP, PTP, NCM tethering verified against host descriptors |
| GPS | MUST | met | provider present; fixes observed in daily use |
| Bluetooth, same MAC as stock | MUST | met | BT MAC equals `ro.boot.btmacaddr` |
| Bluetooth tethering | SHOULD | verify | PAN NAP service registered; not exercised |
| aptX / aptX HD / aptX Adaptive as on stock | SHOULD | verify | framework cap `sbc-aac-aptx-aptxhd-ldac` identical to stock; vendor cap includes aptxadaptiver2 as on stock; needs an aptX sink to prove |
| Cameras front and rear, all rear cameras | MUST/SHOULD | met | 3 rear + front, API1 and API2, video, README |
| Hardware codecs as stock | MUST | met | stock `media_codecs*.xml` shipped; playback/recording verified |
| Display at stock resolution and density | MUST/SHOULD | met | inner 1080x2640@420, cover 1080x1272@360 |
| HDR10 playback | SHOULD | verify | both panels report HDR types 2,3,4; playback not measured |
| NFC | MUST | met | payments verified |
| Fingerprint | MUST | met | |
| IR blaster / SD card / adoptable storage | SHOULD/MUST | n/a | none on this device |
| Accelerometer, gyroscope, proximity, light | MUST | met | 84 sensors listed, fold postures commit |
| Other stock sensors | SHOULD | verify | count matches stock's 79-84; per-sensor behaviour not audited |
| Proprietary accessories | SHOULD | n/a | |
| Hardware deviations documented | MUST | met (README) | thermal profile switching is the one deviation; UVC and RNDIS explained as not-on-stock |

## Software

| Requirement | Level | Status | Evidence / note |
|---|---|---|---|
| Unique codename, `lineage_arcfox.mk` | MUST | met | |
| `lineage.dependencies` for breakfast/roomservice, LineageOS org only | MUST | **gap** | arcfox has no `lineage.dependencies`; sm8635-common's is an empty stub. Also blobs/kernel live in personal repos, not the LineageOS org |
| userdebug build | MUST | verify | `ro.build.type=userdebug`, but `ro.debuggable=0` in system/build.prop while rooted debugging works; find what sets it and whether official 23.x userdebug reports the same |
| GKI: source-built kernel or Google GKI; all feasible modules from source | MUST | met | kernel 6.1.145 built from source via kernel.mk; vendor_dlkm and system_dlkm modules built from source (system_dlkm vermagic matches our kernel) |
| No software touch-wake without firmware support | MUST | met | Verified 2026-09-16: at screen-off the Goodix drivers send the IC the gesture-mode command 0xA6 (kmsg `enable double gesture mode cmd 0xff7f` / `Send enable gesture mode`), enable IRQ wake, and only react to the IC-reported gesture ID 0xCC; no tap timing or coordinates in the kernel. Stock ships the same modules with the same code path. Details in docs/DT2W.md |
| No forced fast charge, no register hacks, no custom KSM | MUST | met | nothing of the kind in the tree |
| Governors and I/O schedulers from the allowed lists | MUST | met | walt/conservative/powersave/performance/schedutil; mq-deadline/kyber/bfq |
| OEM hotplug drivers only | MUST | met | |
| SELinux enforcing | MUST | met | `getenforce` = Enforcing |
| Verity disabled on system for userdebug; verity on vendor | MUST/SHOULD | **gap** | AVB verification is on with the test key and dm-verity is active (`adb remount` needs overlayfs). Official Motorola trees set `BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3`; decide between that and vendor-only verity |
| Updater app upgrades + documented recovery | MUST | partial | recovery path works (sideload verified end to end); the Updater app needs an OTA server, which only exists for official builds |
| FRP with GApps | SHOULD | untested | `ro.frp.pst` set; needs a wipe-and-relock style test |
| Play Integrity responses not altered | MUST | met | stock fingerprint only; no spoofing |
| 64-bit binder; no su; PIE blobs | MUST | met | 64-bit only product; no su binary; blobs from stock |
| Extraction script reproduces blobs; global extract-utils; sources noted | MUST/SHOULD | mostly met | `extract-files.py` on tools/extract-utils; both lists name the source firmware W1UXS36H.72-45-10-7; `fix-vendor-blobs.sh` hand-edits must be folded into the script's fixups to be reproducible |
| CVE patches | MUST/SHOULD | verify | platform patch 2026-08-01, vendor 2026-07-01; kernel CVE cadence not tracked |
| Firmware assertion / A/B both slots on known firmware | MUST | met | install docs require W1UXS36H.72-45-10-7 on both slots (copy-partitions step) |
| exFAT | MAY | met | kernel 6.1 mainline exfat |
| In-kernel LiveDisplay colour adjustment | SHOULD | **gap** | no LiveDisplay HAL shipped; stock has `vendor.qti.hardware.display.color-service`, so the SDM LiveDisplay backend is feasible |
| Software deviations approved and documented; Jelly shipped | MUST | **gap** | Jelly is shipped. The Launcher3 and DeskClock patches are software deviations from other LineageOS devices and would need Director approval or upstreaming |
| Vendor image built; no modified prebuilt vendor | MUST | met | vendor image built from extracted blobs |
| GSI verification | SHOULD | untested | |

## Quality of life

| Requirement | Level | Status | Evidence / note |
|---|---|---|---|
| Authorship of non-original commits | MUST | verify | adapted files from zeekr are annotated in comments, not commit trailers |
| Copyright headers "(C) YEAR The LineageOS Project" on original files | MUST | **gap** | 17 original files in arcfox and 66 in sm8635-common carry no licence header |
| No force pushes / backups | SHOULD | met | |
| GitLab account, triage | MUST | open | process, needs a maintainer identity |
| Licensing: kernel GPLv2, Android Apache-2.0 | MUST | met | |
| Wiki page with install instructions, deviations | MUST | draft exists | INSTALL-RELEASE.md, GAPPS.md, README cover the content; needs the Wiki template |
| No screen of death, no abnormal drain | MUST | **watch** | one boot on 2026-09-15 came up without the cover panel enumerated (Motorola logo stayed); intermittent, not reproduced on reboot. Battery drain not measured over a full day |
| LineageOS Recovery default; addon packages install through it | MUST | met | recovery and MindTheGapps verified end to end |

## What we can work on, in order

1. **Copyright headers** on all original files in both trees (83 files). Mechanical, a MUST.
2. **`lineage.dependencies`** for arcfox pointing at sm8635-common, and a real plan for the kernel and vendor repositories (an official device needs them under the LineageOS organisation).
3. **Verity/AVB policy**: match the official Motorola trees (`--flags 3`) or keep vendor verity only; either way userdebug must not ship system verity.
4. **LiveDisplay**: bring up `vendor.lineage.livedisplay@2.1-service.sdm` against the QTI color service (the sm8475 official tree is the template).
5. **Reproducible blobs**: move every `fix-vendor-blobs.sh` edit into `extract-files.py` fixups so a clean extraction yields the shipped set.
6. **Verification tests** with a written procedure: Wi-Fi hotspot, BT tethering, aptX on a real sink, HDR10 playback, FRP with GApps, emergency dialling without SIM (UI path only), MAC comparison against stock.
7. **`ro.debuggable`**: one fact to establish, not a fix (touch-wake provenance is settled, see docs/DT2W.md).
8. **The cover-panel boot race**: add a boot-time log capture (and quiet `qti_glink_charger`'s 3-second printk) so the next occurrence is diagnosable; a "screen of death" class issue blocks official status.
9. **Software deviations**: upstream the DeskClock widget series and the Launcher3 drawer-scale hook; decide whether to keep the covered-corner hooks or fall back to the zeekr-style cutout for an official variant.
10. **Battery drain measurement** over a normal day, with `dumpsys batterystats` before and after.

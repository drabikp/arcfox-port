#!/bin/bash
# arcfox: assemble the Route A kernel repos from MOTOROLA's published sources.
#
# WHY THIS FILE EXISTS
# Nothing hand-placed under kernel/ may live only on disk. Everything here is
# reproducible from a URL + tag, in the same spirit as fix-vendor-blobs.sh --
# see memory `re-extract-destroys-vendor-edits`. If you hand-edit a kernel repo,
# the edit belongs in this script or in a patch series next to it, NOT loose in
# a working tree that `repo sync` will silently flatten.
#
# ROUTE A (recommended by the compliance review, 2026-08-27)
# LineageOS builds device kernels from an in-vendor triplet, e.g.
# android_device_motorola_sm8550-common/lineage.dependencies ->
#   android_kernel_motorola_sm8550{,-modules,-devicetrees}
# For arcfox the expected repos are android_kernel_motorola_sm8635{,-modules,
# -devicetrees}. None exist upstream yet; this script builds their CONTENT.
#
# WHY MOTOROLA'S TREE AND NOT LineageOS/android_kernel_xiaomi_sm8635
#  - Cross-vendor kernel sourcing is 1-in-310 across official LineageOS devices
#    (only nintendo_nx -> nvidia, which is literally NVIDIA silicon). All 17
#    android_kernel_motorola_* repos stay in-vendor.
#  - The Xiaomi base CAUSED most of our problems: 0 of 20 Motorola CONFIG symbols
#    exist in it; dwc3-msm-core.c calls Xiaomi's get_hw_version_platform()
#    unguarded at :7107/:7404; its camera-kernel lacks the DW9784 OIS driver; and
#    its pineapple_GKI.config sets CONFIG_BACKLIGHT_QCOM_SPMI_WLED, which arcfox
#    does not use and which broke the Motorola camera build.
#  - CVE currency is NOT a reason to prefer Xiaomi's: the fix is to merge Google's
#    ACK android14-6.1 forward on top of Motorola's tag, which is exactly what
#    LineageOS/android_kernel_motorola_sm8550 already does (monthly ASB merges).
#    A Motorola tag is a STARTING POINT, not a shippable frozen state.
set -euo pipefail

TAG=${TAG:-MMI-W1UXS36H.72-45-4-1}      # arcfox build train (see HANDOFF-NEXT 0.20)
GH=https://github.com/MotorolaMobilityLLC
DEST=${DEST:-$(cd "$(dirname "$0")/../.." && pwd)/kernel/motorola}   # <ANDROID_TOP>/kernel/motorola
JOBS=${JOBS:-4}

log(){ printf '  %s\n' "$*"; }
clone(){ # clone <repo> <path> [tag]
  local repo=$1 path=$2 tag=${3:-$TAG}
  if [ -d "$DEST/$path/.git" ]; then log "skip  $path (exists)"; return 0; fi
  mkdir -p "$(dirname "$DEST/$path")"
  if git clone --depth 1 -b "$tag" -q "$GH/$repo.git" "$DEST/$path" 2>/dev/null; then
    log "ok    $path  <- $repo @ $tag"
  else
    log "FAIL  $path  <- $repo @ $tag"; return 1
  fi
}

# ---- 1. the kernel itself -------------------------------------------------
# 6.1.128. Merge ACK android14-6.1 forward AFTER this, for CVE currency.
clone kernel-msm sm8635 || true

# ---- 2. devicetrees -------------------------------------------------------
# We currently ship prebuilt dtb/dtbo. That is permitted (android_device_motorola_manaus
# @ lineage-23.2 ships a committed dtbo.img) but building them is preferred.
clone kernel-devicetree sm8635-devicetrees || true

# ---- 3. modules -----------------------------------------------------------
# MUST be a SIBLING of the kernel named sm8635-modules: the techpack Kbuilds do
#   include $(MMRM_ROOT)/config/...   where MMRM_ROOT=$(KERNEL_SRC)/$(M)
# and audio-kernel HARDCODES
#   KBUILD_EXTRA_SYMBOLS=$(OUT_DIR)/../sm8635-modules/.../Module.symvers
M=sm8635-modules
for e in \
  "vendor-qcom-opensource-mmrm-driver:qcom/opensource/mmrm-driver" \
  "vendor-qcom-opensource-mm-drivers:qcom/opensource/mm-drivers" \
  "vendor-qcom-opensource-securemsm-kernel:qcom/opensource/securemsm-kernel" \
  "vendor-qcom-opensource-audio-kernel:qcom/opensource/audio-kernel" \
  "vendor-qcom-opensource-synx-kernel:qcom/opensource/synx-kernel" \
  "vendor-qcom-opensource-camera-kernel:qcom/opensource/camera-kernel" \
  "vendor-qcom-opensource-dsp-kernel:qcom/opensource/dsp-kernel" \
  "vendor-qcom-opensource-eva-kernel:qcom/opensource/eva-kernel" \
  "vendor-qcom-opensource-video-driver:qcom/opensource/video-driver" \
  "vendor-qcom-opensource-graphics-kernel:qcom/opensource/graphics-kernel" \
  "vendor-qcom-opensource-bt-kernel:qcom/opensource/bt-kernel" \
  "vendor-qcom-opensource-spu-kernel:qcom/opensource/spu-kernel" \
  "vendor-qcom-opensource-mm-sys-kernel:qcom/opensource/mm-sys-kernel" \
  "vendor-qcom-opensource-datarmnet:qcom/opensource/datarmnet" \
  "vendor-qcom-opensource-datarmnet-ext:qcom/opensource/datarmnet-ext" \
  "vendor-qcom-opensource-wlan-platform:qcom/opensource/wlan/platform" \
  "vendor-qcom-opensource-wlan-qcacld-3.0:qcom/opensource/wlan/qcacld-3.0" \
  "vendor-qcom-opensource-wlan-qca-wifi-host-cmn:qcom/opensource/wlan/qca-wifi-host-cmn" \
  "vendor-qcom-opensource-wlan-fw-api:qcom/opensource/wlan/fw-api" \
  "kernel-msm-techpack-dataipa:qcom/opensource/dataipa" \
  "vendor-nxp-opensource-driver:nxp/opensource/driver" \
  "motorola-kernel-modules:motorola" \
; do clone "${e%%:*}" "$M/${e##*:}" || true; done

# ---- 3b. post-clone fixups ------------------------------------------------
# kiwi_v2 variant: CLO packaging ships qcacld-3.0 with SELF-SYMLINK variant dirs
# (.kiwi_v2 -> .); Motorola's repo omits them. arcfox needs the kiwi_v2 variant
# (CONFIG_MOT_CNSS_KIWI_V2), and the build derives the profile from the M= dir
# basename, so recreate the symlink:
[ -e "$DEST/$M/qcom/opensource/wlan/qcacld-3.0/.kiwi_v2" ] ||   ln -sfn . "$DEST/$M/qcom/opensource/wlan/qcacld-3.0/.kiwi_v2"
# securemsm: trace_smcinvoke.h defaults SMCINVOKE_TRACE_INCLUDE_PATH to the
# Android-tree layout (../../../../vendor/qcom/...). In this sibling layout pass
#   KCFLAGS+=-DSMCINVOKE_TRACE_INCLUDE_PATH=smcinvoke
# (SSG_MODULE_ROOT is already on LINUXINCLUDE, so the bare subdir resolves).

# camera-kernel: published Kbuild omits the OIS fw objects stock contains
CPATCH="$(dirname "$0")/patches/camera-kernel/Kbuild-add-ois-fw-objs.patch"
if [ -f "$CPATCH" ] && ! /usr/bin/grep -q cam_ois_dw9784 "$DEST/$M/qcom/opensource/camera-kernel/Kbuild" 2>/dev/null; then
  patch -s -p1 -d "$DEST/$M/qcom/opensource/camera-kernel" < "$CPATCH" && log "patched camera-kernel Kbuild (+dw9784 +sem1217s)"
fi

# ---- 4. display-drivers: NOT from Motorola, plus local patches ------------
# Motorola publishes NO display-drivers for this train, so we take LineageOS's
# (Xiaomi's) and patch it. Provenance + patches live in patches/display-drivers/
# so this is reproducible -- do NOT hand-edit the tree and leave it there.
#   base: LineageOS/android_kernel_xiaomi_sm8635-modules @ lineage-23.2
#         qcom/opensource/display-drivers
#   patch 1 (dsi_drm.c + dsi_display.h): add the Motorola panel sysfs contract
#           (panelName/panelSupplier/panelCellId/panelBLExponent/panelVer/
#            panelId/panelDC/panelPcdCheck/panelEnableSfBrightZone) on the
#           PRIMARY connector only. Captured from the running stock device;
#           consumers are init.mmi.touch.sh, displaypanel.default.so,
#           hardware_revisions.sh, mot_tcmd, motorola.hardware.sensorext-service
#           and als_comp_config*.xml. panelDeclare is deliberately NOT created --
#           it does not exist on stock either.
#   patch 2 (mi_dsi_panel.c): stub mi_display_pwrkey_callback_set(), which only
#           exists as a Xiaomi patch to drivers/input/misc/pm8941-pwrkey.c.
#   patch 3 (sde_dsc_helper.{c,h} + dsi_panel.c): Novatek DSC rate-control.
#           arcfox's panel node sets qcom,mdss-dsc-novateck-ic on every timing;
#           Motorola's stock driver reads it and routes DSC setup through
#           sde_dsc_populate_dsc_config_nt(), which uses a Novatek range_max_qp
#           table. Xiaomi's tree never reads that property, so we programmed
#           Qualcomm's generic table instead. The two differ in exactly one cell,
#           [DSC_V11_10BPC_8BPP][0] = 4 vs 8 -- and that is the row this panel
#           resolves to (DSC v1.1, 10 bpc, 8 bpp, 444, no scr-version). Table and
#           control flow recovered from the stock vendor_dlkm msm_drm.ko
#           (sde_dsc_rc_range_max_qp_nt @ .rodata+0xb1c6).
#   patch 4 (dsi_panel.c + dsi_panel.h): panel VIO/VCI/VDD enable GPIOs.
#           Motorola drives the panel load switches as plain TLMM GPIOs in
#           ADDITION to qcom,panel-supply-entries; Xiaomi's tree parses none of
#           them, so the kernel never touched them and they simply kept whatever
#           level the bootloader left. arcfox declares vio=GPIO125 and
#           vdd=GPIO126 on BOTH panels (no *-vci-enable-gpio exists anywhere in
#           the DTB). Sequencing reproduced from the stock msm_drm.ko:
#             on : vio=1, vdd=1, regulators on, udelay(5000), vci=1
#             off: vci=0, regulators off, vdd=0, udelay(5000), vio=0
#           (dsi_panel_power_on/off are inlined into dsi_panel_pre_prepare
#            @ .text+0x153de8 and dsi_panel_post_unprepare @ .text+0x155e0c.)
#           Stock uses gpio_set_value() == gpiod_set_raw_value(): RAW, so the DT
#           active-low flag is ignored -- preserved here. Every access is
#           gpio_is_valid()-guarded, so a panel without these properties keeps
#           exactly today's behaviour.
XI=${XI:-$DEST/sm8635-modules.xiaomi-base}   # synced by local_manifest/arcfox.xml
DD=$DEST/$M/qcom/opensource/display-drivers
if [ ! -d "$DD" ] && [ -d "$XI/qcom/opensource/display-drivers" ]; then
  cp -a "$XI/qcom/opensource/display-drivers" "$DD"
  for f in msm/dsi/dsi_drm.c msm/dsi/dsi_display.h msm/mi_disp/mi_dsi_panel.c \
           msm/sde_dsc_helper.c msm/sde_dsc_helper.h \
           msm/dsi/dsi_panel.c msm/dsi/dsi_panel.h; do
    pf="$(dirname "$0")/patches/display-drivers/$(echo "$f" | tr '/' '_').patch"
    [ -f "$pf" ] && patch -s -p0 -d "$DD" "$f" < "$pf" && log "patched $f"
  done
  log "ok    $M/qcom/opensource/display-drivers  <- LineageOS xiaomi + local patches"
else
  log "skip  display-drivers"
fi

# ---- 5. WLAN: LineageOS/Xiaomi subtree + the bootarg-MAC patch -------------
# Motorola's qcacld-3.0 does not build (16 documented attempts, HANDOFF 0.28).
# Xiaomi's does, but its qcacld calls cnss_register_driver_async_data_cb, which
# only Xiaomi's cnss2 exports (platform/cnss2/main.c:2692) -- so the WHOLE wlan
# subtree must move together; a hybrid dies at modpost.
# Then patch back Motorola's factory-MAC provisioning: arcfox gets its per-unit
# MAC from the bootloader (wifimacaddr= in /chosen bootargs), which only
# Motorola's hdd_update_mac_config parses. Without the patch the driver falls
# back to the board-data placeholder 00:03:7F:12:34:56 -- the same on EVERY unit.
XI=${XI:-$DEST/sm8635-modules.xiaomi-base}   # synced by local_manifest/arcfox.xml
WL=$DEST/$M/qcom/opensource/wlan
if [ ! -d "$WL" ] && [ -d "$XI/qcom/opensource/wlan" ]; then
  cp -a "$XI/qcom/opensource/wlan" "$WL"
  pf="$(dirname "$0")/patches/wlan/qcacld-bootarg-mac.patch"
  [ -f "$pf" ] && patch -s -p0 -d "$WL/qcacld-3.0/core/hdd/src" wlan_hdd_cfg.c < "$pf" \
    && log "patched qcacld: bootarg factory MAC"
  log "ok    $M/qcom/opensource/wlan  <- LineageOS xiaomi + bootarg-MAC patch"
else
  log "skip  wlan"
fi

cat <<'WARN'

  ---------------------------------------------------------------------------
  KNOWN GAPS -- do not assume these resolve themselves
  ---------------------------------------------------------------------------
  * display-drivers: MOTOROLA HAS NOT PUBLISHED IT FOR THIS TRAIN --
    but this is NO LONGER A BLOCKER. See section 4 above; it is patched.
      vendor-qcom-opensource-display-drivers newest tag = MMI-T1TR33.43-20-56
      kernel-msm-techpack-display            newest tag = S1SUS32.73-13-4-3
    ⚠️ CORRECTION to an earlier claim in this file and in HANDOFF-NEXT 0.24:
    "NT37705A is arcfox's actual panel" was WRONG. arcfox's live panel is
    csot_nt37707_667_1080x2640_dsc_cmd_v3 (read from the device). The shipped
    msm_drm.ko has ZERO references to nt37707 and four to nt37705, so
    mot_nt37705A_display_read_cellid is DEAD CODE for a different Motorola
    device. It was inferred to be arcfox's panel purely from symbol presence.
    The panel needs NO Motorola driver code: all 297 properties in
    dsi-panel-mot-csot-nt37707-667-1080x2640-dsc-cmd-common_v3.dtsi are standard
    qcom,* (zero mot,*/moto,*), so the generic dsi_panel parser drives it, and
    Motorola DOES publish that dtsi (kernel-display-devicetree @ our tag).
    Only the sysfs contract was missing -- now reimplemented.

  * touch-drivers / nxp: no Motorola vendor-qcom-* repo. arcfox's touch stack is
    Motorola's own (touchscreen_mmi, goodix_*_mmi, focaltech_v3_5) and lives in
    motorola-kernel-modules, cloned above. Xiaomi's touch-drivers techpack fails
    to build here on xiaomi/xiaomi_touch.h -- that failure is CORRECT, we do not
    want it.

  * ps5169: NOT a module repo at all -- it is drivers/usb/redriver/ps5169.c in
    the CORE kernel, present only in Motorola's kernel-msm. Route A gets it for
    free; the Xiaomi base never could.

  NEXT STEPS
  1. TARGET_PRODUCT must be rtwo. config/rtwo.mk is the ONLY definition site of
     CONFIG_MOT_SENSOR_PRE_POWERUP, and the stock camera.ko carries 6 MotPreAct
     strings. camera-kernel's Kbuild only includes a product .mk for
     {hiphi*, li, oneli, eqs, rtwo}; LineageOS sets lineage_arcfox, so it is
     never included and HAL opcodes 0x251-0x253 would go unhandled.
  2. Module SIGNING: CONFIG_MODULE_SIG_PROTECT=y and 25 of 60 system_dlkm export
     protected symbols. A self-built kernel can NEVER mix with the PREBUILT
     system_dlkm (signed with Google's key baked into the prebuilt Image), and
     the build must run modules_install / sign-file or those 25 fail -EACCES.
  3. Merge ACK android14-6.1 forward onto the kernel for CVE currency.
WARN

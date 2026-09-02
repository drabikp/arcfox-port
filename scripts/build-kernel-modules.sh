#!/bin/bash
# arcfox: build the LineageOS sm8635 kernel + its modules FROM SOURCE.
#
# WHY: the 287 prebuilt vendor_dlkm .ko files are the last official-support
# blocker (HANDOFF-NEXT.md 0.20). Zero of ~160 official LineageOS devices ship
# .ko prebuilts. Reference device = peridot (POCO F6, same SM8635/pineapple),
# which drives this through LineageOS kernel.mk classic kbuild -- NOT bazel.
#
# PROVEN 2026-08-27:
#   - kernel builds: Image 35,576,320 B, 346 modules, release 6.1.174-gfb4bafa4289e
#   - 172 of the 287 shipped vendor_dlkm come from the in-tree build
#   - msm-mmrm.ko (QTI techpack) built out-of-tree is CRC-IDENTICAL (42/42 symbols)
#     to the shipped prebuilt
#   - a from-source module LOADED on the running 6.1.145 GKI (insmod rc=0)
#
# THREE NON-OBVIOUS THINGS THIS SCRIPT ENCODES:
#  1. HOSTCFLAGS must point at prebuilts/kernel-build-tools BoringSSL.
#     certs/extract-cert.c declares key_pass under #ifdef USE_PKCS11_ENGINE but
#     USES it under #ifndef OPENSSL_IS_BORINGSSL -> with host OpenSSL 3.x it is
#     an "undeclared identifier" compile error. BoringSSL compiles that branch out.
#  2. -Wno-error: build.config.constants wants CLANG_VERSION=r487747c (clang 17);
#     the tree ships clang 21, which is stricter. CRCs come from genksyms type
#     signatures, NOT codegen, so the newer clang does not perturb the module ABI.
#  3. External (techpack) modules must be invoked through THEIR OWN Makefile with
#     an M= path RELATIVE TO KERNEL_SRC. Their Kbuild does
#     `include $(MMRM_ROOT)/config/...` where MMRM_ROOT=$(KERNEL_SRC)/$(M);
#     an absolute M concatenates into garbage. kernel.mk:542 computes this relpath
#     with python3 os.path.relpath for exactly this reason.
#
# ⚠️ CONFIG_MI_HARDWARE_ID=m IS REQUIRED BUT IS A XIAOMI DRIVER.
#    LineageOS's sm8635 kernel is Xiaomi-patched: drivers/usb/dwc3/dwc3-msm-core.c
#    calls get_hw_version_platform() UNGUARDED at lines 7107 and 7404 to force USB
#    gen1 on Xiaomi projects N3/N18/O81/O82. Without the config, modpost fails with
#    "get_hw_version_platform undefined". arcfox never matches those IDs, so the
#    quirk is inert -- but the proper arcfox fix is to GUARD those two call sites
#    rather than ship Xiaomi's hwid driver. Only 1 core file is affected.
set -euo pipefail

TREE=${TREE:-$HOME/android/arcfox}
K=$TREE/kernel/motorola/sm8635                 # MotorolaMobilityLLC/kernel-msm @ MMI-W1UXS36H tag, branch arcfox-ack-merge
EXT=${EXT:-$TREE/kernel/motorola/sm8635-modules}   # MUST be a sibling of $K
OUT=${OUT:-$PWD/kout}
# clang-r547379 (clang 20), NOT r574158 (clang 21): the Motorola 6.1.1xx tree
# predates clang-21-only warnings (-Wdefault-const-init-field-unsafe in
# list.h/mount.h/fs.h). See HANDOFF-NEXT 0.25.
C=$TREE/prebuilts/clang/host/linux-x86/clang-r547379/bin
KBT=$TREE/prebuilts/kernel-build-tools/linux-x86
export PATH=$C:$TREE/prebuilts/build-tools/linux-x86/bin:$PATH

# NOTE: no -I$KBT/include any more -- host OpenSSL is required for sha256
# signing, and the merged tree compiles extract-cert against it cleanly.
HOSTFLAGS=(HOSTCFLAGS="-Wno-error -Wno-incompatible-pointer-types-discards-qualifiers"
           HOSTLDFLAGS="-L$KBT/lib64 -Wl,-rpath,$KBT/lib64")
MK=(make -C "$K" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 "${HOSTFLAGS[@]}")

case "${1:-all}" in
  config)
    "${MK[@]}" gki_defconfig
    "$K"/scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
        "$K"/arch/arm64/configs/vendor/pineapple_GKI.config
    echo "CONFIG_MI_HARDWARE_ID=m" >> "$OUT/.config"   # see warning above
    "${MK[@]}" olddefconfig
    ;;
  kernel)  "${MK[@]}" -j"$(nproc)" KCFLAGS="-Wno-error=format" Image modules ;;
  install) # sign + strip + install. PROVEN 2026-08-28: 332/332 signed sha256,
    # signature CMS-verifies against the cert embedded in OUR Image (and fails
    # against Google's shipped modules -- correct key isolation).
    # Config: merge patches/kernel-config/arcfox-signing.config first (config goal
    # does NOT include it yet -- deliberate until flash time).
    # ⚠️ signing happens at modules_install, NOT at `modules`.
    # ⚠️ HOST OpenSSL, not the BoringSSL in prebuilts/kernel-build-tools:
    #    BoringSSL's sign-file refuses SHA256. The r34 merge fixed
    #    certs/extract-cert.c (key_pass now unconditional), so the BoringSSL
    #    HOSTCFLAGS crutch is no longer needed AT ALL on the merged tree.
    # ⚠️ if scripts/sign-file predates a HOSTCFLAGS change, delete it AND its
    #    .sign-file.cmd -- a stale rpath silently keeps BoringSSL.
    # ⚠️ run install SERIALIZED after Image+modules (a -j32 combined goal races
    #    install jobs against the sign-file relink -> Error 127).
    # The key (certs/signing_key.pem in O=) is generated ONCE and reused; never
    # mrproper or switch O= between building Image and installing modules.
    "${MK[@]}" KCFLAGS="-Wno-error=format" \
      modules_install INSTALL_MOD_PATH="${2:-$OUT-install}" INSTALL_MOD_STRIP=1 ;;
  ext)     # $2 = path under sm8635-modules, e.g. qcom/opensource/mmrm-driver
    # M MUST be ../sm8635-modules/<path>: the techpack Kbuilds do
    #   include $(MMRM_ROOT)/config/... where MMRM_ROOT=$(KERNEL_SRC)/$(M),
    # and audio-kernel hardcodes
    #   KBUILD_EXTRA_SYMBOLS=$(OUT_DIR)/../sm8635-modules/.../Module.symvers
    # so the repo must be a SIBLING of the kernel named sm8635-modules, and
    # objects must land at $(OUT_DIR)/../sm8635-modules/.
    # Build in peridot's TARGET_KERNEL_EXT_MODULES order -- it is dependency order.
    # Some dirs have no `modules` target; fall back to `all` (this is how the
    # wlan variants build: qcacld-3.0/.kiwi_v2 is a SYMLINK to qcacld-3.0 and the
    # variant is chosen by the path name -- arcfox needs .kiwi_v2, not peridot's
    # .qca6750, matching CONFIG_MOT_CNSS_KIWI_V2).
    for goal in modules all; do
      make -C "$EXT/$2" M="../sm8635-modules/$2" KERNEL_SRC="$K" O="$OUT" OUT_DIR="$OUT" \
           ARCH=arm64 LLVM=1 LLVM_IAS=1 TARGET_BOARD_PLATFORM=pineapple \
           "${HOSTFLAGS[@]}" $goal && break
    done
    ;;
  # ---- PER-MODULE OVERRIDES (Route A, Motorola tag; discovered 2026-08-28) ----
  # Prereq symlinks (created by setup-kernel-repos.sh): CLO trace headers and
  # config paths default to the Android-tree layout, resolved via
  # srctree/include/../../../../vendor/qcom/opensource/<repo>. We provide:
  #   $TREE/vendor/qcom/opensource/{dsp-kernel,mm-sys-kernel,dataipa,datarmnet,
  #     securemsm-kernel} -> kernel/motorola/sm8635-modules/qcom/opensource/...
  #   $TREE/kernel/vendor -> ../vendor          (dataipa uses $K/../../vendor)
  # Then:
  #   securemsm-kernel : KCFLAGS+=-DSMCINVOKE_TRACE_INCLUDE_PATH=smcinvoke
  #   dsp-kernel       : works via symlink (fastrpc_trace.h default path)
  #   eva-kernel       : KCFLAGS+=-I<dsp-kernel>/include/linux -I<...>/include/uapi
  #                      (eva does #include <fastrpc.h> from dsp-kernel)
  #   video-driver     : VIDEO_ROOT=<abs module dir>  (its Makefile writes
  #                      $(VIDEO_ROOT)/driver/vidc/inc/video_generated_h)
  #   camera-kernel    : TARGET_PRODUCT=rtwo  -- REQUIRED. Kbuild:65 includes
  #                      config/rtwo.mk only for rtwo; without it the MOT OIS
  #                      sources are half-gated and modpost fails on
  #                      dw9784_fw_update/sem1217s_fw_update undefined.
  #   graphics-kernel  : KBUILD_EXTRA_SYMBOLS="<hw_fence>/Module.symvers
  #                      <sync_fence>/Module.symvers" (no EXTRA_SYMBOLS in its
  #                      Makefile at this tag)
  #   datarmnet + ext  : KCFLAGS+= -DRMNET_TRACE_INCLUDE_PATH=<abs datarmnet/core>
  #                      -DCONFIG_RMNET_LA_PLATFORM   <- Kbuild defines the
  #                      UNPREFIXED -DRMNET_LA_PLATFORM but rmnet_ctl.h checks
  #                      the CONFIG_-prefixed macro (Motorola-tag bug; the
  #                      mismatch makes the header emit stub inlines that then
  #                      collide with the real definitions)
  #                      -I<datarmnet-ext/mem> -I<dataipa>/drivers/platform/msm/include{,/uapi}
  #                      (rmnet_mem.h and linux/ipa.h+msm_ipa.h are sibling headers)
  #   qcacld-3.0       : variant dir .kiwi_v2 is a SELF-SYMLINK we create; that
  #                      breaks WLAN_PLATFORM_INC ?= $(WLAN_ROOT)/../platform/inc
  #                      -- pass WLAN_PLATFORM_INC=<abs wlan/platform/inc>, AND
  #                      CONFIG_CNSS_OUT_OF_TREE=y + KCFLAGS+=-DCONFIG_CNSS_OUT_OF_TREE=1
  #                      (pld_common.h picks #include "cnss2.h" vs <net/cnss2.h>
  #                      on that macro; NO kernel ships net/cnss2.h)
  #   camera-kernel    : ALSO needs patches/camera-kernel/Kbuild-add-ois-fw-objs.patch
  #                      -- the published Kbuild omits cam_ois_dw9784.o and
  #                      cam_ois_sem1217s.o although cam_ois_core.o calls their
  #                      fw_update functions (published-source defect; stock
  #                      camera.ko contains both)
  #   sx937x_multi     : build motorola/drivers/sensors FIRST (it needs
  #                      ../../sensors/Module.symvers = sensors_class.ko)
  # DEPENDENCY ORDER matters: securemsm before display; mm-drivers before
  # graphics; datarmnet/core before datarmnet-ext/*; dsp before eva.
  #   chargers         : bm_adsp_ulog FIRST -> qti_glink_charger -> the rest
  #                      (sc760x/qpnp_adaptive/mmi_lpd need -DUSE_MMI_CHARGER,
  #                      -I mmi_charger dir, + chain symvers incl mmi_relay)
  #   touchscreen_mmi  : symvers from display + mmi_relay + sensors + mmi_info;
  #                      -DCONFIG_DRM_PANEL_EVENT_NOTIFICATIONS=1
  #   panel drivers    : goodix_* need touchscreen_mmi symvers + the TS set;
  #                      focaltech ALSO needs CONFIG_INPUT_TOUCHSCREEN_MMI in
  #                      BOTH planes (make var for the obj list, -D for cpp) --
  #                      its legacy fb-notifier path cannot compile here and
  #                      stock proves it compiled out (0 notifier imports)
  #   bt-kernel        : -I securemsm-kernel/include (the PARENT, so
  #                      <linux/smcinvoke_object.h> resolves) + securemsm
  #                      symvers + CONFIG_MSM_BT_POWER=m CONFIG_BTFM_SLIM=m
  #                      CONFIG_BT_HW_SECURE_DISABLE=y BT_KERNEL_ROOT=<abs>
  #   moto_sched       : -I module root (msched_common.h) + -I kernel srctree
  #   moto_swap        : DO NOT BUILD -- ship prebuilt (kernel-side hybridswap
  #                      memcg fields unpublished; stock parity impossible)
  #   qcacld kiwi_v2   : full CLO var set REQUIRED: WLAN_PROFILE=kiwi_v2 (this,
  #                      not only CONFIG_QCA_CLD_WLAN_PROFILE, drives features)
  #                      WLAN_FW_API=<abs fw-api> WLAN_COMMON_INC=<abs cmn>
  #                      WLAN_PLATFORM_INC=<abs platform/inc>
  #                      DYNAMIC_SINGLE_CHIP=kiwi_v2 MODNAME=wlan DEVNAME=wlan
  #                      BOARD_PLATFORM=pineapple CONFIG_CNSS_OUT_OF_TREE=y
  #                      KCFLAGS+= -DCONFIG_CNSS_OUT_OF_TREE=1
  #                        -DCFG80211_SINGLE_NETDEV_MULTI_LINK_SUPPORT
  #                        -DCFG80211_RU_PUNCT_NOTIFY (ACK 6.1 has the 4-arg
  #                        MLO API but not the CLO marker macros)
  #                        -I dataipa include{,/uapi} -include linux/qcom-iommu-util.h
  # ⚠️ REGRESSION TRAP: command-line KBUILD_EXTRA_SYMBOLS OVERRIDES a module
  #    Makefile's own chaining -- check the Makefile before passing it.
  # ⚠️ audio-kernel can report success with ZERO .ko -- always verify artifact
  #    count, never the exit status alone.
  moto)    # $2 = path under sm8635-modules, e.g. motorola/drivers/moto_swap
    # KCFLAGS (NOT KBUILD_EXTRA_CFLAGS, which kbuild ignores) relaxes clang-21.
    # HAVE_KERNEL_6_1=1: moto_swap/Kbuild picks its zram variant by testing for
    #   $(ANDROID_BUILD_TOP)/kernel_platform/gki/kernel/6.1; unset standalone, it
    #   silently falls through to zram-5.10 and dies on linux/genhd.h (gone in 5.18+).
    # ⚠️ enumerate module dirs with `grep -E "^modules[ :]"` -- moto_binder and
    #   moto_sched use a multi-target rule `modules modules_install clean:` and a
    #   `^modules:` grep silently SKIPS them.
    make -C "$EXT/$2" M="../sm8635-modules/$2" KERNEL_SRC="$K" O="$OUT" OUT_DIR="$OUT" \
         ARCH=arm64 LLVM=1 LLVM_IAS=1 TARGET_BOARD_PLATFORM=pineapple HAVE_KERNEL_6_1=1 \
         KCFLAGS="-Wno-error -I$EXT/motorola/include" "${HOSTFLAGS[@]}" modules
    ;;
  all) "$0" config && "$0" kernel ;;
  *) echo "usage: $0 {config|kernel|ext <subdir>|all}"; exit 1 ;;
esac

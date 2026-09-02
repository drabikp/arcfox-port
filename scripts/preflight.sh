#!/usr/bin/env bash
# preflight.sh — check a machine can actually build LineageOS 23.x for arcfox.
#
# Run this on the BUILD machine (the 16-core / 128GB desktop), not the laptop.
# Read-only: it inspects and reports, and changes nothing.
#
#   ./preflight.sh [build-dir]     # default: ~/android/arcfox
#
# Exit 0 if everything passes, 1 if any BLOCK is reported.

set -uo pipefail

BUILD_DIR="${1:-$HOME/android/arcfox}"
FAILED=0

pass() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }
block() { printf '  \033[31mBLOCK\033[0m %s\n' "$1"; FAILED=1; }

echo "=== LineageOS 23.x / arcfox build preflight ==="
echo "target build dir: $BUILD_DIR"
echo

# --- Hardware ---------------------------------------------------------------
echo "Hardware"
CORES=$(nproc)
RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)

[ "$CORES" -ge 8 ] && pass "$CORES cores" || warn "$CORES cores, builds will be slow"

# AOSP linking is the memory-hungry phase. Rule of thumb is ~1.5GB per parallel
# job; below 32GB you tune -j downward or thrash.
if [ "$RAM_GB" -ge 32 ]; then
  pass "${RAM_GB}GB RAM"
elif [ "$RAM_GB" -ge 16 ]; then
  warn "${RAM_GB}GB RAM, cap parallelism (try -j$((RAM_GB * 2 / 3)) ) or you will OOM at link time"
else
  block "${RAM_GB}GB RAM, too little for a LineageOS 23 build"
fi

# --- Disk -------------------------------------------------------------------
echo
echo "Disk"
CHECK_DIR="$BUILD_DIR"
while [ ! -d "$CHECK_DIR" ] && [ "$CHECK_DIR" != "/" ]; do
  CHECK_DIR=$(dirname "$CHECK_DIR")
done

AVAIL_GB=$(df -BG --output=avail "$CHECK_DIR" | tail -1 | tr -dc '0-9')
FSTYPE=$(df -T "$CHECK_DIR" | tail -1 | awk '{print $2}')

# ~200GB source + ~150GB out/ for one target, plus ccache and room to breathe.
if [ "$AVAIL_GB" -ge 500 ]; then
  pass "${AVAIL_GB}GB free on $CHECK_DIR"
elif [ "$AVAIL_GB" -ge 400 ]; then
  warn "${AVAIL_GB}GB free, workable for one target but tight with ccache"
else
  block "${AVAIL_GB}GB free, need ~400GB minimum (source ~200GB + out/ ~150GB)"
fi

case "$FSTYPE" in
  ext4|btrfs|xfs|f2fs) pass "filesystem $FSTYPE" ;;
  ntfs|fuseblk|exfat|vfat) block "filesystem $FSTYPE cannot host an AOSP tree (no symlinks / wrong semantics)" ;;
  *) warn "filesystem $FSTYPE, unverified for AOSP" ;;
esac

# AOSP requires case sensitivity. A tree on a case-insensitive mount fails in
# confusing ways, often deep into a build.
TMPD=$(mktemp -d "$CHECK_DIR/.casetest.XXXXXX" 2>/dev/null)
if [ -n "$TMPD" ] && [ -d "$TMPD" ]; then
  touch "$TMPD/casetest"
  if [ -e "$TMPD/CASETEST" ]; then
    block "filesystem is case-INSENSITIVE, AOSP will not build here"
  else
    pass "filesystem is case-sensitive"
  fi
  rm -rf "$TMPD"
else
  warn "could not test case sensitivity (no write access to $CHECK_DIR)"
fi

# --- Tools ------------------------------------------------------------------
echo
echo "Tools"
# LineageOS 23 uses the JDK bundled in prebuilts/, so system java is not
# required for the build itself, only for odd helper scripts.
for t in git curl python3 rsync unzip zip openssl lz4 zstd bc; do
  command -v "$t" >/dev/null 2>&1 && pass "$t" || block "$t missing"
done

command -v repo >/dev/null 2>&1 && pass "repo" \
  || block "repo missing (Arch: sudo pacman -S repo)"
command -v git-lfs >/dev/null 2>&1 && pass "git-lfs" \
  || block "git-lfs missing, LineageOS manifests use LFS (Arch: sudo pacman -S git-lfs)"
command -v ccache >/dev/null 2>&1 && pass "ccache" \
  || warn "ccache missing, rebuilds will be far slower (Arch: sudo pacman -S ccache)"

# --- Kernel / ulimits -------------------------------------------------------
echo
echo "Limits"
NOFILE=$(ulimit -n)
if [ "$NOFILE" -ge 32768 ]; then
  pass "open file limit $NOFILE"
elif [ "$NOFILE" -ge 8192 ]; then
  warn "open file limit $NOFILE, raise toward 32768 if ninja complains"
else
  block "open file limit $NOFILE, too low; AOSP wants >=8192 (see /etc/security/limits.conf)"
fi

WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)
[ "$WATCHES" -ge 524288 ] && pass "inotify watches $WATCHES" \
  || warn "inotify watches $WATCHES, raise to 524288 for repo sync on a tree this size"

# --- Git identity -----------------------------------------------------------
echo
echo "Git"
GN=$(git config --global user.name || true)
GE=$(git config --global user.email || true)
if [ -n "$GN" ] && [ -n "$GE" ]; then
  pass "git identity: $GN <$GE>"
else
  block "git user.name / user.email unset; repo init refuses to proceed without them"
fi

# --- Vendor blob fixups -----------------------------------------------------
# extract-files.py regenerates vendor/motorola/ FROM SCRATCH, and that directory
# is not a git repo, so every hand fix in it is destroyed with no diff to warn
# you. fix-vendor-blobs.sh reapplies them; --check verifies them and changes
# nothing. This matters here because a tree that fails the check still BUILDS
# CLEANLY and only misbehaves on the device -- no wlan0, unlinked telephony
# libraries, no inbound SMS -- which is the most expensive place to find it.
echo
echo "Vendor tree"
FVB="$BUILD_DIR/device/motorola/sm8635-common/fix-vendor-blobs.sh"
VND="$BUILD_DIR/vendor/motorola/sm8635-common"
if [ ! -f "$FVB" ]; then
  warn "fix-vendor-blobs.sh not found under $BUILD_DIR (device tree not synced yet?)"
elif [ ! -f "$VND/Android.bp" ]; then
  block "vendor/motorola/sm8635-common has no Android.bp; run, in this order:
          device/motorola/sm8635-common/extract-files.py
          device/motorola/sm8635-common/setup-makefiles.py
          device/motorola/sm8635-common/fix-vendor-blobs.sh"
elif FVB_OUT=$(bash "$FVB" --check 2>&1); then
  pass "vendor blob fixups applied"
else
  block "vendor blob fixups MISSING; run $FVB"
  printf '%s\n' "$FVB_OUT" | sed 's/^/          /'
fi

# --- Summary ----------------------------------------------------------------
echo
if [ "$FAILED" -eq 0 ]; then
  echo "PASS. Nothing blocking a build on this machine."
else
  echo "BLOCKED. Fix the items marked BLOCK above, then re-run."
fi
echo
echo "Reminder: always 'breakfast arcfox' (never a hand-written lunch target) and"
echo "verify out/.../args-lineage_arcfox.txt says --release bp4a. Build in the"
echo "FOREGROUND -- background build tasks get reaped on this machine."
exit "$FAILED"

#!/usr/bin/env bash
set -euo pipefail

: "${KSU_DEBUG_BUILD:=0}"
: "${MAKEJ:=1}"

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_HOST=GitHub-Actions
export KBUILD_BUILD_USER=ci-builder

# Paths
FRAG_DIR=.github/config-fragments
CORE_FRAG=$FRAG_DIR/kernelsu_susfs.config
DEBUG_FRAG=$FRAG_DIR/debug_enable.config
PERF_FRAG=$FRAG_DIR/perf_disable_debug.config

for f in "$CORE_FRAG" "$PERF_FRAG" "$DEBUG_FRAG"; do
  [ -f "$f" ] || { echo "Missing fragment $f" >&2; exit 1; }
done

# Base defconfig (mrproper already cleans tree; no need for extra 'clean')
make -j1 O=out mrproper
make -j"$MAKEJ" O=out ARCH=arm64 vendor/meteoric_defconfig
cp out/.config out/base_original_defconfig || true

# Ensure merge script
if [ ! -x scripts/kconfig/merge_config.sh ]; then
  echo "scripts/kconfig/merge_config.sh missing" >&2
  exit 1
fi

# Build fragment list
FRAGS=("$CORE_FRAG")
if [ "$KSU_DEBUG_BUILD" = "1" ]; then
  FRAGS+=("$DEBUG_FRAG")
else
  FRAGS+=("$PERF_FRAG")
fi

cp out/.config out/base_defconfig || true
# Run merge_config.sh without the '-m' flag to allow alldefconfig resolution to happen internally
bash scripts/kconfig/merge_config.sh -O out out/base_defconfig "${FRAGS[@]}"
# Snapshot after merge (already post-alldefconfig)
cp out/.config out/merged_post_merge_config.config || true
echo "---- Post-merge_config MODULES/KPROBES snapshot ----" >&2
grep -nE '^CONFIG_MODULES|^# CONFIG_MODULES|^CONFIG_KPROBES|^# CONFIG_KPROBES' out/.config || { echo "(no lines matched)" >&2; }
echo "---------------------------------------------------" >&2

# Validation
REQ_Y=(
  CONFIG_KSU
  CONFIG_KSU_SUSFS
  CONFIG_KSU_LSM_SECURITY_HOOKS
  CONFIG_KSU_WITH_KPROBES
  CONFIG_KSU_SUSFS_SPOOF_UNAME
  CONFIG_OVERLAY_FS
  CONFIG_OVERLAY_FS_REDIRECT_DIR
  CONFIG_TMPFS_XATTR
  CONFIG_TMPFS_POSIX_ACL
  CONFIG_KALLSYMS
  CONFIG_KPROBES
  CONFIG_SECURITYFS
  CONFIG_PID_NS
  CONFIG_FHANDLE
  CONFIG_MODULES
)
MISSING=()
for k in "${REQ_Y[@]}"; do
  grep -q "^${k}=y" out/.config || MISSING+=("$k")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  if printf '%s\n' "${MISSING[@]}" | grep -Eq 'CONFIG_MODULES|CONFIG_KPROBES'; then
    echo "---- Diagnostic (MODULES/KPROBES mismatch) ----" >&2
    echo "Pre-olddefconfig snippet:" >&2
    grep -nE '^CONFIG_MODULES|^# CONFIG_MODULES|^CONFIG_KPROBES|^# CONFIG_KPROBES' out/.config || true
    echo "Post-olddefconfig snippet:" >&2
    cp out/.config out/merged_post_olddefconfig.config || true
    grep -nE '^CONFIG_MODULES|^# CONFIG_MODULES|^CONFIG_KPROBES|^# CONFIG_KPROBES' out/merged_post_olddefconfig.config || true
    echo "Fragments (for those symbols):" >&2
    for f in "${FRAGS[@]}"; do echo "== $f ==" >&2; grep -E '^CONFIG_MODULES|^# CONFIG_MODULES|^CONFIG_KPROBES|^# CONFIG_KPROBES' "$f" >&2 || true; done
  fi
  echo "ERROR: Missing required options: ${MISSING[*]}" >&2
  exit 2
fi
if ! grep -E '^CONFIG_LSM=".*kernelsu.*"' out/.config >/dev/null; then
  echo "ERROR: CONFIG_LSM missing kernelsu" >&2
  exit 3
fi
if [ "$KSU_DEBUG_BUILD" != "1" ]; then
  for dbg in CONFIG_KASAN CONFIG_UBSAN CONFIG_KFENCE CONFIG_DEBUG_INFO CONFIG_SCHEDSTATS; do
    if grep -q "^${dbg}=y" out/.config; then
      echo "ERROR: Debug option still enabled in non-debug build: $dbg" >&2
      exit 4
    fi
  done
fi

# Output summaries
echo "==== KernelSU / SUSFS Summary ===="
grep -E '^(CONFIG_KSU|CONFIG_KSU_SUSFS|CONFIG_KSU_SUSFS_|CONFIG_OVERLAY_FS|CONFIG_TMPFS_|CONFIG_KALLSYMS|CONFIG_KPROBES|CONFIG_LSM=)' out/.config || true

# Write focused symbol report
grep -E '^(CONFIG_KSU|CONFIG_KSU_SUSFS|CONFIG_KSU_SUSFS_|CONFIG_OVERLAY_FS|CONFIG_TMPFS_|CONFIG_KALLSYMS|CONFIG_KPROBES|CONFIG_LSM=)' out/.config > out/ksu_susfs_symbols.txt || true

# Record fragment hashes for reproducibility
sha256sum "$CORE_FRAG" "$PERF_FRAG" "$DEBUG_FRAG" > out/fragment_hashes.txt 2>/dev/null || true

echo "==== Focused Diff (base vs final) ===="
set -o pipefail || true
( diff -u out/base_original_defconfig out/.config || true ) | grep -E 'KSU|SUSFS|OVERLAY_FS|KALLSYMS|KPROBE|UBSAN|KASAN|KFENCE|DEBUG_INFO|SCHEDSTATS|CONFIG_LSM' | tee out/ksu_focused_diff.txt || true
set +o pipefail || true

make -j1 O=out ARCH=arm64 savedefconfig || true
cp out/defconfig out/ksu_savedefconfig 2>/dev/null || true

rm -f out/base_defconfig

echo "Config merge complete (Debug build: $KSU_DEBUG_BUILD)."

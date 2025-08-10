#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# configure_kernel.sh
# Robust configuration merger & enforcement for KernelSU-Next + SUSFS on
# Nothing Phone (2) (SoC: SM8475) arm64 kernel builds under CI.
#
# Features:
#  - Deterministic merge of base defconfig + required fragments
#  - Enforcement pass (auto re-merge) for critical symbols (y / string)
#  - Accurate diagnostics (root symbols vs similarly prefixed)
#  - Strict separation: BASE vs DEBUG vs PROD builds
#  - Manual VFS hook configuration (no kprobes dependency)
#  - Focused reporting (symbols, fragment hashes, diff)
#  - Support for KernelSU-Next next-susfs branch + SuSFS gki-android12-5.10
#
# Environment (override as needed):
#   KSU_BUILD_MODE=BASE|DEBUG|PROD : build configuration mode
#   KERNEL_DEFCONFIG=vendor/meteoric_defconfig (device base)
#   OUT_DIR=out            : output dir
#   MAKEJ=<n>              : parallel jobs for make (default 8)
#   EXTRA_FRAGMENTS="a b"  : optional extra fragment paths
#
# Copyright (C) 2025 MiguVT
# Author: MiguVT
#
set -euo pipefail

# Build mode: BASE (minimal), DEBUG (development), PROD (production optimized)
: "${KSU_BUILD_MODE:=BASE}"
: "${KERNEL_DEFCONFIG:=vendor/meteoric_defconfig}"
: "${OUT_DIR:=out}"
: "${MAKEJ:=8}"
: "${EXTRA_FRAGMENTS:=}"

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_HOST=GitHub-Actions
export KBUILD_BUILD_USER=ci-builder
## Keep environment uniform with later build stage (LLVM toolchain variables)
export LLVM=1 LLVM_IAS=1

FRAG_DIR=.github/config-fragments
BASE_FRAG=$FRAG_DIR/kernelsu_susfs.config
DEBUG_FRAG=$FRAG_DIR/debug_enable.config
PROD_FRAG=$FRAG_DIR/perf_disable_debug.config

# Validate fragment files exist
for f in "$BASE_FRAG" "$DEBUG_FRAG" "$PROD_FRAG"; do
  [ -f "$f" ] || { echo "[FATAL] Missing fragment: $f" >&2; exit 1; }
done

# Validate build mode
case "$KSU_BUILD_MODE" in
  BASE|DEBUG|PROD) ;;
  *) echo "[FATAL] Invalid KSU_BUILD_MODE: $KSU_BUILD_MODE (must be BASE|DEBUG|PROD)" >&2; exit 1 ;;
esac

if [ ! -x scripts/kconfig/merge_config.sh ]; then
  echo "[FATAL] scripts/kconfig/merge_config.sh missing or not executable" >&2
  exit 1
fi

echo "==> Cleaning output (mrproper)"
make -j1 O="$OUT_DIR" mrproper

echo "==> Applying base defconfig: $KERNEL_DEFCONFIG"
make -j"$MAKEJ" O="$OUT_DIR" "$KERNEL_DEFCONFIG"
cp "$OUT_DIR/.config" "$OUT_DIR/base_original_defconfig" || true

# Fragment selection based on build mode
FRAGS=("$BASE_FRAG")
case "$KSU_BUILD_MODE" in
  DEBUG)
    FRAGS+=("$DEBUG_FRAG")
    ;;
  PROD)
    FRAGS+=("$PROD_FRAG")
    ;;
  BASE)
    # Only base fragment for minimal build
    ;;
esac

if [ -n "$EXTRA_FRAGMENTS" ]; then
  # shellcheck disable=SC2206
  read -ra EXTRA_ARR <<< "$EXTRA_FRAGMENTS"
  FRAGS+=("${EXTRA_ARR[@]}")
fi

cp "$OUT_DIR/.config" "$OUT_DIR/base_defconfig" || true

echo "==> First merge (base + fragments) - Mode: $KSU_BUILD_MODE"
bash scripts/kconfig/merge_config.sh -O "$OUT_DIR" "$OUT_DIR/base_defconfig" "${FRAGS[@]}"
cp "$OUT_DIR/.config" "$OUT_DIR/merged_after_first_pass.config" || true

# ----------------------------------------------------------------------------
# Enforcement logic: ensure required symbols are set based on configurations
# discussed for KernelSU-Next + SuSFS
# ----------------------------------------------------------------------------

# BASE configuration requirements (always enforced)
BASE_REQUIRED_SETTINGS=(
  # KernelSU-Next Core
  CONFIG_KALLSYMS=y
  CONFIG_KALLSYMS_ALL=y
  # Manual VFS Hooks (MANDATORY)
  CONFIG_KSU_WITH_KPROBES=n
  # KernelSU Next Features
  CONFIG_KSU=y
  CONFIG_KSU_SUSFS=y
  # SuSFS Core Requirements
  CONFIG_KSU_SUSFS_SUS_PATH=y
  CONFIG_KSU_SUSFS_SUS_MOUNT=y
  CONFIG_KSU_SUSFS_SUS_KSTAT=y
  CONFIG_KSU_SUSFS_SUS_MAPS=y
  CONFIG_KSU_SUSFS_SUS_PROC_STAT=y
  # Filesystem Support
  CONFIG_PROC_FS=y
  CONFIG_SYSFS=y
  CONFIG_OVERLAY_FS=y
  CONFIG_NAMESPACES=y
  CONFIG_MNT_NS=y
  # Security Base
  CONFIG_SECURITY=y
  CONFIG_SECURITYFS=y
)

# DEBUG specific requirements
DEBUG_REQUIRED_SETTINGS=(
  # KernelSU Debug
  CONFIG_KSU_DEBUG=y
  # SuSFS Debug Features
  CONFIG_KSU_SUSFS_ENABLE_LOG=y
  CONFIG_KSU_SUSFS_SUS_SU=y
  CONFIG_DEBUG_FS=y
  # Kernel Debug for hooks
  CONFIG_DYNAMIC_DEBUG=y
  CONFIG_PRINTK=y
  CONFIG_DEBUG_KERNEL=y
  # VFS Debug (for troubleshoot hooks)
  CONFIG_DEBUG_VFS=y
  # Tracing for hook analysis
  CONFIG_TRACING=y
  CONFIG_FTRACE=y
  CONFIG_FUNCTION_TRACER=y
  # SuSFS Advanced Debug
  CONFIG_KSU_SUSFS_SUS_PROC_CMDLINE=y
  CONFIG_KSU_SUSFS_SUS_PROC_VERSION=y
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y
  CONFIG_KSU_SUSFS_SPOOF_KERNEL_VERSION=y
)

# PROD specific requirements
PROD_REQUIRED_SETTINGS=(
  # SuSFS Production Features
  CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
  CONFIG_KSU_SUSFS_HAS_LKM=y
  # Advanced Hiding Features
  CONFIG_KSU_SUSFS_SUS_PROC_CMDLINE=y
  CONFIG_KSU_SUSFS_SUS_PROC_VERSION=y
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y
  CONFIG_KSU_SUSFS_SPOOF_KERNEL_VERSION=y
  # Enhanced Security
  CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BY_UID=y
  CONFIG_KSU_SUSFS_TRY_UMOUNT=y
  # Security Hardening for production
  CONFIG_STRICT_KERNEL_RWX=y
  CONFIG_RANDOMIZE_BASE=y
)

# Build complete requirements list based on mode
REQUIRED_SETTINGS=("${BASE_REQUIRED_SETTINGS[@]}")
case "$KSU_BUILD_MODE" in
  DEBUG)
    REQUIRED_SETTINGS+=("${DEBUG_REQUIRED_SETTINGS[@]}")
    ;;
  PROD)
    REQUIRED_SETTINGS+=("${PROD_REQUIRED_SETTINGS[@]}")
    ;;
esac

# LSM string requirements (different for each mode)
REQ_STRINGS=()
case "$KSU_BUILD_MODE" in
  DEBUG)
    REQ_STRINGS=( 'CONFIG_LSM="yama,landlock,lockdown,bpf,integrity,selinux,kernelsu"' )
    ;;
  *)
    REQ_STRINGS=( 'CONFIG_LSM="yama,integrity,selinux,kernelsu"' )
    ;;
esac

missing_symbol_report() {
  local sym wanted pattern actual
  sym="$1"; wanted="$2"; pattern="^${sym}="
  if grep -qE "^# ${sym} is not set" "$OUT_DIR/.config"; then
    actual="# ${sym} is not set"
  elif grep -qE "$pattern" "$OUT_DIR/.config"; then
    actual=$(grep -E "$pattern" "$OUT_DIR/.config" | head -1)
  else
    actual="<absent>"
  fi
  printf '  %-40s wanted=%-20s actual=%s\n' "$sym" "$wanted" "$actual" >&2
}

NEED_ENFORCE=()
for entry in "${REQUIRED_SETTINGS[@]}"; do
  sym=${entry%%=*}; val=${entry#*=}
  if ! grep -qE "^${sym}=${val}$" "$OUT_DIR/.config"; then
    NEED_ENFORCE+=("$entry")
  fi
done
for s in "${REQ_STRINGS[@]}"; do
  name=${s%%=*}
  if ! grep -qE "^${s}$" "$OUT_DIR/.config"; then
    NEED_ENFORCE+=("$s")
  fi
done

if [ ${#NEED_ENFORCE[@]} -gt 0 ]; then
  echo "==> Enforcement pass (missing or mismatched symbols detected):" >&2
  for e in "${NEED_ENFORCE[@]}"; do missing_symbol_report "${e%%=*}" "${e#*=}"; done
  ENFORCE_FRAG="$OUT_DIR/.enforce_fragment.config"
  : >"$ENFORCE_FRAG"
  for e in "${NEED_ENFORCE[@]}"; do
    echo "$e" >>"$ENFORCE_FRAG"
  done
  echo "-- enforcement fragment --" >&2
  cat "$ENFORCE_FRAG" >&2
  echo "-------------------------" >&2
  bash scripts/kconfig/merge_config.sh -O "$OUT_DIR" "$OUT_DIR/.config" "$ENFORCE_FRAG"
fi

cp "$OUT_DIR/.config" "$OUT_DIR/merged_after_enforcement.config" || true

# Informational: did enforcement actually change anything?
if [ -f "$OUT_DIR/merged_after_first_pass.config" ]; then
  if cmp -s "$OUT_DIR/merged_after_first_pass.config" "$OUT_DIR/merged_after_enforcement.config"; then
    echo "==> Enforcement result: no changes (all required symbols satisfied in first merge)"
  else
    echo "==> Enforcement result: changes applied (diff saved to enforcement_diff.txt)"
    diff -u "$OUT_DIR/merged_after_first_pass.config" "$OUT_DIR/merged_after_enforcement.config" \
      | grep -E '^[+-](CONFIG_|# CONFIG_)' \
      | sed -e 's/^/ENFORCE_DIFF: /' | tee "$OUT_DIR/enforcement_diff.txt" >/dev/null || true
  fi
fi

# Final verification
FINAL_MISS=()
for entry in "${REQUIRED_SETTINGS[@]}"; do
  sym=${entry%%=*}; val=${entry#*=}
  grep -qE "^${sym}=${val}$" "$OUT_DIR/.config" || FINAL_MISS+=("$sym")
done
for s in "${REQ_STRINGS[@]}"; do
  grep -qE "^${s}$" "$OUT_DIR/.config" || FINAL_MISS+=("${s%%=*}")
done

if [ ${#FINAL_MISS[@]} -gt 0 ]; then
  echo "[FATAL] Still missing required symbols after enforcement: ${FINAL_MISS[*]}" >&2
  exit 2
fi

# Mode-specific validation
case "$KSU_BUILD_MODE" in
  PROD)
    # Ensure heavy debug features are disabled in PROD build
    FORBID=(CONFIG_KSU_DEBUG CONFIG_KSU_SUSFS_ENABLE_LOG CONFIG_DEBUG_KERNEL CONFIG_DEBUG_FS CONFIG_DYNAMIC_DEBUG CONFIG_TRACING CONFIG_KASAN CONFIG_UBSAN CONFIG_KFENCE)
    BAD=()
    for b in "${FORBID[@]}"; do
      grep -qE "^${b}=y" "$OUT_DIR/.config" && BAD+=("$b") || true
    done
    if [ ${#BAD[@]} -gt 0 ]; then
      echo "[FATAL] Forbidden debug symbols enabled in PROD build: ${BAD[*]}" >&2
      exit 3
    fi
    ;;
  DEBUG)
    # Ensure required debug features are enabled in DEBUG build
    REQUIRED_DEBUG=(CONFIG_KSU_DEBUG CONFIG_KSU_SUSFS_ENABLE_LOG CONFIG_DEBUG_FS CONFIG_TRACING)
    MISSING_DEBUG=()
    for d in "${REQUIRED_DEBUG[@]}"; do
      grep -qE "^${d}=y" "$OUT_DIR/.config" || MISSING_DEBUG+=("$d")
    done
    if [ ${#MISSING_DEBUG[@]} -gt 0 ]; then
      echo "[FATAL] Missing required debug symbols in DEBUG build: ${MISSING_DEBUG[*]}" >&2
      exit 4
    fi
    ;;
esac

# Enhanced reporting for KernelSU-Next + SuSFS
REPORT_GREP='^(CONFIG_KSU|CONFIG_KSU_SUSFS|CONFIG_OVERLAY_FS|CONFIG_TMPFS_|CONFIG_KALLSYMS|CONFIG_LSM=|CONFIG_NAMESPACES|CONFIG_MNT_NS)'

echo "==== KernelSU-Next + SuSFS Summary (Mode: $KSU_BUILD_MODE) ===="
grep -E "$REPORT_GREP" "$OUT_DIR/.config" || true
grep -E "$REPORT_GREP" "$OUT_DIR/.config" >"$OUT_DIR/ksu_susfs_symbols.txt" || true

echo "==== Fragment Hashes ===="
sha256sum "$BASE_FRAG" "$DEBUG_FRAG" "$PROD_FRAG" 2>/dev/null | tee "$OUT_DIR/fragment_hashes.txt" || true

echo "==== Focused Diff (base vs final) ===="
set +e
diff -u "$OUT_DIR/base_original_defconfig" "$OUT_DIR/.config" 2>/dev/null | grep -E 'KSU|SUSFS|OVERLAY_FS|KALLSYMS|NAMESPACES|CONFIG_LSM|DEBUG' | tee "$OUT_DIR/ksu_focused_diff.txt" || true
set -e

echo "==> Generating savedefconfig artifact"
make -j1 O="$OUT_DIR" savedefconfig || true
cp "$OUT_DIR/defconfig" "$OUT_DIR/ksu_savedefconfig" 2>/dev/null || true

echo "==> Final verification complete (Build mode: $KSU_BUILD_MODE)"
echo "==> KernelSU-Next + SuSFS configuration ready for compilation"

exit 0

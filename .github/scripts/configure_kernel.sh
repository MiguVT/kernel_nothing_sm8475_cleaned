#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# configure_kernel.sh
# Robust configuration merger & enforcement for KernelSU + SUSFS on
# Nothing Phone (2) (SoC: SM8475) arm64 kernel builds under CI.
#
# Features:
#  - Deterministic merge of base defconfig + required fragments
#  - Enforcement pass (auto re-merge) for critical symbols (y / string)
#  - Accurate diagnostics (root symbols vs similarly prefixed)
#  - Strict separation of performance vs debug builds (KSU_DEBUG_BUILD=1)
#  - Manual VFS hook configuration (no kprobes dependency)
#  - Focused reporting (symbols, fragment hashes, diff)
#
# Environment (override as needed):
#   KSU_DEBUG_BUILD=0|1   : enable heavy debug/instrumentation set
#   KERNEL_DEFCONFIG=vendor/meteoric_defconfig (device base)
#   OUT_DIR=out            : output dir
#   MAKEJ=<n>              : parallel jobs for make (default 8)
#   EXTRA_FRAGMENTS="a b"  : optional extra fragment paths
#
# Copyright (C) 2025 MiguVT
# Author: MiguVT
#
set -euo pipefail

: "${KSU_DEBUG_BUILD:=0}"
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
CORE_FRAG=$FRAG_DIR/kernelsu_susfs.config
DEBUG_FRAG=$FRAG_DIR/debug_enable.config
PERF_FRAG=$FRAG_DIR/perf_disable_debug.config

for f in "$CORE_FRAG" "$DEBUG_FRAG" "$PERF_FRAG"; do
  [ -f "$f" ] || { echo "[FATAL] Missing fragment: $f" >&2; exit 1; }
done

if [ ! -x scripts/kconfig/merge_config.sh ]; then
  echo "[FATAL] scripts/kconfig/merge_config.sh missing or not executable" >&2
  exit 1
fi

echo "==> Cleaning output (mrproper)"
make -j1 O="$OUT_DIR" mrproper

echo "==> Applying base defconfig: $KERNEL_DEFCONFIG"
make -j"$MAKEJ" O="$OUT_DIR" "$KERNEL_DEFCONFIG"
cp "$OUT_DIR/.config" "$OUT_DIR/base_original_defconfig" || true

FRAGS=("$CORE_FRAG")
if [ "$KSU_DEBUG_BUILD" = "1" ]; then
  FRAGS+=("$DEBUG_FRAG")
else
  FRAGS+=("$PERF_FRAG")
fi
if [ -n "$EXTRA_FRAGMENTS" ]; then
  # shellcheck disable=SC2206
  read -ra EXTRA_ARR <<< "$EXTRA_FRAGMENTS"
  FRAGS+=("${EXTRA_ARR[@]}")
fi

cp "$OUT_DIR/.config" "$OUT_DIR/base_defconfig" || true

echo "==> First merge (base + fragments)"
bash scripts/kconfig/merge_config.sh -O "$OUT_DIR" "$OUT_DIR/base_defconfig" "${FRAGS[@]}"
cp "$OUT_DIR/.config" "$OUT_DIR/merged_after_first_pass.config" || true

# ----------------------------------------------------------------------------
# Enforcement logic: ensure required symbols are set; if not, generate a
# supplemental fragment and re-merge exactly once (idempotent).
# ----------------------------------------------------------------------------

# Format: name=value (value 'y' or exact unquoted numeric/string)
# Split required settings into base + debug-only + perf-only blocks so the
# enforcement reflects the updated fragments.
BASE_REQUIRED_SETTINGS=(
  CONFIG_KALLSYMS=y
  CONFIG_KALLSYMS_ALL=y
  CONFIG_KSU_WITH_KPROBES=n
  CONFIG_KSU=y
  CONFIG_KSU_SUSFS=y
  CONFIG_KSU_SUSFS_SUS_PATH=y
  CONFIG_KSU_SUSFS_SUS_MOUNT=y
  CONFIG_KSU_SUSFS_SUS_KSTAT=y
  CONFIG_KSU_SUSFS_SUS_MAPS=y
  CONFIG_KSU_SUSFS_SUS_PROC_STAT=y
  CONFIG_PROC_FS=y
  CONFIG_SYSFS=y
  CONFIG_OVERLAY_FS=y
  CONFIG_NAMESPACES=y
  CONFIG_MNT_NS=y
  CONFIG_SECURITY=y
  CONFIG_SECURITYFS=y
)

# Additional symbols present in the debug fragment (advanced debug / tracing)
DEBUG_REQUIRED_SETTINGS=(
  CONFIG_KSU_DEBUG=y
  CONFIG_KSU_SUSFS_ENABLE_LOG=y
  CONFIG_KSU_SUSFS_SUS_SU=y
  CONFIG_DEBUG_FS=y
  CONFIG_DYNAMIC_DEBUG=y
  CONFIG_PRINTK=y
  CONFIG_DEBUG_KERNEL=y
  CONFIG_DEBUG_VFS=y
  CONFIG_DEBUG_MOUNT=y
  CONFIG_DEBUG_PAGEALLOC=y
  CONFIG_DEBUG_VM=y
  CONFIG_TRACING=y
  CONFIG_FTRACE=y
  CONFIG_FUNCTION_TRACER=y
  # Advanced SuSFS debug features also in debug fragment
  CONFIG_KSU_SUSFS_SUS_PROC_CMDLINE=y
  CONFIG_KSU_SUSFS_SUS_PROC_VERSION=y
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y
  CONFIG_KSU_SUSFS_SPOOF_KERNEL_VERSION=y
)

# Production / perf-only features (from perf_disable_debug.config)
PERF_REQUIRED_SETTINGS=(
  CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
  CONFIG_KSU_SUSFS_HAS_LKM=y
  CONFIG_KSU_SUSFS_SUS_PROC_CMDLINE=y
  CONFIG_KSU_SUSFS_SUS_PROC_VERSION=y
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y
  CONFIG_KSU_SUSFS_SPOOF_KERNEL_VERSION=y
  CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BY_UID=y
  CONFIG_KSU_SUSFS_TRY_UMOUNT=y
  CONFIG_KSU_SUSFS_SUS_SU_WORKING_MODE=2
)

# Build the unified REQUIRED_SETTINGS array according to build type.
REQUIRED_SETTINGS=("${BASE_REQUIRED_SETTINGS[@]}")
if [ "$KSU_DEBUG_BUILD" = "1" ]; then
  REQUIRED_SETTINGS+=("${DEBUG_REQUIRED_SETTINGS[@]}")
else
  REQUIRED_SETTINGS+=("${PERF_REQUIRED_SETTINGS[@]}")
fi

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

if [ ${#FINAL_MISS[@]} -gt 0 ]; then
  echo "[FATAL] Still missing required symbols after enforcement: ${FINAL_MISS[*]}" >&2
  exit 2
fi

if [ "$KSU_DEBUG_BUILD" != "1" ]; then
  # Ensure heavy / debug-only features are really off in perf build
  # (KALLSYMS_ALL retained for both builds per core fragment; removed from forbid list)
  FORBID=(
    CONFIG_KASAN
    CONFIG_KASAN_HW_TAGS
    CONFIG_UBSAN
    CONFIG_KFENCE
    CONFIG_SCHEDSTATS
    CONFIG_DEBUG_INFO
    CONFIG_KSU_DEBUG
    CONFIG_KSU_SUSFS_ENABLE_LOG
    CONFIG_DEBUG_FS
    CONFIG_TRACING
    CONFIG_FTRACE
    CONFIG_FUNCTION_TRACER
    CONFIG_DYNAMIC_DEBUG
    CONFIG_DEBUG_VFS
    CONFIG_DEBUG_MOUNT
    CONFIG_DEBUG_PAGEALLOC
    CONFIG_DEBUG_VM
    CONFIG_IKCONFIG_PROC
  )
  BAD=()
  for b in "${FORBID[@]}"; do
    grep -qE "^${b}=y" "$OUT_DIR/.config" && BAD+=("$b") || true
  done
  if [ ${#BAD[@]} -gt 0 ]; then
    echo "[FATAL] Forbidden debug symbols enabled in perf build: ${BAD[*]}" >&2
    exit 3
  fi
fi

REPORT_GREP='^(CONFIG_KSU|CONFIG_KSU_SUSFS|CONFIG_KSU_SUSFS_|CONFIG_OVERLAY_FS|CONFIG_TMPFS_|CONFIG_KALLSYMS(=|$))'

echo "==== KernelSU / SUSFS Summary ===="
grep -E "$REPORT_GREP" "$OUT_DIR/.config" || true
grep -E "$REPORT_GREP" "$OUT_DIR/.config" >"$OUT_DIR/ksu_susfs_symbols.txt" || true

echo "==== Fragment Hashes ===="
sha256sum "$CORE_FRAG" "$DEBUG_FRAG" "$PERF_FRAG" 2>/dev/null | tee "$OUT_DIR/fragment_hashes.txt" || true

echo "==== Focused Diff (base vs final) ===="
set +e
diff -u "$OUT_DIR/base_original_defconfig" "$OUT_DIR/.config" 2>/dev/null | grep -E 'KSU|SUSFS|OVERLAY_FS|KALLSYMS|UBSAN|KASAN|KFENCE|DEBUG_INFO|SCHEDSTATS' | tee "$OUT_DIR/ksu_focused_diff.txt" || true
set -e

echo "==> Generating savedefconfig artifact"
make -j1 O="$OUT_DIR" savedefconfig || true
cp "$OUT_DIR/defconfig" "$OUT_DIR/ksu_savedefconfig" 2>/dev/null || true

echo "==> Final verification complete (Debug build: $KSU_DEBUG_BUILD)"

exit 0

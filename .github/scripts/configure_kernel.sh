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

# Format: name=value (value 'y' or exact quoted string)
REQUIRED_SETTINGS=(
  CONFIG_KSU=y
  CONFIG_KSU_SUSFS=y
  CONFIG_KSU_LSM_SECURITY_HOOKS=y
  CONFIG_KSU_WITH_KPROBES=y
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y
  CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
  CONFIG_OVERLAY_FS=y
  CONFIG_OVERLAY_FS_REDIRECT_DIR=y
  CONFIG_OVERLAY_FS_INDEX=y
  CONFIG_TMPFS_XATTR=y
  CONFIG_TMPFS_POSIX_ACL=y
  CONFIG_KALLSYMS=y
  CONFIG_KPROBES=y
  CONFIG_SECURITYFS=y
  CONFIG_PID_NS=y
  CONFIG_FHANDLE=y
  CONFIG_MODULES=y
  CONFIG_MODULE_UNLOAD=y
  CONFIG_IKCONFIG=y
)

REQ_STRINGS=(
  'CONFIG_LSM="yama,integrity,selinux,kernelsu"'
)

if [ "$KSU_DEBUG_BUILD" = "1" ]; then
  # Debug build expansions (will already be supplied via fragment, but enforce anyway)
  REQUIRED_SETTINGS+=(
    CONFIG_KSU_DEBUG=y
    CONFIG_KSU_SUSFS_ENABLE_LOG=y
    CONFIG_DEBUG_INFO=y
    CONFIG_DEBUG_INFO_DWARF4=y
    CONFIG_UBSAN=y
    CONFIG_KASAN=y
    CONFIG_KASAN_HW_TAGS=y
    CONFIG_KFENCE=y
    CONFIG_SCHEDSTATS=y
    CONFIG_KALLSYMS_ALL=y
    CONFIG_IKCONFIG_PROC=y
    CONFIG_KPROBE_EVENTS=y
  )
  REQ_STRINGS=( 'CONFIG_LSM="yama,landlock,lockdown,bpf,integrity,selinux,kernelsu"' )
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

if [ "$KSU_DEBUG_BUILD" != "1" ]; then
  # Ensure heavy debug features are really off in perf build
  FORBID=(CONFIG_KASAN CONFIG_KASAN_HW_TAGS CONFIG_UBSAN CONFIG_KFENCE CONFIG_SCHEDSTATS CONFIG_DEBUG_INFO CONFIG_KALLSYMS_ALL CONFIG_KSU_DEBUG CONFIG_KSU_SUSFS_ENABLE_LOG)
  BAD=()
  for b in "${FORBID[@]}"; do
    grep -qE "^${b}=y" "$OUT_DIR/.config" && BAD+=("$b") || true
  done
  if [ ${#BAD[@]} -gt 0 ]; then
    echo "[FATAL] Forbidden debug symbols enabled in perf build: ${BAD[*]}" >&2
    exit 3
  fi
fi

# Targeted snapshots
echo "---- Root symbol snapshot (MODULES/KPROBES) ----" >&2
grep -nE '^(CONFIG_MODULES=|# CONFIG_MODULES is not set|CONFIG_KPROBES=|# CONFIG_KPROBES is not set)' "$OUT_DIR/.config" || true
echo "------------------------------------------------" >&2

REPORT_GREP='^(CONFIG_KSU|CONFIG_KSU_SUSFS|CONFIG_KSU_SUSFS_|CONFIG_OVERLAY_FS|CONFIG_TMPFS_|CONFIG_KALLSYMS(=|$)|CONFIG_KPROBES=|CONFIG_LSM=)'

echo "==== KernelSU / SUSFS Summary ===="
grep -E "$REPORT_GREP" "$OUT_DIR/.config" || true
grep -E "$REPORT_GREP" "$OUT_DIR/.config" >"$OUT_DIR/ksu_susfs_symbols.txt" || true

echo "==== Fragment Hashes ===="
sha256sum "$CORE_FRAG" "$DEBUG_FRAG" "$PERF_FRAG" 2>/dev/null | tee "$OUT_DIR/fragment_hashes.txt" || true

echo "==== Focused Diff (base vs final) ===="
set +e
diff -u "$OUT_DIR/base_original_defconfig" "$OUT_DIR/.config" 2>/dev/null | grep -E 'KSU|SUSFS|OVERLAY_FS|KALLSYMS|KPROBE|UBSAN|KASAN|KFENCE|DEBUG_INFO|SCHEDSTATS|CONFIG_LSM' | tee "$OUT_DIR/ksu_focused_diff.txt" || true
set -e

echo "==> Generating savedefconfig artifact"
make -j1 O="$OUT_DIR" savedefconfig || true
cp "$OUT_DIR/defconfig" "$OUT_DIR/ksu_savedefconfig" 2>/dev/null || true

echo "==> Final verification complete (Debug build: $KSU_DEBUG_BUILD)"

exit 0

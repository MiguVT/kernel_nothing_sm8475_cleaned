#!/usr/bin/env bash
set -euo pipefail

# Paths
BASE_DEFCONFIG="arch/arm64/configs/meteoric_defconfig"
FRAGMENT="ksu_ci.config"
OUTDIR="out"

mkdir -p "${OUTDIR}"

# 1. Write minimal override fragment
cat > "${FRAGMENT}" << 'EOF'
#
# ksu_ci.config – minimal overrides for Meteoric Kernel v6 (SM8475)
#

# KernelSU-Next + SUSFS (mandatory for root hiding)
CONFIG_KSU_NEXT=y
CONFIG_KSU_SUSFS_HAS_OVERLAYFS=y
CONFIG_KSU_SUSFS_AUTO_ADD_PATH=y
CONFIG_KSU_SUSFS_AUTO_ADD_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_TRY_UMOUNT=y

# Project Matrixx scheduler & performance
CONFIG_CASS_SCHED=y
CONFIG_SCHED_TUNE=y
CONFIG_SCHED_BOOST=y
CONFIG_CPU_INPUT_BOOST=y
CONFIG_CPU_INPUT_BOOST_DURATION_MS=150
CONFIG_CPU_INPUT_BOOST_FREQ_LP=1248000
CONFIG_CPU_INPUT_BOOST_FREQ_PERF=2304000
CONFIG_HZ=300

# Tickless power-saving
CONFIG_NO_HZ_FULL=y
CONFIG_NO_HZ_IDLE=y

# ZRAM built-in for swap
CONFIG_ZRAM=y
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_FRONTSWAP=y

# Enforce BBR as default TCP congestion  
CONFIG_DEFAULT_TCP_CONG="bbr2"

# Preserve 32-bit compatibility for vendor blobs
CONFIG_COMPAT_VDSO=y
CONFIG_THUMB2_COMPAT_VDSO=y
CONFIG_KUSER_HELPERS=y

# Disable debug/sanitizer for production
CONFIG_UBSAN=n
CONFIG_KASAN=n
EOF

# 2. Merge non-interactively and resolve dependencies
scripts/kconfig/merge_config.sh "${BASE_DEFCONFIG}" "${FRAGMENT}" > "${OUTDIR}/.config"
make -C "${OUTDIR}" olddefconfig

# 3. Cleanup
rm -f "${FRAGMENT}"

echo "✅ out/.config ready: optimized minimal overrides applied."

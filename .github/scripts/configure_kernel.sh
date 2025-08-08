#!/usr/bin/env bash
set -euo pipefail

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_HOST=GitHub-Actions
export KBUILD_BUILD_USER=ci-builder

make -j1 O=out clean mrproper
make -j1 O=out ARCH=arm64 vendor/meteoric_defconfig

# Complete optimization for Nothing Phone 2 (SM8475)
cat > ksu_ci.config << 'EOF'
# KernelSU-Next & SUSFS (stable integration)
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_MODULE=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y

# Remove sanitizers for performance
# CONFIG_UBSAN is not set
# CONFIG_KASAN is not set

# Keep essential security hardening
CONFIG_HARDENED_USERCOPY=y
CONFIG_SLAB_FREELIST_RANDOM=y
CONFIG_SLAB_FREELIST_HARDENED=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_SHADOW_CALL_STACK=y

# ARM64 advanced optimizations for Kryo 670
CONFIG_ARM64_PTR_AUTH=y
CONFIG_ARM64_BTI=y
# CONFIG_ARM64_BTI_KERNEL is not set
CONFIG_ARM64_E0PD=y
CONFIG_ARM64_TLB_RANGE=y
CONFIG_ARCH_RANDOM=y

# Optimize for SM8475 performance
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO_CLANG_THIN_RAMSIZE=128
CONFIG_PREEMPT_NONE=y
CONFIG_HZ=500

# Memory layout optimizations
CONFIG_ARCH_MMAP_RND_BITS=18
CONFIG_VMAP_STACK=y
CONFIG_RELR=y

# CPU frequency scaling (battery + performance)
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
# CONFIG_CPU_FREQ_GOV_ONDEMAND is not set
# CONFIG_CPU_FREQ_GOV_CONSERVATIVE is not set

# Power management optimizations
CONFIG_CPU_IDLE=y
CONFIG_CPU_IDLE_GOV_MENU=y
CONFIG_ARCH_HAS_CPU_RELAX=y

# Thermal management (critical for SD8+G1)
CONFIG_THERMAL=y
CONFIG_THERMAL_GOV_STEP_WISE=y
CONFIG_CPU_THERMAL=y

# Memory compression for battery
CONFIG_ZSMALLOC=y
CONFIG_ZRAM=y
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_FRONTSWAP=y
CONFIG_CMA=y

# I/O optimization
CONFIG_IOSCHED_BFQ=y
CONFIG_BFQ_GROUP_IOSCHED=y

# GKI optimizations
CONFIG_MODVERSIONS=y
CONFIG_TRIM_UNUSED_KSYMS=y

# Debug stripping (safe for production)
# CONFIG_DEBUG_INFO is not set
# CONFIG_DEBUG_KERNEL is not set
# CONFIG_FTRACE is not set
# CONFIG_TRACING is not set
EOF

make -j1 O=out CC=clang ARCH=arm64 vendor/meteoric_defconfig ksu_ci.config savedefconfig
rm -f ksu_ci.config

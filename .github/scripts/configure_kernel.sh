#!/usr/bin/env bash
set -euo pipefail

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_HOST=GitHub-Actions
export KBUILD_BUILD_USER=ci-builder

# 1) Clean + base defconfig
make -j1 O=out clean mrproper
make -j1 O=out ARCH=arm64 vendor/meteoric_defconfig

# 2) Non-interactive allconfig merge
cat > ksu_ci.config << 'EOF'
# KernelSU-Next & SUSFS
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_MODULE=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y

# Disable 32-bit prompts
# CONFIG_COMPAT is not set
# CONFIG_KUSER_HELPERS is not set
# CONFIG_COMPAT_VDSO is not set
# CONFIG_THUMB2_COMPAT_VDSO is not set

# Architecture options
CONFIG_JUMP_LABEL=y
CONFIG_SECCOMP=y
CONFIG_STACKPROTECTOR=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_SHADOW_CALL_STACK=y

# LTO choice
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO_CLANG_THIN_RAMSIZE=96

# Performance & tickless idle
CONFIG_PREEMPT_NONE=y
CONFIG_HZ=300
CONFIG_NO_HZ_FULL=y
CONFIG_NO_HZ_IDLE=y

# Thermal management
CONFIG_THERMAL=y
CONFIG_THERMAL_GOV_STEP_WISE=y
CONFIG_CPU_THERMAL=y

# CPU governors & power
CONFIG_CPU_IDLE_GOV_MENU=y
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y

# Memory optimizations
CONFIG_VMAP_STACK=y
CONFIG_ZRAM=y
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_CMA=y

# Security & sanitizers
CONFIG_HARDENED_USERCOPY=y
CONFIG_SLAB_FREELIST_RANDOM=y
CONFIG_SLAB_FREELIST_HARDENED=y
CONFIG_UBSAN=y
CONFIG_UBSAN_TRAP=y
CONFIG_UBSAN_BOUNDS=y

# Subsystems
CONFIG_CGROUPS=y
CONFIG_NAMESPACES=y
EOF

# Merge without interaction
make -j1 O=out CC=clang ARCH=arm64 \
     KCONFIG_ALLCONFIG=ksu_ci.config \
     vendor/meteoric_defconfig alldefconfig

rm ksu_ci.config

# 3) Build
make -j$(nproc) O=out CC=clang ARCH=arm64

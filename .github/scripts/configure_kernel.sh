#!/usr/bin/env bash
set -euo pipefail

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_HOST=GitHub-Actions
export KBUILD_BUILD_USER=ci-builder

# 1) Clean and apply base defconfig
make -j1 O=out clean mrproper
make -j1 O=out ARCH=arm64 vendor/meteoric_defconfig

# 2) Create config fragment (replicating ksu.config approach)
cat > ksu_ci.config << 'EOF'
# KernelSU-Next & SUSFS integration
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_MODULE=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y

# Legacy compatibility disabling
# CONFIG_IA32_EMULATION is not set
# CONFIG_COMPAT_VDSO32 is not set
# CONFIG_COMPAT_VDSO32_X86_OLD is not set

# Strip debug & disable module signing
# CONFIG_DEBUG_INFO is not set
# CONFIG_DEBUG_KERNEL is not set
CONFIG_SYSTEM_TRUSTED_KEYS=""
# CONFIG_MODULE_SIG is not set
# CONFIG_MODULE_SIG_ALL is not set
# CONFIG_MODULE_SIG_FORCE is not set

# Clang ThinLTO
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO_CLANG_THIN_RAMSIZE=64

# Hardening sanitizers
CONFIG_UBSAN=y
CONFIG_UBSAN_TRAP=y
CONFIG_UBSAN_BOUNDS=y
CONFIG_UBSAN_SANITIZE_ALL=y
CONFIG_KASAN=y
CONFIG_KASAN_OUTLINE=y

# Performance & tickless idle
CONFIG_PREEMPT_NONE=y
CONFIG_HZ=300
CONFIG_NO_HZ_FULL=y

# Minimal subsystems
CONFIG_CGROUPS=y
CONFIG_NAMESPACES=y
# CONFIG_FTRACE is not set
# CONFIG_UPROBES is not set
EOF

# 3) Apply fragment and finalize (exactly like legacy build.sh)
make -j1 O=out CC=clang ARCH=arm64 vendor/meteoric_defconfig ksu_ci.config savedefconfig

# 4) Clean up
rm -f ksu_ci.config

#!/usr/bin/env bash
set -euo pipefail

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_HOST=GitHub-Actions
export KBUILD_BUILD_USER=ci-builder

# 1) Clean and start from vendor defconfig
make -j1 O=out clean mrproper
make -j1 O=out ARCH=arm64 vendor/meteoric_defconfig

# 2) Prepare scripts/config
#   scripts/config needs a .config in the source tree, so copy ours in
cp out/.config .config

# 3) Enable/disable each feature
#    KernelSU-Next & SUSFS
./scripts/config --enable CONFIG_KSU
./scripts/config --enable CONFIG_KSU_SUSFS
./scripts/config --enable CONFIG_KSU_SUSFS_MODULE
./scripts/config --enable CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT

#    Legacy 32-bit compat (drop ~0.5 MiB)
./scripts/config --disable CONFIG_IA32_EMULATION
./scripts/config --disable CONFIG_COMPAT_VDSO32
./scripts/config --disable CONFIG_COMPAT_VDSO32_X86_OLD

#    Strip debug + disable module signing
./scripts/config --disable CONFIG_DEBUG_INFO
./scripts/config --disable CONFIG_DEBUG_KERNEL
./scripts/config --set-val CONFIG_SYSTEM_TRUSTED_KEYS \"\"
./scripts/config --disable CONFIG_MODULE_SIG
./scripts/config --disable CONFIG_MODULE_SIG_ALL
./scripts/config --disable CONFIG_MODULE_SIG_FORCE

#    Clang ThinLTO
./scripts/config --enable CONFIG_LTO_CLANG_THIN
./scripts/config --set-val CONFIG_LTO_CLANG_THIN_RAMSIZE 64

#    Hardening sanitizers
./scripts/config --enable CONFIG_UBSAN
./scripts/config --enable CONFIG_UBSAN_TRAP
./scripts/config --enable CONFIG_UBSAN_BOUNDS
./scripts/config --enable CONFIG_UBSAN_SANITIZE_ALL
./scripts/config --enable CONFIG_KASAN
./scripts/config --enable CONFIG_KASAN_OUTLINE

#    Performance & tickless idle
./scripts/config --enable CONFIG_PREEMPT_NONE
./scripts/config --set-val CONFIG_HZ 300
./scripts/config --enable CONFIG_NO_HZ_FULL

#    Minimal subsystems
./scripts/config --enable CONFIG_CGROUPS
./scripts/config --enable CONFIG_NAMESPACES
./scripts/config --disable CONFIG_FTRACE
./scripts/config --disable CONFIG_UPROBES

# 4) Finalize config non-interactively
make -j1 O=out ARCH=arm64 olddefconfig

# 5) Copy back
cp .config out/.config

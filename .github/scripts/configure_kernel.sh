#!/usr/bin/env bash
set -euo pipefail

# 1) Clean and apply vendor defconfig into out/
make -j1 O=out clean mrproper
make -j1 O=out ARCH=arm64 vendor/meteoric_defconfig

# 2) Configure out/.config directly
CONFIG=out/.config

# KernelSU-Next & SUSFS
./scripts/config --file $CONFIG --enable CONFIG_KSU
./scripts/config --file $CONFIG --enable CONFIG_KSU_SUSFS
./scripts/config --file $CONFIG --enable CONFIG_KSU_SUSFS_MODULE
./scripts/config --file $CONFIG --enable CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT

# Disable legacy 32-bit compat (~0.5 MiB)
./scripts/config --file $CONFIG --disable CONFIG_IA32_EMULATION
./scripts/config --file $CONFIG --disable CONFIG_COMPAT_VDSO32
./scripts/config --file $CONFIG --disable CONFIG_COMPAT_VDSO32_X86_OLD

# Strip debug & disable module signing
./scripts/config --file $CONFIG --disable CONFIG_DEBUG_INFO
./scripts/config --file $CONFIG --disable CONFIG_DEBUG_KERNEL
./scripts/config --file $CONFIG --set-val CONFIG_SYSTEM_TRUSTED_KEYS ""
./scripts/config --file $CONFIG --disable CONFIG_MODULE_SIG
./scripts/config --file $CONFIG --disable CONFIG_MODULE_SIG_ALL
./scripts/config --file $CONFIG --disable CONFIG_MODULE_SIG_FORCE

# Clang ThinLTO
./scripts/config --file $CONFIG --enable CONFIG_LTO_CLANG_THIN
./scripts/config --file $CONFIG --set-val CONFIG_LTO_CLANG_THIN_RAMSIZE 64

# Hardening sanitizers
./scripts/config --file $CONFIG --enable CONFIG_UBSAN
./scripts/config --file $CONFIG --enable CONFIG_UBSAN_TRAP
./scripts/config --file $CONFIG --enable CONFIG_UBSAN_BOUNDS
./scripts/config --file $CONFIG --enable CONFIG_UBSAN_SANITIZE_ALL
./scripts/config --file $CONFIG --enable CONFIG_KASAN
./scripts/config --file $CONFIG --enable CONFIG_KASAN_OUTLINE

# Performance & tickless idle
./scripts/config --file $CONFIG --enable CONFIG_PREEMPT_NONE
./scripts/config --file $CONFIG --set-val CONFIG_HZ 300
./scripts/config --file $CONFIG --enable CONFIG_NO_HZ_FULL

# Minimal subsystems
./scripts/config --file $CONFIG --enable CONFIG_CGROUPS
./scripts/config --file $CONFIG --enable CONFIG_NAMESPACES
./scripts/config --file $CONFIG --disable CONFIG_FTRACE
./scripts/config --file $CONFIG --disable CONFIG_UPROBES

# 3) Finalize non-interactively in out/
make -j1 O=out ARCH=arm64 olddefconfig KCONFIG_ALLCONFIG=$CONFIG

#!/usr/bin/env bash
set -e

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_HOST=GitHub-Actions
export KBUILD_BUILD_USER=ci-builder

make O=out clean mrproper
make O=out ARCH=arm64 vendor/meteoric_defconfig

# Append all custom configs
printf '%s\n' \
  "CONFIG_KSU=y" \
  "CONFIG_KSU_SUSFS=y" \
  "CONFIG_KSU_SUSFS_MODULE=y" \
  "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" \
  "" \
  "CONFIG_IA32_EMULATION=n" \
  "CONFIG_COMPAT_VDSO32=n" \
  "CONFIG_COMPAT_VDSO32_X86_OLD=n" \
  "" \
  "CONFIG_DEBUG_INFO=n" \
  "CONFIG_DEBUG_KERNEL=n" \
  "CONFIG_SYSTEM_TRUSTED_KEYS=\"\"" \
  "CONFIG_MODULE_SIG=n" \
  "CONFIG_MODULE_SIG_ALL=n" \
  "CONFIG_MODULE_SIG_FORCE=n" \
  "" \
  "CONFIG_LTO_CLANG_THIN=y" \
  "CONFIG_LTO_CLANG_THIN_RAMSIZE=64" \
  "" \
  "CONFIG_UBSAN=y" \
  "CONFIG_UBSAN_TRAP=y" \
  "CONFIG_UBSAN_BOUNDS=y" \
  "CONFIG_UBSAN_SANITIZE_ALL=y" \
  "CONFIG_KASAN=y" \
  "CONFIG_KASAN_OUTLINE=y" \
  "" \
  "CONFIG_PREEMPT_NONE=y" \
  "CONFIG_HZ=300" \
  "CONFIG_NO_HZ_FULL=y" \
  "" \
  "CONFIG_CGROUPS=y" \
  "CONFIG_NAMESPACES=y" \
  "CONFIG_FTRACE=n" \
  "CONFIG_UPROBES=n" \
>> out/.config

make O=out ARCH=arm64 olddefconfig

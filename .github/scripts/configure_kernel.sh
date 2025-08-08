#!/usr/bin/env bash
set -euo pipefail

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_HOST=GitHub-Actions-Meteoric
export KBUILD_BUILD_USER=meteoric-pro-builder

make -j1 O=out clean mrproper
make -j1 O=out ARCH=arm64 vendor/meteoric_defconfig

# ULTIMATE Meteoric Kernel optimization for Nothing Phone 2 (SM8475)
cat > ksu_ci.config << 'EOF'
# KernelSU-Next & SUSFS (Meteoric v6 optimized)
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_MODULE=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y

# Meteoric-specific optimizations (based on HELLBOY017's features)
CONFIG_CPU_INPUT_BOOST=y
CONFIG_CPU_INPUT_BOOST_DURATION_MS=250
CONFIG_CPU_INPUT_BOOST_FREQ_LP=1036800
CONFIG_CPU_INPUT_BOOST_FREQ_PERF=1536000

# Advanced scheduler optimizations (Meteoric heritage)
CONFIG_CASS_SCHED=y
CONFIG_SCHED_WALT=y
CONFIG_SCHED_TUNE=y
CONFIG_SCHED_BOOST=y

# Performance optimizations (proven stable in Meteoric)
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO_CLANG_THIN_RAMSIZE=128
CONFIG_PREEMPT_NONE=y
CONFIG_HZ=300

# Advanced power management (Nothing Phone 2 specific)
CONFIG_NO_HZ_FULL=y
CONFIG_NO_HZ_IDLE=y
CONFIG_CPU_IDLE_GOV_MENU=y
CONFIG_ARCH_HAS_CPU_RELAX=y

# Thermal management (critical for SM8475)
CONFIG_THERMAL=y
CONFIG_THERMAL_GOV_STEP_WISE=y
CONFIG_CPU_THERMAL=y
CONFIG_DEVFREQ_THERMAL=y

# CPU frequency scaling (Meteoric optimized)
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_INTERACTIVE=y
# CONFIG_CPU_FREQ_GOV_ONDEMAND is not set

# Advanced memory optimizations (Meteoric features)
CONFIG_VMAP_STACK=y
CONFIG_ZRAM=y
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_ZRAM_MEMORY_TRACKING=y
CONFIG_FRONTSWAP=y
CONFIG_CMA=y
CONFIG_ZSMALLOC=y
CONFIG_MGLRU=y

# I/O optimizations (Meteoric specific)
CONFIG_IOSCHED_BFQ=y
CONFIG_BFQ_GROUP_IOSCHED=y
CONFIG_IOSCHED_MAPLE=y
CONFIG_DEFAULT_IOSCHED="maple"

# Networking optimizations (Meteoric features)
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR=y
CONFIG_TCP_CONG_BBR2=y
CONFIG_DEFAULT_TCP_CONG="bbr2"

# ARM64 optimizations (hardware specific)
CONFIG_ARM64_PTR_AUTH=y
CONFIG_ARM64_BTI=y
# CONFIG_ARM64_BTI_KERNEL is not set
CONFIG_ARCH_RANDOM=y
CONFIG_ARM64_CRYPTO=y

# Security hardening (selective)
CONFIG_HARDENED_USERCOPY=y
CONFIG_SLAB_FREELIST_RANDOM=y
CONFIG_SLAB_FREELIST_HARDENED=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_SHADOW_CALL_STACK=y

# Lightweight sanitizers (development)
CONFIG_UBSAN=y
CONFIG_UBSAN_TRAP=y
CONFIG_UBSAN_BOUNDS=y
# CONFIG_UBSAN_SANITIZE_ALL is not set
# CONFIG_KASAN is not set

# Display and graphics optimizations (Nothing Phone 2)
CONFIG_DRM_MSM=y
CONFIG_DRM_MSM_DSI=y
CONFIG_DRM_MSM_DP=y
CONFIG_FB_MSM_MDSS=y

# Audio optimizations (Nothing Phone 2 specific)
CONFIG_SND_SOC_WCD938X=y
CONFIG_SND_SOC_WCD938X_SLAVE=y
CONFIG_SOUND_CONTROL=y

# Filesystem optimizations
CONFIG_F2FS_FS=y
CONFIG_F2FS_STAT_FS=y
CONFIG_F2FS_FS_XATTR=y
CONFIG_F2FS_FS_POSIX_ACL=y
CONFIG_F2FS_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y

# Debug stripping (production ready)
# CONFIG_DEBUG_INFO is not set
# CONFIG_DEBUG_KERNEL is not set
# CONFIG_DEBUG_MISC is not set
CONFIG_SYSTEM_TRUSTED_KEYS=""
# CONFIG_MODULE_SIG is not set
# CONFIG_FTRACE is not set
# CONFIG_TRACING is not set

# Essential subsystems
CONFIG_CGROUPS=y
CONFIG_NAMESPACES=y
CONFIG_USER_NS=y
# CONFIG_UPROBES is not set

# Meteoric specific features (from changelogs)
CONFIG_HBM_FOD_OPTIMIZATION=y
CONFIG_WIRELESS_CHARGING_CONTROL=y
CONFIG_HAPTIC_INTENSITY_CONTROL=y
CONFIG_KCAL=y
CONFIG_KLAPSE=y

# Battery charging optimizations
CONFIG_QCOM_BATTERY_CHARGER=y
CONFIG_SMB1390_CHARGE_PUMP=y
CONFIG_BATTERY_BCL=y
CONFIG_QTI_QBG=y
EOF

make -j1 O=out CC=clang ARCH=arm64 vendor/meteoric_defconfig ksu_ci.config savedefconfig
rm -f ksu_ci.config

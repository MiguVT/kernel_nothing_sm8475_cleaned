# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Meteoric Kernel by HELLBOY017 | Mod by MiguVT
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=Pong
device.name2=PongIND
device.name3=PongEEA
'; } # end properties

# boot image installation
block=boot;
is_slot_device=1;
## AnyKernel methods (DO NOT CHANGE)
# import patching functions/variables - see for reference
. tools/ak3-core.sh;


# Install SUSFS userspace tools
ui_print " ";
ui_print "🛡️ Installing SUSFS userspace tools...";
if [ -f "$home/susfs_tools/ksu_susfs" ]; then
  mkdir -p /data/adb/ksu/bin;
  cp $home/susfs_tools/ksu_susfs /data/adb/ksu/bin/ksu_susfs;
  chmod 755 /data/adb/ksu/bin/ksu_susfs;
  ui_print "✅ SUSFS tool installed";
  if [ -f "$home/susfs_tools/ksu_susfs_arm" ]; then
    cp $home/susfs_tools/ksu_susfs_arm /data/adb/ksu/bin/ksu_susfs_arm;
    chmod 755 /data/adb/ksu/bin/ksu_susfs_arm;
    ui_print "✅ SUSFS ARM32 backup installed";
  fi;
else
  ui_print "⚠️ SUSFS tools not found";
fi;


split_boot;
flash_boot;

# vendor_boot installation (for dtb)
block=vendor_boot;
is_slot_device=1;
reset_ak;
split_boot;
flash_boot;

# dtbo installation
flash_generic dtbo;

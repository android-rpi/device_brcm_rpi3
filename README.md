Read it first : https://github.com/android-rpi/local_manifests

## Build Kernel
 1. Install gcc-arm-linux-gnueabihf
 2. $ cd kernel/rpi
 3. $ ARCH=arm scripts/kconfig/merge_config.sh arch/arm/configs/bcm2709_defconfig android/configs/android-base.cfg android/configs/android-recommended.cfg
 4. $ ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- make zImage
 5. $ ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- make dtbs

## Install python mako module
 1. sudo apt-get install python-mako

## Patch framework source :
 1. $ cd $WORKING_DIR
 2. $ sh device/brcm/rpi3/patches/install.sh
 
## Build Android source
 1. Continue build with http://source.android.com/source/building.html
 2. $ source build/envsetup.sh
 3. $ lunch rpi3-eng
 4. $ make ramdisk systemimage
 
## Help for build failure :
 1. https://github.com/android-rpi/device_brcm_rpi3/wiki/Build-Errors

## Prepare sd card
 # Partitions of the card should be set-up like followings.
 1. p1 512MB for BOOT : Do fdisk : W95 FAT32(LBA) & Bootable, mkfs.vfat
 2. p2 512MB for /system : Do fdisk, new primary partition
 3. p3 512MB for /cache  : Do fdisk, mkfs.ext4
 4. p4 remainings for /data : Do fdisk, mkfs.ex4
 5. Set volume label for each partition - system, cache, userdata: use -L option of mkfs.ext4, e2label command, or -n option of mkfs.vfat
 
## Write system partition
 1. $ cd out/target/product/rpi3
 2. $ sudo dd if=system.img of=/dev/<p2> bs=1M
  
## Copy kernel & ramdisk to BOOT partition
 1. device/brcm/rpi3/boot/* to p1:/
 2. kernel/rpi/arch/arm/boot/zImage to p1:/
 3. kernel/rpi/arch/arm/boot/dts/bcm2710-rpi-3-b.dtb to p1:/
 4. kernel/rpi/arch/arm/boot/dts/overlays/vc4-kms-v3d.dtbo to p1:/overlays/vc4-kms-v3d.dtbo
 5. out/target/product/rpi3/ramdisk.img to p1:/

## HDMI_MODE : If DVI monitor does not work, try followings for p1:/config.txt
 1. hdmi_group=2
 2. hdmi_mode=85

## How to put Android-TV launcher :
 1. https://github.com/android-rpi/device_brcm_rpi3/wiki#how-to-apply-android-tv-leanback-launcher

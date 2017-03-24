#/bin/bash
echo "EXPERIMENTAL SCRIPT! USE AT YOUR OWN RISK!"
if [ `id -u` != 0 ]; then
    echo "Must be root to run script"
    exit
fi

echo "Enter Image Size in GiB"
read SIZE

if  [ "$SIZE" -lt 3 ] ; then
	echo "Size should be more than 3GiB"
else
	echo "Enter Filename:"
	read IMGNAME
	echo "Creating Image File:"
	dd if=/dev/zero of="$IMGNAME".img bs=512k count=$(echo "$SIZE*1024*2" | bc)
	sync
	kpartx -a "$IMGNAME".img
	sync
	(
	echo o
	echo n
	echo p
	echo 1
	echo
	echo +512M
	echo n
	echo p
	echo 2
	echo
	echo +1024M
	echo n
	echo p
	echo 3
	echo
	echo +512M
	echo n
	echo p
	echo 4
	echo
	echo
	echo t
	echo 1
	echo c
	echo a
	echo 1
	echo w
	) | fdisk /dev/loop0
	sync
	kpartx -d "$IMGNAME".img
	sync
	kpartx -a "$IMGNAME".img
	sync
	sleep 5
	mkfs.fat -F 32 /dev/mapper/loop0p1
	mkfs.ext4 /dev/mapper/loop0p3
	mkfs.ext4 /dev/mapper/loop0p4
	dd if=../../../out/target/product/rpi3/system.img of=/dev/mapper/loop0p2 bs=1M
	mkdir -p sdcard/boot
	sync
	mount /dev/mapper/loop0p1 sdcard/boot
	sync
	cp boot/* sdcard/boot
	cp ../../../kernel/rpi/arch/arm/boot/zImage sdcard/boot
	cp ../../../kernel/rpi/arch/arm/boot/dts/bcm2710-rpi-3-b.dtb sdcard/boot
	cp ../../../kernel/rpi/arch/arm/boot/dts/bcm2709-rpi-2-b.dtb sdcard/boot
	cp ../../../kernel/rpi/arch/arm/boot/dts/bcm2710-rpi-cm3.dtb sdcard/boot
	mkdir -p sdcard/boot/overlays
	cp ../../../kernel/rpi/arch/arm/boot/dts/overlays/vc4-fkms-v3d.dtbo sdcard/boot/overlays
	cp ../../../kernel/rpi/arch/arm/boot/dts/overlays/vc4-kms-v3d.dtbo sdcard/boot/overlays
	cp ../../../out/target/product/rpi3/ramdisk.img sdcard/boot
	sync
	umount /dev/mapper/loop0p1
	kpartx -d "$IMGNAME".img
	sync
	echo "DONE"
fi

#!/bin/bash

# global program variables
DEVICE_LOCATION=""
DEVICE_ID=""
DEVICE_SIZE=""
DEVICE_PATH=""
PARTITION=false
PARTITION_NEEDED=false
USERDATA_FORMAT=false

# constants for the sdcard and partitions
SIZE_SD=4096  # minimum size of device in MB
SIZE_P1=512   # exact size of the partition 1 (boot) in MB
SIZE_P2=1024  # exact size of the partition 2 (system) in MB
SIZE_P3=512   # exact size of the partition 3 (cache) in MB
SIZE_P4=1024  # minimum size of the partition 4 (userdata) in MB

show_help()
{
cat << EOF
USAGE:
  $0 [-p] [-f] /dev/NAME
OPTIONS:
  -p    (Re-)partition the sdcard
  -f    Format userdata and cache
EOF
}

check_device()
{
    echo " * Checking the device in $DEVICE_LOCATION..."

    if [[ ! -n "$DEVICE_LOCATION" ]]; then
        echo "ERR: device location not specified (e.g. '-d /dev/sdc')"
        exit 1
    fi

    if [[ ! -b "$DEVICE_LOCATION" ]]; then
        echo "ERR: no block device was found in $DEVICE_LOCATION"
        exit 1
    fi

    # get the block device for size detection
    sudo lsblk
    dir /dev/disk/by-path/
    DEVICE_ID=`echo "$DEVICE_LOCATION" | sed -e "s/^\/dev\/sd\(.\)$/\1/g"` #regex : search for /dev/sd[a-z] and set DEVICE_ID = [a-z]

    echo " * Validating the device's size..."

    # DEVICE_SIZE [Sector] * 512 [Byte/Sector] / 1024 [Byte/KB] / 1024 [KB/MB] = SIZE [MB]
    DEVICE_SIZE=`cat /sys/block/sd"$DEVICE_ID"/size`
    DEV_SIZE_MB=$(($DEVICE_SIZE*512/1024/1024))
    if [[ $DEV_SIZE_MB -gt $SIZE_SD ]]; then
        echo "ERR: please use an sdcard with more than $SIZE_SD MB"
        exit 1
    fi
}

check_partition()
{
    if [[ "$PARTITION" ]]; then
        read -p "Are you sure you want to partition the device $DEVICE_LOCATION (all data will be lost)? [y/N]: " yn
        case $yn in
            [Yy]* ) perform_partition;;
            [Nn]* ) printf "Please check your parameter and try again.\n"; exit;; # abort
            "" ) printf "Please check your parameter and try again.\n"; exit;; # abort
            *) printf "Please answer with [y]es or [n]o.\n"; check_partition;;
        esac
    elif $PARTITION_NEEDED; then
        printf "The device is not partitioned in the correct way. Use \"-p\" to partition the device.\n"
        exit 1
    else
        echo "The device is correct patitionated."
    fi
}

perform_partition()
{
    echo " * Start partitioning..."
    local TEST=0

    # destroy the old partition table
    sudo dd if=/dev/zero of=$DEVICE_LOCATION bs=1024 count=1 conv=notrunc
    ((TEST+=$?))

    # re-read the partition table
    sudo partprobe $DEVICE_LOCATION

    # write new partition table
    printf "o\nw\n" | sudo fdisk $DEVICE_LOCATION
    ((TEST+=$?))

    # add partition 1 (512MB) -> boot
    printf "n\np\n1\n\n+${SIZE_P1}M\nw\n" | sudo fdisk $DEVICE_LOCATION
    ((TEST+=$?))

    # set it as bootable with partition type "W95 FAT32 (LBA)"
    printf "a\n1\nt\n1\nc\nw\n" | sudo fdisk $DEVICE_LOCATION
    ((TEST=$?))

    # add partition 2 (1024MB) -> system
    printf "n\np\n2\n\n+${SIZE_P2}M\nw\n" | sudo fdisk $DEVICE_LOCATION
    ((TEST+=$?))

    # add partition 3 (512MB) -> cache
    printf "n\np\n3\n\n+${SIZE_P3}M\nw\n" | sudo fdisk $DEVICE_LOCATION
    ((TEST+=$?))

    # add partition 4 (rest of disk) -> userdata
    printf "n\np\n3\n\n\nw\n" | sudo fdisk $DEVICE_LOCATION
    ((TEST=$?))

    # re-read the partition table
    sudo partprobe $DEVICE_LOCATION

    if [[ $TEST -gt 0 ]]; then
        echo "ERR: an error while partitioning occured."
        exit 1
    fi

    echo " * Validating the partition count..."
}


check_size()
{
    echo " * Validating partition sizes..."

    if [[ -b "/sys/block/sd${DEVICE_ID}/sd${DEVICE_ID}1" ]]; then
        local PARTITION1_SIZE=`cat "/sys/block/sd${DEVICE_ID}/sd${DEVICE_ID}1"`
    else
        PARTITION_NEEDED=true
    fi

    if [[ -b "/sys/block/sd${DEVICE_ID}/sd${DEVICE_ID}2" ]]; then
        local PARTITION2_SIZE=`cat "/sys/block/sd${DEVICE_ID}/sd${DEVICE_ID}2"`
    else
        PARTITION_NEEDED=true
    fi

    if [[ -b "/sys/block/sd${DEVICE_ID}/sd${DEVICE_ID}3" ]]; then
        local PARTITION3_SIZE=`cat "/sys/block/sd${DEVICE_ID}/sd${DEVICE_ID}3"`
    else
        PARTITION_NEEDED=true
    fi

    if [[ -b "/sys/block/sd${DEVICE_ID}/sd${DEVICE_ID}4" ]]; then
        local PARTITION4_SIZE=`cat "/sys/block/sd${DEVICE_ID}/sd${DEVICE_ID}4"`
    else
        PARTITION_NEEDED=true
    fi

    if [[
        $(($PARTITION1_SIZE*512/1024/1024)) -eq $SIZE_P1 &&
        $(($PARTITION2_SIZE*512/1024/1024)) -eq $SIZE_P2 &&
        $(($PARTITION3_SIZE*512/1024/1024)) -eq $SIZE_P3 &&
        $(($PARTITION4_SIZE*512/1024/1024)) -gt $SIZE_P4
        ]];
    then
        PARTITION_NEEDED=false
    else
        PARTITION_NEEDED=true
    fi

    PART_COUNT=`ls -al ${DEVICE_LOCATION}? | wc -l`
    echo " * Using sdcard in $DEVICE_LOCATION with $PART_COUNT"

    if [ "${PART_COUNT:-0}" -ne 4 ]; then
      echo "ERR: bad device in $DEVICE_LOCATION"
      exit 1
    fi
}

unmount_all()
{
    echo " * Unmounting mouted partitions..."

    sudo umount ${DEVICE_LOCATION}1 > /dev/null 2>&1
    sudo umount ${DEVICE_LOCATION}2 > /dev/null 2>&1
    sudo umount ${DEVICE_LOCATION}3 > /dev/null 2>&1
    sudo umount ${DEVICE_LOCATION}4 > /dev/null 2>&1
}

format_data()
{
    echo " * Formatting 'cache' and 'data'..."
    local TEST=0

    sudo mkfs.ext4 -L cache ${DEVICE_LOCATION}3
    ((TEST+=$?))

    sudo mkfs.ext4 -L userdata ${DEVICE_LOCATION}4
    ((TEST+=$?))

    if [[ $TEST -gt 0 ]]; then
        echo "ERR: an error occured while formatting data partitions."
        exit 1
    fi
}

format_system()
{
    echo " * Formatting 'boot' and 'system'..."
    local TEST=0

    sudo mkfs.vfat -n boot -F 32 ${DEVICE_LOCATION}1
    ((TEST+=$?))

    sudo mkfs.ext4 -L system ${DEVICE_LOCATION}2
    ((TEST+=$?))

    if [[ $TEST -gt 0 ]]; then
        echo "ERR: an error occured while formatting system partitions."
        exit 1
    fi
}

copy_files()
{
    BOOT_FILES="boot"
    SYSTEM_IMG="system.img"

    if [ ! -f $SYSTEM_IMG ]; then
        echo "ERR: system image not found!"
        exit 1
    fi

    echo " * Copying new system files..."
    DIR_NAME="/media/rpi-sd-boot"

    echo "   - mounting the boot partition to $DIR_NAME"
    sudo rm -rf $DIR_NAME > /dev/null 2>&1
    sudo mkdir -p $DIR_NAME
    sudo mount -t vfat -o rw ${DEVICE_LOCATION}1 $DIR_NAME

    echo "   - copying boot files"
    sudo cp $BOOT_FILES/* $DIR_NAME/

    echo "   - unmounting the boot partition"
    sudo umount $DIR_NAME
    sudo rm -rf $DIR_NAME

    echo "   - writing the system image"
    sudo dd if=$SYSTEM_IMG of=${DEVICE_LOCATION}2 bs=1M
}

# --------------------------------------
# Script entry point
# --------------------------------------

echo "Installation script for RPi started."
echo ""

# save the passed options
while getopts ":fp" flag; do
case $flag in
    "p") PARTITION=false ;;
    "f") USERDATA_FORMAT=true ;;
    *)
         echo "ERR: invalid option (-$flag $OPTARG)"
         echo ""
         show_help
         exit 1
esac
done

# what left after the parameters has to be the device
shift $(($OPTIND - 1))
DEVICE_LOCATION="$1" ;;

check_device
check_partition
check_format
check_size
unmount_all
format_data
format_system
copy_files

echo ""
echo "Installation successful. You can now put your sdcard in the RPi."

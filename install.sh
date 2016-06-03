#!/bin/bash

# global program variables
DEVICE_LOCATION=""
DEVICE_NAME=""
DEVICE_ID=""
DEVICE_SIZE=""
DEVICE_PATH=""
PARTITION=false
PARTITION_NEEDED=false
USERDATA_FORMAT=false

# constants for the sdcard and partitions
SIZE_P1=512   # exact size of the partition 1 (boot) in MB
SIZE_P2=1024  # exact size of the partition 2 (system) in MB
SIZE_P3=512   # exact size of the partition 3 (cache) in MB
SIZE_P4=1024  # minimum size of the partition 4 (userdata) in MB

show_help()
{
cat << EOF
USAGE:
  $0 [-f] [-h] [-p] /dev/NAME
OPTIONS:
  -f  Format userdata and cache
  -h  Show help
  -p  (Re-)partition the sdcard
EOF
}

check_device()
{
    echo " * Checking the device in $DEVICE_LOCATION..."

    if [[ -z "$DEVICE_LOCATION" ]]; then
        echo ""
        echo "ERR: device location not valid"
        exit 1
    fi

    if [[ ! -b "$DEVICE_LOCATION" ]]; then
        echo ""
        echo "ERR: no block device was found in $DEVICE_LOCATION"
        exit 1
    fi

    echo " * Validating the device's size..."

    DEVICE_NAME=${DEVICE_LOCATION##*/}
    SIZE_FILE="/sys/block/$DEVICE_NAME/size"
    DEVICE_SIZE_SECTORS=$(cat $SIZE_FILE)

    if [[ ! -f "$SIZE_FILE" ]]; then
        echo ""
        echo "ERR: can't detect the size of the sdcard"
    fi

    REQUIRED_SIZE_MB=$((SIZE_P1 + SIZE_P2 + SIZE_P3 + SIZE_P4))
    echo "  - minimum size: $REQUIRED_SIZE_MB MB"

    # DEVICE_SIZE [Sector] * 512 [Byte/Sector] / 1024 [Byte/KB] / 1024 [KB/MB] = SIZE [MB]
    DEVICE_SIZE_MB=$(($DEVICE_SIZE_SECTORS*512/1024/1024))
    echo "  - detected size: $DEVICE_SIZE_MB MB"

    if [[ $DEVICE_SIZE_MB -lt $REQUIRED_SIZE_MB ]]; then
        echo ""
        echo "ERR: please use an sdcard with more than $SIZE_SD MB"
        exit 1
    fi
}

check_partitions()
{
    PARTITION_COUNT=$(ls -al ${DEVICE_LOCATION}? | wc -l)
    echo " * Detected $PARTITION_COUNT partitions on $DEVICE_LOCATION"

    # allow less partitions if we are going to re-partition it anyways
    if [ "$PARTITION" = true ]; then
        echo " - ignoring this count due to upcoming partitioning"
        PARTITION_COUNT=4
    fi

    if [ "${PARTITION_COUNT:-0}" -ne 4 ]; then
        echo "ERR: bad device in $DEVICE_LOCATION"
        exit 1
    fi
}

check_sizes()
{
    echo " * Validating partition sizes..."

    PARTITION1_SIZE_SECTORS=$(cat "/sys/block/${DEVICE_NAME}/${DEVICE_NAME}1/size")
    PARTITION1_SIZE_MB=$(($PARTITION1_SIZE_SECTORS*512/1024/1024))
    echo "  - boot) available: $PARTITION1_SIZE_MB MB, required: $SIZE_P1 MB"

    if [[ $PARTITION1_SIZE_MB -lt $SIZE_P1 ]];
    then
        echo ""
        echo "ERR: the 'boot' partition doesn't provide enough space!"
        exit 1
    fi

    PARTITION2_SIZE_SECTORS=$(cat "/sys/block/${DEVICE_NAME}/${DEVICE_NAME}2/size")
    PARTITION2_SIZE_MB=$(($PARTITION2_SIZE_SECTORS*512/1024/1024))
    echo "  - system) available: $PARTITION2_SIZE_MB MB, required: $SIZE_P2 MB"

    if [[ $PARTITION2_SIZE_MB -lt $SIZE_P2 ]];
    then
        echo ""
        echo "ERR: the 'system' partition doesn't provide enough space!"
        exit 1
    fi

    PARTITION3_SIZE_SECTORS=$(cat "/sys/block/${DEVICE_NAME}/${DEVICE_NAME}3/size")
    PARTITION3_SIZE_MB=$(($PARTITION3_SIZE_SECTORS*512/1024/1024))
    echo "  - cache) available: $PARTITION3_SIZE_MB MB, required: $SIZE_P3 MB"

    if [[ $PARTITION3_SIZE_MB -lt $SIZE_P3 ]];
    then
        echo ""
        echo "ERR: the 'cache' partition doesn't provide enough space!"
        exit 1
    fi

    PARTITION4_SIZE_SECTORS=$(cat "/sys/block/${DEVICE_NAME}/${DEVICE_NAME}4/size")
    PARTITION4_SIZE_MB=$(($PARTITION4_SIZE_SECTORS*512/1024/1024))
    echo "  - data) available: $PARTITION4_SIZE_MB MB, required: $SIZE_P4 MB"

    if [[ $PARTITION4_SIZE_MB -lt $SIZE_P4 ]];
    then
        echo ""
        echo "ERR: the 'data' partition doesn't provide enough space!"
        exit 1
    fi
}

create_partitions()
{
    # no partitioning was requested
    if [ "$PARTITION" = false ]; then
        echo " * Skipping partitioning..."
        return
    fi

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
    # no partitioning was requested
    if [ "$USERDATA_FORMAT" = false ]; then
        echo " * Skipping data format..."
        return
    fi

    echo " * Formatting data partitions..."
    local TEST=0

    echo "  - formatting 'cache'"
    sudo mkfs.ext4 -L cache ${DEVICE_LOCATION}3
    ((TEST+=$?))

    echo "  - formatting 'userdata'"
    sudo mkfs.ext4 -L userdata ${DEVICE_LOCATION}4
    ((TEST+=$?))

    if [[ $TEST -gt 0 ]]; then
        echo "ERR: an error occured while formatting data partitions."
        exit 1
    fi
}

format_system()
{
    echo " * Formatting system partitions..."
    local TEST=0

    echo "  - formatting 'boot'"
    sudo mkfs.vfat -n boot -F 32 ${DEVICE_LOCATION}1
    ((TEST+=$?))

    echo "  - formatting 'system'"
    sudo mkfs.ext4 -L system ${DEVICE_LOCATION}2
    ((TEST+=$?))

    if [[ $TEST -gt 0 ]]; then
        echo "ERR: an error occured while formatting system partitions."
        exit 1
    fi
}

copy_files()
{
    BOOT_DIR="boot"
    if [ ! -d $BOOT_DIR ]; then
        echo "ERR: boot directory not found!"
        exit 1
    fi

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
    sudo cp $BOOT_DIR/* $DIR_NAME/

    echo "   - unmounting the boot partition"
    sudo umount $DIR_NAME
    sudo rm -rf $DIR_NAME

    echo "   - writing the system image"
    sudo dd if=$SYSTEM_IMG of=${DEVICE_LOCATION}2 bs=1M
}

# --------------------------------------
# Script entry point
# --------------------------------------

# save the passed options
while getopts ":fhp" flag; do
case $flag in
    "h") SHOW_HELP=true ;;
    "p") PARTITION=true ;;
    "f") USERDATA_FORMAT=true ;;
    *)
         echo ""
         echo "ERR: invalid option (-$flag $OPTARG)"
         echo ""
         show_help
         exit 1
esac
done

# don't do anything else
if [[ "$SHOW_HELP" = true ]]; then
    show_help
    exit
fi

# what left after the parameters has to be the device
shift $(($OPTIND - 1))
DEVICE_LOCATION="$1"

# no target provided
if [[ -z "$DEVICE_LOCATION" ]]; then
    echo ""
    echo "ERR: missing the path to the sdcard!"
    echo ""
    show_help
    exit
fi

echo "Installation script for RPi started."
echo "Target device: $DEVICE_LOCATION"
echo "Perform partitioning: $PARTITION"
echo "Perform formatting: $USERDATA_FORMAT"
echo ""

check_device
check_partitions
create_partitions
check_sizes
unmount_all
format_data
format_system
copy_files

echo ""
echo "Installation successful. You can now put your sdcard in the RPi."

#!/usr/bin/env bash

set -e

SCRIPT_NAME="resin-migrate-stage2"

MOUNT_DIR_ROOT="/tmp/orig-root"
MOUNT_DIR_DATA="/tmp/resin-data"
MOUNT_DIR_TMP="/tmp/resin-tmp"


RESIN_IMG_FILE="/opt/resin-image-genericx86-64.resinos-img.gz"
CORE_IMG_FILE="/opt/core.img"
# CORE_IMG_FILE="/mnt/boot/grub/core.img"
BOOT_IMG_FILE="/opt/boot.img"
# BOOT_IMG_FILE="/mnt/boot/grub/boot.img"

##########################################
# log functions
##########################################

function inform {
    echo "[${SCRIPT_NAME}] INFO: $1"
}

function warn {
    echo "[${SCRIPT_NAME}] WARN: $1"
}

function simulate {
    echo "[${SCRIPT_NAME}] INFO: would execute \"$*\""
}

##########################################
# fail : try to restore
##########################################

function clean {
    echo "[${SCRIPT_NAME}] INFO: cleanup"
    $UMOUNT ${MOUNT_DIR_DATA}
    $UMOUNT ${MOUNT_DIR_ROOT}
}

##########################################
# fail : try to resotore & reboot
##########################################

function fail {
    echo "[${SCRIPT_NAME}] ERROR: $1"
    clean
    # reboot
}


# stuff I do manually on stage2

# determine in stage 1 which is the temporary data partition and its sectors
# store this information on data partition

# SKIP_PREP="TRUE"

if [ ! -f ${RESIN_IMG_FILE} ] ; then
    fail "resin os image could not be found"
fi

if [ ! -f ${BOOT_IMG_FILE} ] ; then
    fail "boot image not found: ${MOUNT_DIR_DATA}/migrate.cfg"
fi

if [ ! -f ${CORE_IMG_FILE} ] ; then
    fail "core image not found: ${MOUNT_DIR_DATA}/migrate.cfg"
fi

mkdir -p ${MOUNT_DIR_DATA}
mount -L flash-data ${MOUNT_DIR_DATA} || fail "failed to mount resin data partition"

if [ -f ${MOUNT_DIR_DATA}/migrate.cfg ] ; then
    source ${MOUNT_DIR_DATA}/migrate.cfg || fail "failed to source ${MOUNT_DIR_DATA}/migrate.cfg"
else
    fail "config file not found: ${MOUNT_DIR_DATA}/migrate.cfg"
fi


# determine in stage 1 which is/are the original boot partition/s
inform "mounting resin-data"
mkdir -p ${MOUNT_DIR_ROOT}
mount /dev/sda1 ${MOUNT_DIR_ROOT} || fail "failed to mount original root partition"

inform "mounting original root"
# mkdir -p ${MOUNT_DIR_DATA}/backup
inform "creating backup"
# rsync -a ${MOUNT_DIR_ROOT}/etc ${MOUNT_DIR_DATA}/backup || fail "failed to backup data"

inform "unmounting drives"
# umount ${MOUNT_DIR_DATA}
umount ${MOUNT_DIR_ROOT}

# fail "deliberate exit"

inform "flashing resin os to ${DATA_PART_DEV}"
gunzip -c ${RESIN_IMG_FILE} | dd of=${DATA_PART_DEV} bs=4M
# rm -rf "$INTERNAL_DEVICE_BOOT_PART_MOUNTPOINT/EFI"

inform "flashing boot.img os to ${DATA_PART_DEV}"
dd if=${BOOT_IMG_FILE} of=${DATA_PART_DEV} conv=fdatasync bs=1
inform "flashing core.img os to ${DATA_PART_DEV}"
dd if=${CORE_IMG_FILE} of=${DATA_PART_DEV} conv=fdatasync bs=1 seek=512
sync

reboot

# inform "data partition: <${DATA_PART_DEV}>"

#inform "call parted ${DATA_PART_DEV} resizepart 4 ${DATA_PART_END}s"
#parted ${DATA_PART_DEV} resizepart 4 ${DATA_PART_END}s << EOT
#Yes
#I
#EOT
#inform "call parted -sm ${DATA_PART_DEV} mkpart logical ext4 ${DATA_PART_START}s ${DATA_PART_END}s"
#parted -sm ${DATA_PART_DEV} mkpart logical ext4 ${DATA_PART_START}s ${DATA_PART_END}s









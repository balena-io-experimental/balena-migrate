#!/bin/bash

# Sample backup script for balena-migrate
# Activate by adding to BACKUP_SCRIPT variable in balena-migrate.conf
# - The script will be called with the name of a backup archive, typically backup.tgz
# - If created, the backup archive will be transferred to the balena-data partition.
# - On first boot of balena-OS (Version >= 2.29.0) the supervisor checks for an existing backup archive
#   and pre-creates a volume for every top level directory found in the archive.
# - Volumes are only created if the volume / directory name is referenced from
#   an application container.
#

set -e

BACKUP_FILE=$1

################################################################################
# fail with error message, removing temp directory if it exists
################################################################################
function fail {
  echo "ERROR: $1"
  if [ -z "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] ; then
    rm -rf "$TEMP_DIR"
  fi
  exit 1
}

# check if backup file name is given
if [ -z "$BACKUP_FILE" ] ; then
  fail "no backup file given"
fi

# create a temporary directory in current dir to setup the backup in
TEMP_DIR=$(mktemp -d -p ./)

################################################################################
# variant 1 - link subdirectory into volume
################################################################################

VOLUME_NAME1="app-volume"
BACKUP_DIR1="/home/pi/dir-to-backup1"
VOLUME_DIR1="dir-in-volume1"


# create top level directory that will be mounted as volume
if [ -d "$BACKUP_DIR1" ] ; then
  TARGET_PATH="${TEMP_DIR}/${VOLUME_NAME1}"
  mkdir -p "${TARGET_PATH}"
  # create a symbolic link to the folder to be backed up in the volume directory
  echo "processing directory $BACKUP_DIR1"
  ln -s "$BACKUP_DIR1" "${TARGET_PATH}/${VOLUME_DIR1}"
else
  fail "directory $BACKUP_DIR1 could not be found"
fi

################################################################################
# variant 2 - link all files in subdirectory into volume
################################################################################

VOLUME_NAME2="app-volume"
BACKUP_DIR2="/home/pi/dir-to-backup2"
VOLUME_DIR2="dir-in-volume2"

if [ -d "$BACKUP_DIR2" ] ; then
  TARGET_PATH="${TEMP_DIR}/${VOLUME_NAME2}/${VOLUME_DIR2}"
  mkdir -p "${TARGET_PATH}"
  # get files in directory listed one per line
  FILES=$(ls -1 "$BACKUP_DIR2")
  IFS_BACKUP=$IFS
  IFS=$'\n'
  for file in $FILES
  do
    ln -s "$BACKUP_DIR2/$file" "${TARGET_PATH}/$file"
  done
  IFS=$IFS_BACKUP
else
  fail "directory $BACKUP_DIR2 could not be found"
fi

# create the gzipped tar archive
tar -hzcf "$BACKUP_FILE" -C "${TEMP_DIR}" . || fail "failed to create backup file $BACKUP_FILE"
# remove the temporary directory
rm -rf "${TEMP_DIR}"

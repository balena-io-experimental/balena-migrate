#!/bin/bash

# Sample backup script for balena-migrate
# Activate by adding to BACKUP_SCRIPT variable in balena-migrate.conf
# The script will be called with the name of a backup archive, typically backup.tgz
# If created, the backup archive will be transferred to the balena data partition.
# On first boot of balena-OS the supervisor checks for an existing backup archive
# and pre-creates a volume for every top level directory found in the archive.
# Volumes are only created if the volume / directory name is referenced from
# an application container.


set -e

BACKUP_FILE=$1


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

TEMP_DIR=$(mktemp -d -p ./)

################################################################################
# variant 1 - link subdirectory into volume
################################################################################
BACKUP_DIR1="/home/pi/dir-to-backup1"
VOLUME_NAME1="app-volume"
VOLUME_DIR1="dir-to-backup1"


# create top level directory that will be mounted as volume
if [ -d "$BACKUP_DIR1" ] ; then
  mkdir -p "${TEMP_DIR}/${VOLUME_NAME1}"
  # create a link to the folder to be backed up in the top level directory
  echo "processing directory $BACKUP_DIR1"
  ln -s "$BACKUP_DIR1" "${TEMP_DIR}/${VOLUME_NAME1}/${VOLUME_DIR1}"
else
  fail "directory $BACKUP_DIR1 could not be found"
fi

################################################################################
# variant 2 - link all files in subdirectory into volume
################################################################################
BACKUP_DIR2="/home/pi/dir-to-backup2"
VOLUME_NAME2="app-volume"

if [ -d "$BACKUP_DIR2" ] ; then
  mkdir -p "${TEMP_DIR}/${VOLUME_NAME2}"
  FILES=$(ls -1 "$BACKUP_DIR2")
  IFS_BACKUP=$IFS
  IFS=$'\n'
  for file in $FILES
  do
    ln -s "$BACKUP_DIR2/$file" "${TEMP_DIR}/${VOLUME_NAME2}/$file"
  done
  IFS=$IFS_BACKUP
else
  fail "directory $BACKUP_DIR2 could not be found"
fi

# create the gzipped tar archive
tar -hzcf "$BACKUP_FILE" -C "${TEMP_DIR}" ./ || fail "failed to create backup file $BACKUP_FILE"
# remove the temporary directory
rm -rf "${TEMP_DIR}"

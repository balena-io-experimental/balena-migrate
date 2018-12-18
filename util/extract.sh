#!/bin/bash

set -e

INPUT_IMG=
LOOP_DEV=
MNT_DIR=
TMP_DIR=
GRUB_FILE=
IMG_FILE=
BLOCK_SIZE=512

function fail {
  echo "${1}"
  clean
  exit 1
}

function printHelp {
  cat << EOI

  extract - extract balena OS image and grub config from balena OS flasher image
    USAGE extract [OPTIONS] <image-file>
    please run as root.
    OPTIONS:
      --grub <output grub file>              - output grub config to given path
      --grub-boot <output grub core imgage>  - output grub boot image to given path
      --grub-core <output grub core imgage>  - output grub core image to given path
      --balena-cfg <output config.json file> - output config.json to given path
      --config <output migrate config file>  - set variables corresponding to extracted files in migrate config
      --home <HOME_DIR used for migrate cfg> - use this directory as HOME_DIR for migrate config
      --img <output image file>              - output OS image to given path

EOI
  return  0
}

function clean {
  if [ -n "$LOOP_DEV" ] && [ -b "$LOOP_DEV" ] ; then
    # echo "removing $LOOP_DEV"
    umount $LOOP_DEV || true
    losetup -d $LOOP_DEV
    LOOP_DEV=
  fi

  if [ -n "$MNT_DIR" ] && [ -d "$MNT_DIR" ] ; then
    # echo "removing mount point $MNT_DIR"
    rmdir "$MNT_DIR"
  fi

  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] ; then
    # echo "removing temporary directory $TMP_DIR"
    rm -rf "$TMP_DIR"
  fi
}

function getCmdArgs {

  if [[ $# -eq 0 ]] ; then
    echo "no command line arguments."
    printHelp
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
      -h|--help)
          printHelp
          exit 0
          ;;
        --grub-boot)
          if [ -z "$2" ]; then
            fail "\"$1\" argument needs a value."
          fi
          GRUB_BOOT_IMG="$2"
          echo "using grub boot img output file $GRUB_BOOT_IMG"
          shift
          ;;
        --grub-core)
          if [ -z "$2" ]; then
            fail "\"$1\" argument needs a value."
          fi
          GRUB_CORE_IMG="$2"
          echo "using grub core img output file $GRUB_CORE_IMG"
          shift
          ;;
        --config)
          if [ -z "$2" ]; then
            fail "\"$1\" argument needs a value."
          fi
          MIGRATE_CONFIG="$2"
          echo "using migrate config file $MIGRATE_CONFIG"
          shift
          ;;
        --home)
          if [ -z "$2" ]; then
            fail "\"$1\" argument needs a value."
          fi
          HOME_DIR="$2"
          echo "using home dir $HOME_DIR"
          shift
          ;;
        --balena-cfg)
          if [ -z "$2" ]; then
            fail "\"$1\" argument needs a value."
          fi
          BALENA_CONFIG="$2"
          echo "using config.json output file $BALENA_CONFIG"
          shift
          ;;
        --grub)
          if [ -z "$2" ]; then
            fail "\"$1\" argument needs a value."
          fi
          GRUB_FILE="$2"
          echo "using grub output file $GRUB_FILE"
          shift
          ;;
        --img)
          if [ -z "$2" ]; then
            fail "\"$1\" argument needs a value."
          fi
          IMG_FILE="$2"
          echo "using image output file $IMG_FILE"
          shift
          ;;
        *)
          if [[ $1 =~ ^-.* ]] ; then
            echo "unknown option $1"
            printHelp
            exit 1
          fi

          INPUT_IMG="$1"
          echo "using input file: $INPUT_IMG"
          ;;
    esac
    shift
  done
}

function setConfig {
  CFG_FILE=$1
  CFG_NAME=$2
  CFG_VALUE=$3

  if [ ! -f "$CFG_FILE" ] ; then
    echo "file not found $CFG_FILE"
    return 1
  fi

  # TODO: make this work
  #local baseDir=$(dirname "$CFG_VALUE")
  #echo "is $HOME_DIR in ${baseDir}* ?"
  #if [[ $HOME_DIR == "${baseDir}*" ]] ; then
  #  CFG_VALUE=${baseDir#"$HOME_DIR"}/$(basename $CFG_VALUE)
  #  echo "setting path to $CFG_VALUE"
  #else
  #  echo "$CFG_VALUE is not in $HOME_DIR"
  #  return 1
  #fi

  if grep "^${CFG_NAME}=.*" "$CFG_FILE" ; then
    sed -i "s/^${CFG_NAME}=.*\$/${CFG_NAME}=${CFG_VALUE}/g" "$CFG_FILE" || return 1
  else
    echo "${CFG_NAME}=${CFG_VALUE}"  >> "$CFG_FILE" || return 1
  fi
  return 0
}

################################################################################
# main
################################################################################

getCmdArgs "$@"

if [[ $EUID -ne 0 ]]; then
  fail "Please run this script as root"
fi

if [ -z "$INPUT_IMG" ] ; then
  echo "ERROR: no input image file given."
  printHelp
  fail
fi

if [ ! -f "$INPUT_IMG" ] ; then
  echo "ERROR file not found $INPUT_IMG"
  printHelp
  fail
fi

if [ -z "$IMG_FILE" ] && [ -z "$GRUB_FILE" ] ; then
  echo "USAGE: extract [--grub=<grub output file>] [--img=<image output file>] <image-file>"
  fail "no output files specified, please use --img and/or --grub options to specify output files"
fi

if [ -n "$MIGRATE_CONFIG" ] && [ -z "$HOME_DIR" ] ; then
  HOME_DIR=$(dirname "${MIGRATE_CONFIG}")
  echo "using ${HOME_DIR} as HOME_DIR"
fi

FTYPE=$(file -b "$INPUT_IMG")

if [[ $FTYPE =~ ^Zip\ archive\ data.* ]]  ; then
  echo "file appears to be a zip archive, unzipping.."
  TMP_DIR=$(mktemp -d -p ./)
  unzip "$INPUT_IMG" -d "$TMP_DIR" || fail "failed to unzip $INPUT_IMG"
  INPUT_IMG="${TMP_DIR}/$(ls "$TMP_DIR")"
  echo "got ${INPUT_IMG}"
  FTYPE=$(file -b "$INPUT_IMG")
fi

if [[ ! $FTYPE =~ ^DOS/MBR\ boot\ sector.* ]]  ; then
  fail "cannot make sense of image file $INPUT_IMG - expecting an image file, got $FTYPE"
fi


if [[ ! "$INPUT_IMG" =~ ^[^\ ]+\.img$ ]] ; then
  fail "cannot make sense of image file $INPUT_IMG - expecting a single file that ends with .img"
fi

echo "processing image $INPUT_IMG"

while read -r line
do
  if [[ $line =~ ^1:([0-9]+)s:.* ]] ; then
    bootStart="${BASH_REMATCH[1]}"
    bootStart=$((bootStart*BLOCK_SIZE))
    # echo "got boot partition start offset $bootStart"
    continue
  fi

  if [[ $line =~ ^2:([0-9]+)s:.* ]] ; then
    rootStart="${BASH_REMATCH[1]}"
    rootStart=$((rootStart*BLOCK_SIZE))
    # echo "got root partition start offset $rootStart"
    break
  fi
done < <(parted -sm "$INPUT_IMG" unit s print)

MNT_DIR=$(mktemp -d -p ./)

if [ -n "$GRUB_FILE" ] || [ -n "$BALENA_CONFIG" ]  ||  [ -n "$GRUB_BOOT_IMG" ] ||  [ -n "$GRUB_CORE_IMG" ]; then
  # echo "attempting losetup --show -o $bootStart -f $INPUT_IMG"
  LOOP_DEV=$(losetup --show -o $bootStart -f "$INPUT_IMG") || fail "failed to loopmount boot partition"

  echo "boot partition attached to loop device $LOOP_DEV"

  echo "mounting boot"
  mount "$LOOP_DEV" "$MNT_DIR"


  if [ -n "$GRUB_FILE" ] ; then
    cp "${MNT_DIR}/grub.cfg_internal" "$GRUB_FILE" || fail "failed to copy grub config"
    echo "copied ${MNT_DIR}/grub.cfg_internal to $GRUB_FILE"
    if [ -n "$MIGRATE_CONFIG" ] && [ -f "$MIGRATE_CONFIG" ] ; then
      setConfig "$MIGRATE_CONFIG" GRUB_CFG "$GRUB_FILE"
    fi
  fi

  if [ -n "$BALENA_CONFIG" ] ; then
    if [ -f "${MNT_DIR}/config.json" ] ; then
      cp "${MNT_DIR}/config.json" "$BALENA_CONFIG"
      if [ -n "$MIGRATE_CONFIG" ] && [ -f "$MIGRATE_CONFIG" ] ; then
        setConfig "$MIGRATE_CONFIG" BALENA_CONFIG "$BALENA_CONFIG"
      fi
    else
      fail "cannot find config.json in flasher boot partition"
    fi
  fi

  if [ -n "$GRUB_BOOT_IMG" ] ; then
    if [ -f "${MNT_DIR}/grub/boot.img" ] ; then
      cp "${MNT_DIR}/grub/boot.img" "$GRUB_BOOT_IMG"
      if [ -n "$MIGRATE_CONFIG" ] && [ -f "$MIGRATE_CONFIG" ] ; then
        setConfig "$MIGRATE_CONFIG" GRUB_BOOT_IMG "$GRUB_BOOT_IMG"
      fi
    else
      fail "cannot find grub/boot.img in flasher boot partition"
    fi
  fi

  if [ -n "$GRUB_CORE_IMG" ] ; then
    if [ -f "${MNT_DIR}/grub/core.img" ] ; then
      cp "${MNT_DIR}/grub/core.img" "$GRUB_CORE_IMG"
      if [ -n "$MIGRATE_CONFIG" ] && [ -f "$MIGRATE_CONFIG" ] ; then
        setConfig "$MIGRATE_CONFIG" GRUB_CORE_IMG "$GRUB_CORE_IMG"
      fi
    else
      fail "cannot find grub/core.img in flasher boot partition"
    fi
  fi

  sleep 1 # otherwise mount dir might still be busy...
  umount "$MNT_DIR" || fail "failed to unmount boot partition"
  losetup -d "$LOOP_DEV" || fail "failed to unmount loop device"
  LOOP_DEV=
fi

if [ -n "$IMG_FILE" ] ; then
  # echo "attempting losetup --show -o $rootStart -f $INPUT_IMG"
  LOOP_DEV=$(losetup --show -o $rootStart -f "$INPUT_IMG") || fail "failed to loopmount boot partition"

  echo "root-A partition attached to loop device $LOOP_DEV"

  echo "mounting root-A"
  mount "$LOOP_DEV" "$MNT_DIR"

  echo "attempting <ls \"${MNT_DIR}/opt/resin-image-genericx86*.resinos-img\">"
  # shellcheck disable=SC2086
  RAW_IMG_FILE=$(ls ${MNT_DIR}/opt/resin-image-genericx86*.resinos-img)

  if [ -n "$RAW_IMG_FILE" ] ; then
    echo "found image file: $RAW_IMG_FILE"
    gzip -c "${RAW_IMG_FILE}" > "$IMG_FILE" || fail "failed to copy image file"
  else
    fail "no image file found in flasher image"
  fi

  echo "gzipped ${MNT_DIR}/opt/resin-image-genericx86-64.resinos-img to $IMG_FILE"
  sleep 1 # otherwise mount dir might still be busy...

  umount "$MNT_DIR" || fail "failed to unmount root-A partition"
  losetup -d "$LOOP_DEV" || fail "failed to unmount loop device"
  LOOP_DEV=

  if [ -n "$MIGRATE_CONFIG" ] && [ -f "$MIGRATE_CONFIG" ] ; then
    setConfig "$MIGRATE_CONFIG" IMAGE_NAME "$IMG_FILE"
  fi
fi

if [ -n "$MIGRATE_CONFIG" ] && [ ! -f "$MIGRATE_CONFIG" ]; then
    echo "creating migrate config file $MIGRATE_CONFIG"
    cat <<EOI > "${MIGRATE_CONFIG}"
IMAGE_NAME=$IMG_FILE
DEBUG="TRUE"
BACKUP_SCRIPT=
BACKUP_DIRECTORIES=
NO_FLASH=TRUE
NO_SETUP= # "TRUE"
DO_REBOOT= # "TRUE"

LOG_DRIVE=  # /dev/sdb1
LOG_FS_TYPE=  # ext4

HAS_WIFI_CFG="FALSE"
MIGRATE_ALL_WIFIS="FALSE"
MIGRATE_WIFI_CFG= # "migrate-wifis" # file with a list of wifi networks to migrate, one per line
BALENA_WIFI=  # "TRUE"

BALENA_CONFIG=$BALENA_CONFIG

GRUB_CFG=$GRUB_FILE
GRUB_BOOT_IMG=$GRUB_BOOT_IMG
GRUB_CORE_IMG=$GRUB_CORE_IMG
EOI
fi

clean

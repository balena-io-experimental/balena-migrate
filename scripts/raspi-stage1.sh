#!/usr/bin/env bash

# create a list of required tools
# determine and copy all libs needed by tools



set -e

TOOLS_REQUIRED="ls dd mount umount parted reboot shutdown fuser systemctl grep dbus-daemon dbus-cleanup-sockets \
dbus-monitor dbus-send dbus-uuidgen dbus-daemon dbus-run-session dbus-update-activation-environment wpa_supplicant \
dnsmasq dhclient rsyslogd agetty systemd-logind systemd-udevd systemd-journal hciattach hciconfig hcitool expr kill \
sshd init sh bash whereis df"

NO_STOP_SERVICES="dbus dnsmasq getty@tty1 hciuart ssh systemd-journald systemd-logind systemd-udevd user@1000 rsyslog"
NO_RELOAD_SERVICES="rsyslog systemd-journald systemd-logind systemd-udevd getty@tty1 hciuart"
# "rsyslogd dbus dnsmasq" # NO_RELOAD instead ?
MEM_MIN_AVAIL=600000
MEM_TMPFS_SIZE=512000000

MIGRATEFS_MOUNT_POINT="/tmp/migrateFs"



SCRIPT_NAME="raspi-migrate-stage1"

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

# TODO: plenty - try to restore swap
# delete partitions in CREATED_PARTITIONS
# then use layout file created earlier with parted -sm /dev/?? unit s print to recreate

function clean {
    echo "[${SCRIPT_NAME}] INFO: cleanup"
    $UMOUNT ${MOUNT_DIR1}
    $UMOUNT ${MOUNT_DIR2}
    if [ -f ./tmp.img ] ; then
        rm ./tmp.img
    fi
}

##########################################
# fail : try to resotore & reboot
##########################################

function fail {
    echo "[${SCRIPT_NAME}] ERROR: $1"
    clean
    # reboot
    exit -1
}

##########################################
# check if list contains string
##########################################
# careful how you call it, should be
# eg.: listContains "$SUPPORTED_OSTYPES" $OSTYPE
function listContains {
    for CURR in $1
    do
        if [ "$2" == "$CURR" ]; then
            return 0
        fi
    done
    return -1
}

##########################################
# stopServices: stop running services
# except for those listed in
# NO_STOP_SERVICES
##########################################

function stopServices {

    while read line ;
    do
        local parts=(${line})
        # inform "looking at service: ${parts[0]}"
        local service=$(expr match "${parts[0]}" '\([^\.]\+\).service')

        if ! listContains "${NO_STOP_SERVICES}" "${service}" ; then
            inform "stop service ${service}"
            systemctl stop ${parts[0]} || fail "failed to stop service ${parts[0]}"
        fi

    done < <(systemctl | grep -e "\.service.*running")
}

##########################################
# restartServices: restart all running
# services except for those listed in
# NO_RELOAD_SERVICES
##########################################

function restartServices {

    while read line ;
    do
        local parts=(${line})
        local service=$(expr match "${parts[0]}" '\([^\.]\+\).service')

        if ! listContains "${NO_RELOAD_SERVICES}" "${service}" ; then
            inform "reloading service ${service}"
            systemctl restart ${parts[0]} || warn "failed to reload service ${parts[0]}"
            inform "done restarting service ${service}"
        fi

    done < <(systemctl | grep -e "\.service.*running")
}

##########################################
# where find path to executable
##########################################

function where {
    path=($(whereis -b $1))
    echo "${path[1]}"
}


##########################################
# copyPgm copy program and libraries required
##########################################

function copyPgm {
    pgmName=$1

    if [ -z "${2}" ] ; then
        target=${target}
    else
        target=$2
    fi

    pgmPath=$(where ${pgmName}) || fail "required program not found ${pgmName}"
    if [ -z "$pgmPath" ] ; then
        return 0
    fi

    inform "copying pgm name: ${pgmName} : ${pgmPath}"

    dirPath=$(dirname ${pgmPath})


    if [ ! -z "${dirPath}" ] && [ ! -d dirPath ] ; then
        local tgtPath="${target}${dirPath}"
        mkdir -p ${tgtPath}
    fi

    cp ${pgmPath}  ${tgtPath}/

    while read line ;
    do
        # inform "process: $line"

        if [[ $line =~ ^linux-vdso.*$ ]] ; then
            continue
        fi

        if [[ $line =~ ^.*\ =\>\ .*$ ]] ; then
            local tmp=$(expr match "${line}" '.* => \(.*\)')
        else
            local tmp=${line}
        fi

        # inform "tmp: ${tmp}"
        parts=(${tmp})

        libPath=${parts[0]}

        # inform "attempting to copy ${libPath}"
        dirPath=$(dirname ${libPath})
        if [ ! -z "${dirPath}" ] && [ ! -d dirPath ] ; then
            tgtPath="${target}${dirPath}"
            mkdir -p ${tgtPath}
        fi

        if [ ! -f "${target}${libPath}" ] ; then
            cp ${libPath}  ${tgtPath}/
            inform "${libPath} copied to ${tgtPath}/"
        fi

    done < <(ldd ${pgmPath})
}


##########################################
# main:
##########################################

stopServices

swapoff -a || fail "failed to disable swap"

MEM_INFO=($(free | grep "Mem:")) || fail "failed to retrieve free mem"
inform "mem available: ${MEM_INFO[6]}"
if (( ${MEM_INFO[6]} < $MEM_MIN_AVAIL )) ; then
    fail "not enough memory available for tmpfs"
fi

umount -a || true

mkdir -p ${MIGRATEFS_MOUNT_POINT} || fail "failed to create mount directory in ${MIGRATEFS_MOUNT_POINT}"
if [ ! -d ${MIGRATEFS_MOUNT_POINT} ] ; then
     fail "failed to create mount directory in ${MIGRATEFS_MOUNT_POINT}"
fi

mount -t tmpfs -o size=${MEM_TMPFS_SIZE} tmpfs ${MIGRATEFS_MOUNT_POINT} || fail "failed to create migration tmpfs"

inform "mounted tmpfs on ${MIGRATEFS_MOUNT_POINT}"

mkdir ${MIGRATEFS_MOUNT_POINT}/{proc,sys,dev,run,usr,var,tmp,oldroot}
cp -ax /{etc,mnt} ${MIGRATEFS_MOUNT_POINT}/ || fail "failed to copy /etc /mnt /lib/systemd"


for pgmName in ${TOOLS_REQUIRED}
do
    copyPgm ${pgmName} ${MIGRATEFS_MOUNT_POINT}
done
# cp -ax /usr/bin ${MIGRATEFS_MOUNT_POINT}/usr/ || fail "failed to copy /usr "
cp -ax /var/{log,local,lock,run,tmp} ${MIGRATEFS_MOUNT_POINT}/var/ || fail "failed to copy /var to  "

mkdir -p ${MIGRATEFS_MOUNT_POINT}//usr/share/dbus-1
cp -rax /usr/share/dbus-1/* ${MIGRATEFS_MOUNT_POINT}/usr/share/dbus-1/
cp -rax /lib/systemd/* ${MIGRATEFS_MOUNT_POINT}/lib/systemd/

inform "copied vital components, unmounting file systems"


MEM_INFO=($(free | grep "Mem:")) || fail "failed to retrieve free mem"
inform "mem available: ${MEM_INFO[6]}"

cd ${MIGRATEFS_MOUNT_POINT}
mount --make-rprivate / # necessary for pivot_root to work
inform "changing to new root"
pivot_root ${MIGRATEFS_MOUNT_POINT} ${MIGRATEFS_MOUNT_POINT}/oldroot

inform "remounting dev, proc, sys, run"
for i in dev proc sys run; do mount --move /oldroot/$i /$i; done

restartServices

systemctl daemon-reexec  || fail "failed to restart systemctl deamon"

fuser -vm /oldroot

inform "all done"
# reboot -f

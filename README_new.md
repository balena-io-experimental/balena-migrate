# Project Migration

**THIS IS WORK IN PROGRESS CODE** Project is not expected to reliably work yet.

This project attempts to create a unified approach to migrate a range of different device types and a linux operaring 
systems to resinOS.

# Strategy


The migration is performed in two stages. The first stage ensures that all requirements are met. 
The stage 1 script will create a configuration file in ```/etc/balena-migration-stage2.conf``` that will determine 
the actions and required files for initramfs creation as well as for stage 2. 

The stage 1 script then creates an initramfs file that contains all scripts programms and configuration files needed for 
phase 2.
The stage 1 script will also perform migration task such as creating a backup and migrating network (WIFI) configurations
that will be transferred to (resin-data) or installed in resinOS (mainly resin-boot/system-connections). The backup files 
files as well as the actual resinOS image file are often too big to be contained in the root partition 
where the initramfs resides and will be copied from the root file system to initramfs in stage 2.     
  
The stage 1 script will then reconfigure the booloader of system to use the created initramfs and optionally reboot. On 
systems using grub as bootloader the system is configured to have one shot at the modified boot configuration using 
grub-reboot. On RPI the /boot/config.txt and cmdline.txt files are modified.   
 

When booted from the newly created initramfs the contained scripts will attempt to store all required files inside the 
tmpfs that the initram system is mounted on. The configuration created in stage 1 (/etc/balena-migrate-stage2.conf) contains 
instructions on which files to transfer to the tmpfs.

Any failures up to this point can be tolerated by resetting the boot configuration to the prior state. In grub based 
boot loaders this is achieved automatically for RPI devices the /boot/config.txt and /boot/cmdline.txt files have to be restored 
to their prior state and the systems should be able to reboot into its former configuration.      
 
When all files are secured the stage2 scripts will unmount the former root file system and flash the configured resinOS 
image to the target device. After flashing, the script will trigger a reread of the devices partition information and attempt
to mount resin-boot and resin-data to transfer files.

A raspberry PI device the can be rebooted after this step as the resinOS image contains all information necessarry to 
reboot the system. 

On Intel based devices the stage 2 script will attempt to create a new boot loader configuration by copying a new 
grub.cfg to the resin-boot partition and by calling grub-install on the boot device. Alternatively boot loader images 
could be provided or contained in the resinOS image.      
            

# Migration Stage 1 
The script ```balena-stage1``` will check the prerequisites for migration before it attempts to modify the system. 
  
The main script contains a list of supported operation systems and hardware platforms that it has been tested on. 
It will reject any OS or hardware not contained in that list. The idea is to add further architectures and OS'ses and 
OS versions  only after they have been tested.   

## Prerequisites

### Environment

The stage 1 scripts expects the boot configuration to be available under ```/boot```. It expects the ```/boot``` directory 
to be on the same partition as the root file system and will fail if this is not the case. 

### Currently accepted Platforms

OS version extracted from ```/etc/os-release```:
* ubuntu-14.04
* raspian-9

Architectures taken from  ```uname -m```:

| uname tag  | Architecture |  |
| ------------- |:-------------|:--------|
| armv7l | arm v7  | distinguish RPI's / other devices by analysing ```/proc/cpuinfo``` , expect image tagged appropriately with with 'raspberrypi1', 'raspberrypi2', 'raspberrypi3' |
| x86_64 | intel 64 bit systems | expect image tagged with 'genericx86-64' | 
| i686 | intel 32 bit systems | expect image tagged with 'intel-core2-32' |


### required Programs
The stage 1 script will also make sure, that all the software required 
to perform the migration is available.  
Required software depends on the architecture and OS and includes the following:

| Program  | Architecture | Version |
| ------------- |:-------------:|--------:|
| **stage 1** |
| lsblk      | all | unspecified |
| readlink      | all      | unspecified | 
| sed | all      | unspecified | 
| mkinitramfs | all | unspecified |
| **stage 2** |
| dd | all | unspecified |
| gzip | all | unspecified | 
| partprobe | all | unspecified | 
| udevadm | all | unspecified |
| grub-install | x86_64, i686 | v2 | 
| busybox | x86_64, i686 | unspecified |
 

## Configuration

The main script ```balena-stage1``` uses a configuration file in ```/etc/balena-migrate.conf``` to read its configuration 
from. 

Valid settings for this file are:

### STRATEGY

**Default:** ```STRATEGY="DEFAULT"```

This is an experimental setting and is likely to be removed in the near future. The alternate strategy is RESIZE. It 
not fully implemented.
 
### HOME_DIR
 
**Default:** ```HOME_DIR=./```

The working directory of the migration script and the location where it exprects to find initramfs setup and image files. 
The default is to use the current working directory. 
   
### DO_REBOOT
**Default:** ```DO_REBOOT=```

When this variable is set to ```"TRUE"``` the script will reboot the computer after finishing successfully. It will display 
a warning and reboot after 5 seconds. By default tthis option is disabled and the device has to be rebooted manually.

### IMAGE_NAME

This option has to be specified. It specifies the resinOS image that will be flashed to the devices boot device. 
The script will fail if the file is not specified or does not exist. The script also expects the file to reference the 
detected architecture as follows:
 
   

**Example:** ```IMAGE_NAME="resin-raspberrypi3-2.15.1+rev2-dev-v7.16.6.img.gz"```

 


```bash 
####################################################################
# strategy
# DEFAULT: copy os image & backup to initramfs, unmount root, reflash drive,
#          partprobe and mount resin-data to copy backup, reboot
# RESIZE:  unfinished - resize root file system & partition in local-premount
#          use the space to store balenaOS image & backup
####################################################################
STRATEGY="DEFAULT"
# where everything is
# TODO: establish & use an absolute path to a set home directory that is not
#       necessarily PWD
HOME_DIR=./
# reboot automatically after script has finished by setting to "TRUE"
DO_REBOOT= # "TRUE"
# name of the balenaOS image to flash (expected in $HOMEDIR)
IMAGE_NAME="resin-image-genericx86-64.resinos-img.gz"
# IMAGE_NAME="resin-resintest-raspberrypi3-2.15.1+rev2-dev-v7.16.6.img.gz"

# switch on initramfs / kernel debug mode by seting to "TRUE"
DEBUG= # "TRUE"

# name of backup file to create/transfer to balena-data
BACKUP_FILE=backup.tgz
# TODO: customer defined backup script to call
BACKUP_SCRIPT=
BACKUP_DIRECTORIES="/etc"

# Grub boot devices
GRUB_BOOT_DEV="hd0,msdos1"
GRUB_BOOT_TYPE="legacy"

# DEBUG end initramfs scripts before unmounting root / flashing the image
NO_FLASH= #"TRUE"
ERROR_EXIT= # "reboot -f"

# DEBUG: do not modify config.txt, cmdline.txt, grub config if set to "TRUE"
NO_SETUP= #{ }"TRUE"
# create initramfs in contrast to using an initramfs supplied
MK_INITRAMFS="TRUE"
# name of initramfs to be created/used expected in $HOMEDIR
INITRAMFS_NAME="balena-migrate-initramfs-$(uname -r)"
# DEBUG verbose build process
MK_INITRAM_VERBOSE= # "TRUE"
# DEBUG keep initramfs layout
MK_INITRAM_RETAIN= # "TRUE"

# attempt to mount and log initramfs logs to external drive if set
LOG_DRIVE=/dev/sdb1
LOG_FS_TYPE=ext4

HAS_WIFI_CFG="FALSE" # set to "TRUE" if a wifi config is provided in image
MIGRATE_ALL_WIFIS="FALSE" # migrate all wifis if set to "TRUE"
MIGRATE_WIFI_CFG="migrate-wifis" # file with a list of wifi networks to migrate, one per line
```      


Prerequisites:


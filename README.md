# BalenaOS Migration

**THIS IS WORK IN PROGRESS CODE** Project is not expected to work yet.

This project attempts to provide a generic solution to migrate a range
of different device types running linux operating systems to balenaOS.

## Strategy

The migration is performed in two stages:

### Stage 1

The first stage ensures that all requirements are met. It uses a config
file in */etc/balena-migrate.conf* to override some of the default
settings in balena-stage1. This config file **must** contain the name of
the image to be flashed.

The defaults are rather conservative so the script will not actually
flash the image but just create an initramfs and configure it to boot.
It will will not overwrite the boot device when booted from in the
default configuration.

The stage 1 script will create a configuration file in
*/etc/balena-migration-stage2.conf* that will determine the actions and
required files during initramfs creation as well as for stage 2 that is
run from inside initramfs.

The stage 1 script then creates an initramfs file that contains all
scripts, programs and configuration files needed for phase 2.

The stage 1 script will also perform migration tasks such as creating a
backup (that will be transferred to resin-data) and migrating network
(WIFI) configurations to be installed in balenaOS
(resin-boot/system-connections). The backup files files as well as the
actual balenaOS image file are likely too big to be contained in the
root partition where the

initramfs resides and will be copied from the root file system to
initramfs in stage 2.

The stage 1 script will reconfigure the bootloader of the system to use
the created initramfs and optionally reboot the system. On systems using
grub as bootloader the system is configured to have one shot at the
modified boot configuration using grub-reboot. On RPI the
*/boot/config.txt* and */boot/cmdline.txt* files are modified.

### Stage 2

When booted from the newly created initramfs the contained stage 2
scripts will attempt to store all required files inside the tmpfs that
the initram system is mounted on. The configuration created in stage 1
(*/etc/balena-migrate-stage2.conf*)

contains instructions on which files to transfer to the tmpfs.

Any failures up to this point can be tolerated by resetting the boot
configuration to the prior state. In grub based boot loaders this is
achieved automatically, for RPI devices the */boot/config.txt* and
*/boot/cmdline.txt* files have to be restored to their prior state and
the systems should be able to reboot into its former configuration. This
is done by the stage 2 script as soon as it is started.

After all files have been secured, the stage 2 scripts will unmount the
former root file system and flash the configured balenaOS image to the
target device. After flashing, the script will trigger a reread of the
devices partition information and attempt to mount resin-boot and
resin-data to transfer files to.

A raspberry PI device can be rebooted after this step as the balenaOS
image contains all information necessary to reboot the system.

On Intel based devices the stage 2 script will attempt to create a new
boot loader configuration by copying a new *grub.cfg* to the resin-boot
partition and then calling grub-install on the boot device.

Alternatively boot loader images can be provided and flashed or
contained in the balenaOS image. This strategy is not yet supported
though.

## Supported Platforms

So far the scripts are being tested and are working on the following
platforms:

-   Raspberry PI 2 on Raspian-9
-   Raspberry PI 3 on Raspian-9
-   Virtualbox x86\_64 systems running ubuntu 14.04 and 18.04 in grub
    legacy mode.
-   The STEM device - 32 intel running Ubuntu 14.04 in grub legacy mode


## TODOS

Work is in progress on following platforms:

-   Intel UEFI devices (testing on intel nuc)
-   Raspberry PI running NOOBS

-   The migrate scripts currently do not inject a config.json into
    balenaOS. This can easily be added.
-   Currently the stage 2 script does not check if the files copied to
    tmpfs will actually fit. Stage 1 should estimate the memory needed
    to store all files and warn if it exceeds the available memory.
-   Migrate other than wifi settings eg. GSM modem settings.

## Migration Stage 1 in Detail

The script *balena-stage1* will check the prerequisites for migration
before it attempts to modify the system.

The script can be located anywhere. It reads the file
*/etc/balena-migration.conf* to retrieve its configuration. Part of the
configuration is a *HOME\_DIR* variable that points to the directory
where all other files are expected to be found. The default setting for
*HOME\_DIR* is *./* so the files are expected to be found in the
directory *balena-stage1* was executed in.

The script contains a list of supported operating systems and hardware
platforms that it has been tested on. It will reject any OS or hardware
not contained in that list.

The idea is to add further architectures, OS'ses and OS versions only
after they have been tested.

### Prerequisites

#### Environment

The stage 1 scripts expects the boot configuration to be available under
*/boot*. It expects the */boot* directory to be on the same hard drive
as the root file system and will fail with an error message if this is
not the case.

To create the initramfs *balena-stage1* uses its own initramfs-tools
directory (default is */etc/initramfs-tools*) which is expected to be
located in *HOME\_DIR*. This directory contains an initramfs config file
and several scripts that either help create the initramfs or are
executed from within the initramfs when it is booted from.

The following are the relevant files in *HOME\_DIR/initramfs-tools*:

-   *initramfs.cfg* - the initramfs config file.
-   hooks/balena-init - this script copies programs & files to the
    initramfs at creation time.
-   *scripts/balena-common* - this script contains some helper functions
    used from other scripts during initramfs boot.
-   *scripts/local-premount/balena-stage2-premount* - this script
    performs root fs resizing & repartitioning when strategy RESIZE is
    used. It is not currently being used.
-   *scripts/local-bottom/balena-stage2-default* - this is the main boot
    time script when using DEFAULT strategy.
-   *scripts/local-bottom/balena-stage2-resized* - this is the main boot
    time script when using RESIZE strategy. It is not currently being
    used.

#### Currently accepted Platforms

OS version extracted from */etc/os-release*:

-   ubuntu-18.04
-   ubuntu-14.04
-   raspian-9

Architectures taken from *uname -m*:


  |**uname tag**   |**Architecture**       |**Action Taken**|
  |---------------| ----------------------| ----------------------------------------------------------------|
  | armv7l          |arm v7                 |distinguish RPI's / other devices by analysing */proc/cpuinfo* |
  |  x86\_64         |intel 64 bit systems||   
  |i686            |intel 32 bit systems||



#### Required Programs

The stage 1 script will also make sure, that all the software required
to perform the migration is available. Required software depends on the
architecture and OS and includes the following:

  |**Program**|   **Architecture**|          **Version**|
  |--------------| -------------------------| -------------|
  |Stage 1 ||                                  
  |tar            |all                       |unspecified|
  |findmnt        |all                       |unspecified|
  |parted         |all                       |unspecified|
  |lsblk          |all                       |unspecified|
  |blkid          |x86\_64, i686 with UEFI   |unspecified|
  |readlink       |all                       |unspecified|
  |sed            |all                       |unspecified|
  |mkinitramfs    |all                       |unspecified|
  |grub-update    |x86\_64, i686             |V2|
  |Stage 2|||                                  
  |mount          |all                       |unspecified|
  |dd             |all                       |unspecified|
  |gzip           |all                       |unspecified|
  |partprobe      |all                       |unspecified|
  |udevadm        |all                       |unspecified|
  |grub-install   |x86\_64, i686             |V2|
  |busybox        |x86\_64, i686             |unspecified|




### Configuration

The script *balena-stage1* uses a configuration file in
*/etc/balena-migrate.conf* to read its configuration from.

Valid settings for this file are:

#### STRATEGY

**Default:** *STRATEGY="DEFAULT"*

The variable determines the strategy used by the stage 2 script. Only
the *DEFAULT* strategy is actually working and tested. The alternate
strategy *RESIZE* will attempt to resize the root

File system- and partition before it is mounted and use the freed space
to create a new partition and save data there. The strategy will likely
be abandoned.

#### HOME\_DIR

**Default:** *HOME\_DIR=./*

The working directory of the migration script and the location where it
expects to find initramfs setup and image files. The default is to use
the current working directory.

#### NO\_FLASH

**Default:** *NO\_FLASH=TRUE*

When this variable is set to *TRUE* the script will proceed normally but
will terminate at the point in stage 2 where the mounted root file
system would be unmounted and the balenaOS image would be flashed to the
device. How to terminate is determined by the value of the variable
*TERM\_EXIT*.

#### TERM\_EXIT

**Default:** *TERM\_EXIT="exit 0"*

Determines how to exit when the script terminates prematurely. Default
is *“exit 0”* in which case the boot process is continued normally.
Alternative is *“reboot -f”* to force a reboot. If the boot
configuration has not been reset the later can leed to a boot loop.

#### NO\_SETUP

Default: *NO\_SETUP=*

When this variable is set to *TRUE* the script does not attempt to
modify the boot configuration. It will check the prerequisites create an
initramfs but not create any disruptive configuration changes.

#### DO\_REBOOT

**Default:** *DO\_REBOOT=*

When this variable is set to *TRUE* the *balena-stage1* script will
reboot the computer after finishing successfully. It will display a
warning and reboot after 5 seconds. By default this option is disabled
and the device has to be rebooted manually when stage 1 has terminated.

#### IMAGE\_NAME

This option has to be specified. It specifies the balenaOS image that
will be flashed to the devices boot device. The script will fail if the
file is not specified or does not exist.

The script currently expects the image to be in gzipped format.

The script expects the file to be tagged with the target platform as
follows:


  |**Platform**    |**Image tag**|
  |--------------- |----------------|
  |  Raspberry PI1|   raspberry-pi1|
  |Raspberry PI2   |raspberry-pi2|
  |Raspberry PI3   |raspberrypi3|
  |x86\_64         |genericx86-64|
  |i686            |intel-core2-32|


**Example:**
*IMAGE\_NAME="resin-raspberrypi3-2.15.1+rev2-dev-v7.16.6.img.gz*"

\

#### DEBUG

**Default:** *DEBUG=*

Sets the debug flag in the kernel command line if set to *TRUE*. If this
setting is enabled the initramfs log can be found in
*/run/initramfs/initramfs.debug*.

[]{#anchor-24}LOG\_DRIVE , LOG\_FS\_TYPE

**Default:** *LOG\_DRIVE=*

Specifies a separate device to receive log files written during stage 2.
The device **must** be separate from the installation device (hard
drive) to be able to survive flashing of the balenaOS image. Use a
separate hard disk or a USB stick.

**Example:**

*LOG\_DRIVE=/dev/sdb1*

*LOG\_FS\_TYPE=ext4*

#### BACKUP\_FILE, BACKUP\_SCRIPT, BACKUP\_DIRECTORIES

**Default:**

*BACKUP\_FILE=backup.tgz*

*BACKUP\_SCRIPT=*

*BACKUP\_DIRECTORIES="/etc"*

Define how to backup the system. This part of the script is unfinished.
The above default configuration will create a backup using

*tar -czf \$HOME\_DIR/\$BACKUP\_FILE \$BACKUP\_DIRECTORIES*

thus backup the contents of all files in the directories specified in
*BACKUP\_DIRECTORIES.*

The alternative would be to specify a backup script in *BACKUP\_SCRIPT*
that will create the backup file.

This will be processed by *balena-stage1* so it is not critical and can
easily be tested.

The file specified in *BACKUP\_FILE* will be copied to the *resin-data*
partition in stage 2.


#### GRUB\_BOOT\_DEV

**Default:** *GRUB\_BOOT\_DEV=hd0*

The variable supplies a hint to which grub device to use for boot. The
stage 1 script will attempt to determine the GRUB boot device by using
UUID tags. If this fails it will fallback to the above variable and set
root to

*\$GRUB\_BOOT\_DEV,X*, X being a grub partition specifier.

For root a partition of /dev/sda1 this would be either *msdos1* or
*gpt1* depending on the type of partition table and thus result to a
boot menu entry of

*set root=hdo,msdos1*

[]{#anchor-28}HAS\_WIFI\_CFG, MIGRATE\_ALL\_WIFIS, MIGRATE\_WIFI\_CFG

**Default:**

*HAS\_WIFI\_CFG=*

*MIGRATE\_ALL\_WIFIS=*

*MIGRATE\_WIFI\_CFG=*

These variables configure the *balena-stage1* scripts attempts to
migrate wifi configurations.

-   If *HAS\_WIFI\_CFG* is set to *TRUE* the balena-stage1 script will
    assume that the balenaOS image already contains a wifi configuration
    in */resin-boot/system-connections/resin-wifi01* and will attempt
    not to overwrite

it. The migrated configurations will start with *resin-wifi02*.

-   If *MIGRATE\_ALL\_WIFIS* is set to *TRUE* all wifi configurations
    found in */etc/wpa\_supplicant/wpa\_supplicant.conf* or

*/etc/NetworkManager/system-connections* will result in a *resin-wifiXX*
file that will be transferred to */resin-boot/system-connections* in
stage 2.

-   If *MIGRATE\_WIFI\_CFG* is set to the name of a file in *HOME\_DIR*
    the migrated wifi configurations will be filtered by the contents of
    the file.

The file is expected to contain one wifi name (ssid) per line. Only
configurations referenced in the file will result in a *resin-wifiXX*
file in */resin-boot/system-connections*.

## Migration Stage 2 in Detail

Stage 2 is made up of a set of scripts that are run when the initramfs
is started. The initramfs contains an init script that will orchestrate
actions and call different scripts in different phases.

When using *DEFAULT* strategy only the
*/local-bottom/balena-stage2-default* script is actually active. All
other scripts will terminate immediately on being invoked. The
local-bottom is called last after the root file system has been mounted.
Only remaining steps in initramfs are to identify the systems init
script and hand over control to that.

**Restore Boot Configuration**

The */local-bottom/balena-stage2-default* script attempts to open the
balena-migrate-stage2.conf stored inside the initramfs from which it
takes its configuration.

First steps are to restore the original boot configuration on raspberry
pi devices. To do this it attempts to mount the boot partition and
restore /boot/config.txt and /boot/cmdline.txt from previously created
backups.

The script attempts do do this in a failsafe way, not terminating on
failure.

**Establish external Logging**

If an external log device was configured the
*/local-bottom/balena-stage2-default* script attempts to mount the
configured log drive and redirect all logging. The output can be found
in the file migrate.log.

The script attempts do do this in a failsafe way, not terminating on
failure.

**Copy BalinaOS image, Backups and configs to TMPFS**

Next the stage2 script attempts to copy all files, that need to be
transferred to balinaOS to the tmpfs storage the initramfs resides in.
This is a critical stage, that could fail in a non recoverable way. If
too much data is copied to initramfs the system will run out of memory
and will likely fail in a way that will stall the boot process. For this
reason it is important to make sure that enough memory is available for
files still leaving enough memory for initramfs processing to work.

**Flash balenaOS**

After all the above preparations have succeeded the script will unmount
the root file system and flash the balenaOS to the target device.
Beginning with this stage the migration is not recoverable. The exit
strategy on failure is changed to *reboot -f* to attempt to reboot into
balenaOS if something goes wrong.

For the raspberry PI platform this is likely to succeed, grub based
systems currently need a further step to be able to boot successfully.

**Transfer Data to BalenaOS**

The script will now attempt to mount the */resin-boot* and */resin-data*
partitions.

To do this it calls *partprobe* on the root device to reread the changed
partition tables.

After the partitions have been mounted successfully the backup files are
being transferred to */resin-data* and migrated wifi-configurations are
copied to */resin-boot/system-connections .*

**Installing a new Bootloader**

In case of a raspberry Pi the work is done after the last step.

In a grub booted environment a new bootloader has to be installed. So
far the script is only tested with grub legacy boot. As boot images
(boot.img / core.img) and offsets are not yet available for all x86
platforms the current approach is to create a grub configuration and
call grub-install from within the initramfs.

All relevant files (mainly grub.cfg) have been prepared in stage 1 so
the stage 2 script only places the files in the appropriate locations
and calls grub-install with parameters prepared in stage 1. Calling
grub-install from within initramfs has to be thoroughly tested for all
relevant platforms and grub versions. The program requires files to be
copied to initramfs from */usr/share/grub* and attempts to access
*/usr/locale* but tolerates it not being available. Having ready made
boot.img / core.img files (even integrated into the images) might be a
more reliable solution.

**Unmounting partitions and reboot**

Last step is to unmount all mounted partitions, reboot the system and
ope for the best..

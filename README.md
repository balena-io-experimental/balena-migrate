# BalenaOS Migration

This project attempts to provide a generic solution to migrate a range of different device types running linux operating 
systems to balenaOS.

## How to use balena-migrate

**Warning:** When migrating devices, that contain critical data or are not easily accessible, please make sure to test your setup 
thoroughly in a test environment before applying it to production devices. It also makes sense to read this document completely to understand 
the concepts and the risks involved. 

### Preparing the Migration Environment

The *migrateCfg* folder in this repository will be your migration environment. 

To migrate a device you will have to copy some more files into this directory and create / edit configuration files. 
Therefore it makes sense to copy the entire folder to a different location. Ultimately - once your setup is complete 
you will copy the directory to the device you want to migrate.

After creating the migration environment the next step is to create a balena-migrate.conf file, that will contain your 
configuration. There are a several sample config files contained in the directory that you can use as a template. The 
easiest way is to copy a file that matches your platform to *balena-migrate.conf*.
To migrate a Raspberry PI device you might invoke:
 ```
 cp balena-migrateRPI.conf balena-migrate.conf
 ```   

#### Preparing the OS Image

Next copy the balenaOS image that you want to install to the folder and set the *IMAGE\_FILE* variable in the config
file to the name of the image.

When migrating Raspberry PI devices you can use the unmodified image, that you have downloaded from the dashboard. 

On intel-based devices you will have downloaded a flasher image that can not be used directly with *balena-migrate*. 
Please read the next section: 'Extracting the balenaOS image and grub config from a Flasher Image' to extract your 
balenaOS image and grub config file. 

The image you downloaded is typically zip compressed. Internally balena-migrate works with the gzip format to be able 
to flash images directly from the compressed archive. For this reason balena-migrate will unzip zip compressed image files 
and recompresss them using gzip. If you are planning to use the same setup multiple time it makes sense to convert the 
image file to gzip manually to save time and disk space when devices are actually migrated. To do this use unzip 
to unpack the zip archive containing the image and then gzip to compress the unpacked file. You can then remove the 
zip archive and configure the gzipped file to be your image file.
Example:
```
unzip balena-cloud-appname-paspberrypi3-2.26.0+rev1-dev-v8.0.0.img.zip
gzip balena-cloud-appname-paspberrypi3-2.26.0+rev1-dev-v8.0.0.img
rm balena-cloud-appname-paspberrypi3-2.26.0+rev1-dev-v8.0.0.img.zip
```     

##### Extracting the balenaOS image and grub config from a Flasher Image

The easiest way to extract the balenaOS image and grub config is to use the extract script supplied in this repository.
The extract script can be invoked as follows:
```sudo ./extract --grub=<extracted grub file destination> --img=<extracted image destination> <flasher image>```
Example:
```
sudo ./extract --grub=grub.cfg \
               --img=resin-image-genericx86-64.resinos.img.gz \
               balena-cloud-appname-intel-nuc-2.26.0+rev1-dev-v8.0.0.img.zip
```
The above command will extract the grub config and the gzipped image from a zip archive containing the flasher image.

The extract script can work with a zip archive or with the raw flasher image. 

**Warning:** If working on a zip archive please make sure you have about 3GB of disk space available to unpack the image.     
 

##### Setting up the Config File

Using the a text editor like nano, vim or gedit edit your balena-migrate.conf file to contain at least the following 
values:

```
IMAGE_NAME=<path to you zip or gzip image file>
NO_FLASH= # when you are ready to flash the device
```

Several other options can be set that are describe in section 'Configuration'.
 

### Starting Migration 
 
Once prepared the migration environment can be transferred to the target device. Migration is started by invoking
balena-migrate from inside the migration environment. 
Example:
```
sudo balena-migrate
```         

## Strategy

The migration is performed in two stages. Stage 1 is invoked by running the script balena-migrate.
Stage 2 is invoked during boot from inside an initramfs. The stage 2 scripts will install balenaOS if
configured to do so.

### Stage 1

The first stage ensures that all requirements are met, triggers the creation of a modified initramfs and installs 
it to be used at the next system reboot. It will reboot the system if configured to do so. 


The balena-migrate script will create a configuration file in */etc/balena-migration-stage2.conf* that will determine 
the actions and required files during initramfs creation as well as for stage 2 which is run from inside initramfs after 
booting the device.

The balena-migrate script creates an initramfs file that contains all scripts, programs and configuration files needed 
for phase 2.

The stage 1 script will also perform migration tasks such as creating a backup (that will be transferred to resin-data) 
and migrating network (WIFI) configurations to be installed in balenaOS (resin-boot/system-connections). 
The backup files files as well as the actual balenaOS image file are likely too big to be contained in the root partition 
where the initramfs resides and will be copied from the root file system to initramfs in stage 2.

The stage 1 script will reconfigure the bootloader of the system to use the created initramfs and optionally reboot 
the system. On systems using grub as bootloader the system is configured to have one shot at the modified boot configuration 
using grub-reboot. On RPI the */boot/config.txt* and */boot/cmdline.txt* files are modified. They are reset to their 
original values by the stage 2 script. 
 

### Stage 2

When booted from the newly created initramfs the contained stage 2 scripts will attempt to store all required files 
inside the tmpfs that the initram system is mounted on. The configuration created in stage 1 
(*/etc/balena-migrate-stage2.conf*) contains instructions on which files to transfer to the tmpfs.

Any failures up to this point can be tolerated by resetting the boot configuration to the prior state. In grub based 
boot loaders this is achieved automatically, for RPI devices the */boot/config.txt* and */boot/cmdline.txt* files have 
to be restored to their prior state and the systems should be able to reboot into its former configuration. 
For Raspberry PI's the stage 1 script stores copies of the original files in the boot partition renamed to config.txt.TS 
and cmdline.txt.TS where TS is a timestamp. 

After all files have been secured, the stage 2 scripts will unmount the former root file system and flash the configured 
balenaOS image to the target device. After flashing, the script will trigger a reread of the devices partition information 
and attempt to mount resin-boot and resin-data to transfer files to.

A raspberry PI device can be rebooted after this step as the balenaOS image contains all information necessary to reboot 
the system. 

On Intel based devices the stage 2 script will attempt to create a new boot loader configuration by copying a new 
*grub.cfg* to the resin-boot partition and then calling grub-install on the boot device. The grub.cfg can be supplied by 
seting the parameter *GRUB_CFG* in the config file. If this parameter is not set, the script will use a simple grub.cfg created 
by the stage 1 script. Due to changes in recent versions of balenaOS the autocreated grub.cfg does not work any more. 
The safe way is to do this is to supply a cfg.grub that matches the OS version that is being installed by extracting it 
from the flasher image.
  
### TODO:
Support user supplied boot loader images to be flashed flashed. 

## Supported Platforms

So far the scripts are being tested and are working on the following platforms:

-   Raspberry PI 2 on Raspian-9
-   Raspberry PI 3 on Raspian-9
-   Raspberry PI 3 running NOOBS and Raspian-9
-   Virtualbox x86\_64 systems running ubuntu 14.04 and 18.04 in grub
    legacy mode.
-   x86\_64 intel-nuc running ubuntu 14.04 and 18.04 in grub EFI mode.
-   The STEM device - 32 intel running Ubuntu 14.04 in grub legacy mode


## TODOS

- Work is in progress on following platforms: beaglebone green
- Migrate other than wifi settings eg. GSM modem settings.

## Migration Stage 1 in Detail

The script *balena-migrate* will check the prerequisites for migration before it attempts to modify the system.
It reads its configuration from a file and also supports a number of command line parameters. 
Parameters set on the command line override options given in the config file. 

The script itself can be located anywhere. It attempts to read its configuration from a file which  defaults to 
**balena-migrate.conf**. It will look for the file in the current directory and in the *HOME\_DIR*. 
The location and name of the config file and HOME\_DIR can both be set using command line parameters.

The directory specified by *HOME\_DIR* is used to store temporary files and is also expected to contain the 
initramfs-tools directory provided in this repository. All other paths given in the config file or on the command line 
are expected to be relative to *HOME_DIR* which defaults to the current working directory.
  
All parameters have a default except for *IMAGE_NAME* which **must** be set in the config file or using command line 
parameters. It points to the balenaOS image to be flashed.

When migrating a platform, that uses grub as boot manager in balenaOS (intel 32 and 64 bit devices), please make sure to 
provide a valid grub config file that is compatible with the balenaOS version used. The file can be specified using the 
*GRUB\_CFG* variable. Failing to do so will lead to devices failing to boot into balenaOS.
 
The defaults set in *balena-migrate* are rather conservative so that the script will not actually flash the image but 
just create an initramfs and configure it to boot. It will will not overwrite the boot device when booted from in the
default configuration. To enable this the config variable *DO_FLASH*  has to be set to *TRUE*.   

The script contains a list of supported operating systems and hardware platforms that it has been tested on. It will 
reject any OS or hardware not contained in that list.

The idea is to add further architectures, OS'ses and OS versions only after they have been thoroughly tested.

### Prerequisites

#### Environment

The stage 1 scripts expects the boot configuration to be available under */boot*. It expects the */boot* directory to 
be on the same hard drive as the root file system and will fail with an error message if this is not the case.

To create the initramfs *balena-migrate* uses its own initramfs-tools directory (instead of */etc/initramfs-tools*) 
which is expected to be located in *HOME\_DIR*. This directory contains an initramfs config file and several scripts that 
either help create the initramfs or are executed from within the initramfs when it is booted from.

The following are the relevant files in *HOME\_DIR/initramfs-tools*:

-   *initramfs.cfg* - the initramfs config file.
-   hooks/balena-init - this script copies programs & files to the initramfs at creation time.
-   *scripts/balena-common* - this script contains some helper functions used from other scripts during initramfs boot.
-   *scripts/local-bottom/balena-stage2-default* - this is the main boot time script.

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

The stage 1 script will also make sure, that all the software required to perform the migration is available. Required 
software depends on the architecture and OS and includes the following:

  |**Program**|   **Architecture**|          **Version**|
  |--------------| -------------------------| -------------|
  |Stage 1 ||                                  
  |tar            |all                       |unspecified|
  |findmnt        |all                       |unspecified|
  |parted         |all                       |unspecified|
  |lsblk          |all                       |unspecified|
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

The script *balena-migrate* uses a configuration file to read its configuration from.

balena-migrate will print a simple help message when called with the -h or --help option that states the available command 
line options.

The **config file** can be specified on the commandline using the -c or --config option:

*balena-migrate -c ./migrate.conf* 

*balena-migrate --config=./migrate.conf*

The config file uses shell syntax, valid settings for this file are as follows.

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

The alternative would be to supply a backup script that will create the file set in *BACKUP\_FILE* and specify it in the 
*BACKUP\_SCRIPT* variable. The backup script will be processed by *balena-migrate* (in stage 1) so it is not critical 
and can easily be tested.

The file specified in *BACKUP\_FILE* will be copied to the *resin-data* partition in stage 2. 

##### Backup file Size considerations

The stage 1 script attempts to estimate the space available and warn if there is not enough space left, but this is still 
rather unprecise due to lack of experience. 
The backup file and the balenaOS image will be copied to initramfs during stage 2. If the size of the backup and the image 
together with all other files needed for migration in stage 2 exceeds the size of the available memory or does not 
leave enough memory for processing, stage 2 will fail. This means that the boot process will stall and the device might 
remain in a state that requires manual intervention. 

To avoid this from happening please make sure to keep the backup file as small as possible.   
       
#### BALENA\_CONFIG

**Default:** *BALENA\_CONFIG=

If specified , the name of a file in *HOME\_DIR* that will be interpreted as config.json file and copied to the 
resin-boot partition in stage 2.

The balena config.json file can be specified as a command line parameter using the *--balena-cfg* option as follows: 

*balena-migrate --balena-cfg=project-config.json*


#### BALENA\_UUID

**Default:** *BALENA\_UUID=

If specified this value is treated as the devices UUID and will be injected into the file specified by the 
*BALENA\_CONFIG* variable. If *BALENA\_CONFIG* is not set this parameter has no effect.    

The balena config.json file can be specified as a command line parameter using the *-u / --uuid* option as follows: 
  
*balena-migrate -u 1a9f88d13a555ba61f1c9a951fab09a3*
  
*balena-migrate --uuid=1a9f88d13a555ba61f1c9a951fab09a3*

#### BALENA\_WIFI

**Default:** *BALENA\_WIFI="TRUE"

If this variable is set to *TRUE* and *BALENA\_CONFIG* points to a file in *HOME\_DIR* the file will be scanned for the 
ssid & key of a wifi network. If an SSID is found a network manager file will be created for this network and copied to
*resin-boot/system-connections* in stage 2.

#### DEBUG

**Default:** *DEBUG=*

Sets the debug flag in the kernel command line if set to *TRUE*. If this setting is enabled the initramfs log can be 
found in */run/initramfs/initramfs.debug*.

#### DO\_REBOOT

**Default:** *DO\_REBOOT=*

When this variable is set to a numeric value the *balena-migrate* script will reboot the computer after finishing successfully. 
It will display a warning and reboot after the number of seconds specified in *DO\_REBOOT*. By default this option is 
disabled and the device has to be rebooted manually after stage 1 has terminated.

The variable can be set on the command line by using the -r or --reboot parameters:

*balena-migrate -r 10*

*balena-migrate --reboot=10* 


#### GRUB\_BOOT\_DEV

**Default:** *GRUB\_BOOT\_DEV=hd0*

The variable supplies a hint to which grub device to use for boot. The stage 1 script will attempt to determine the GRUB 
boot device by using UUID tags. If this fails it will fallback to the above variable and set root to

*\$GRUB\_BOOT\_DEV,X* - X being a grub partition specifier.

For root a partition of /dev/sda1 this would be either *msdos1* or *gpt1* depending on the type of partition table and 
thus result to a boot menu entry of

*set root=hdo,msdos1*

#### GRUB\_CFG

**Default:** *GRUB\_CFG=*

Specify a grub config file for balenaOS. 

The setting is only relevant for platforms on which balenaOS uses grub to boot, relevant platforms are intel 32 or 64 
bit devices. 

If the variable is not set balena-migrate will create a simple grub.cfg file. At the time of writing this 
file has been tested on balena release 2.13 and is expected to work on earlier releases. 

Newer versions of balenaOS (seen on 2.26) use a modified layout of the boot files and require a matching *grub.cfg* file 
to be provided using this variable. 

**Warning:** If an incompatible grub.cfg is used the system will not boot into balenaOS successfully. As the balenaOS 
image is already written to the disk, the only way to recover is to repair the boot configuration.         


#### HAS\_WIFI\_CFG, MIGRATE\_ALL\_WIFIS, MIGRATE\_WIFI\_CFG

**Default:**

*HAS\_WIFI\_CFG=*

*MIGRATE\_ALL\_WIFIS=*

*MIGRATE\_WIFI\_CFG=*

These variables configure the *balena-migrate* scripts attempts to
migrate wifi configurations.

-   If *HAS\_WIFI\_CFG* is set to *TRUE* the balena-migrate script will assume that the balenaOS image already contains 
    one wifi configuration in */resin-boot/system-connections/resin-wifi01* and will attempt not to overwrite it. 
    The migrated configurations will start with *resin-wifi02*.
-   If *MIGRATE\_ALL\_WIFIS* is set to *TRUE* all wifi configurations found in */etc/wpa\_supplicant/wpa\_supplicant.conf* 
    or */etc/NetworkManager/system-connections* will result in a *resin-wifiXX* file that will be transferred to 
    */resin-boot/system-connections* in stage 2.
-   If *MIGRATE\_WIFI\_CFG* is set to the name of a file in *HOME\_DIR* the migrated wifi configurations will be filtered 
    by the contents of the file. The file is expected to contain one wifi name (ssid) per line. Only configurations 
    referenced in the file will result in a *resin-wifiXX* file in */resin-boot/system-connections*.

#### HOME\_DIR

**Default:** *HOME\_DIR=./*

The working directory of the migration script and the location where it expects to find initramfs-tools directory, 
as well as setup and image files. The default is to use the current working directory. 

This variable can be set on the command line using the --home parameter:

*balena-migrate --home=/migrate-dir*  


#### IMAGE\_NAME

This option **must** be specified. It specifies the balenaOS image that will be flashed to the devices boot device. 
The script will fail if the file is not specified or does not exist.

The script expects the image to be in gzipped format.

The script expects the file to be tagged with the target platform as follows:


  |**Platform**    |**Image tag**|
  |--------------- |----------------|
  |  Raspberry PI1|   raspberry-pi1|
  |Raspberry PI2   |raspberry-pi2|
  |Raspberry PI3   |raspberrypi3|
  |x86\_64         |genericx86-64|
  |i686            |intel-core2-32|


**Example:**
*IMAGE\_NAME="resin-raspberrypi3-2.15.1+rev2-dev-v7.16.6.img.gz*"


#### LOG\_DRIVE , LOG\_FS\_TYPE

**Default:** *LOG\_DRIVE=*

Specify a separate device to receive log files written during stage 2. The device **must** be separate from the 
installation device (hard drive) to be able to survive flashing of the balenaOS image. Use a separate hard disk or a 
USB stick. The logfiles can be used for debugging of problems in stage 2.

**Example:**

*LOG\_DRIVE=/dev/sdb1*

*LOG\_FS\_TYPE=ext4*


#### NO\_FLASH

**Default:** *NO\_FLASH=TRUE*

When this variable is set to *TRUE* the script will proceed normally but will terminate at the point in stage 2 where 
the mounted root file system would be unmounted and the balenaOS image would be flashed to the device. How to terminate 
is determined by the value of the variable *TERM\_EXIT*.

#### NO\_SETUP

Default: *NO\_SETUP=*

When this variable is set to *TRUE* the *balena-migrate* script does not attempt to modify the boot configuration. 
It will check the prerequisites create an initramfs but not create any disruptive configuration changes.

#### TERM\_EXIT

**Default:** *TERM\_EXIT="exit 0"*

Determines how to exit when the script terminates prematurely. Default is *“exit 0”* in which case the boot process is 
continued normally. Alternative is *“reboot -f”* to force a reboot. 
**Warning:** If the boot configuration has not been reset successfully , setting *TERM\_EXIT="reboot -f"* can lead to 
a boot loop.


## Migration Stage 2 in Detail

Stage 2 is made up of a set of scripts that are run when the initramfs is started. The initramfs contains an init script 
that will orchestrate actions and call different scripts in different phases.

Scripts in the *local-bottom* directory are called last and after the root file system has been mounted. Only remaining 
steps in initramfs are to identify the systems init script and hand over control to that. The balena-stage2 script runs 
in that stage. If it has successfully written and configured balenaOS it will terminate the boot process by forcing a 
reboot.  

**Restore Boot Configuration**

The */local-bottom/balena-stage2-default* script attempts to open the balena-migrate-stage2.conf stored inside the initramfs from which it
takes its configuration. 

First steps are to restore the original boot configuration on raspberry pi devices. To do this it attempts to mount the 
boot partition and restore /boot/config.txt and /boot/cmdline.txt from previously created backups.

The script attempts do do this in a failsafe way, not terminating on failure.

**Establish external Logging**

If an external log device was configured the */local-bottom/balena-stage2-default* script attempts to mount the
configured log drive and redirect all logging. The output can be found in the file migrate.log in the root of the device.

The script attempts do do this in a failsafe way, not terminating on failure.

**Copy BalinaOS image, Backups and configs to TMPFS**

Next the stage2 script attempts to copy all files, that need to be transferred to balinaOS to the tmpfs storage the 
initramfs resides in. This is a critical stage, that could fail in a non recoverable way. If too much data is copied to 
initramfs the system will run out of memory and will likely fail in a way that will stall the boot process. For this
reason it is important to make sure that enough memory is available for files still leaving enough memory for initramfs 
processing to work. 

The stage 2 script attempts to estimate the available space and will fail if insufficient space is available. 

**Flash balenaOS**

After all the above preparations have succeeded the script will unmount the root file system and flash the balenaOS to 
the target device. Beginning with this stage the migration is not recoverable. The exit strategy on failure is changed 
to *reboot -f* to attempt to reboot into balenaOS if something goes wrong.

For the raspberry PI platform this is likely to succeed, grub based systems currently need a further step to be able to 
boot successfully.

**Transfer Data to BalenaOS**

The script will now attempt to mount the */resin-boot* and */resin-data* partitions.
To do this it calls *partprobe* on the root device to reread the changed partition tables.

After the partitions have been mounted successfully the backup files are being transferred to */resin-data* and migrated 
wifi-configurations are copied to */resin-boot/system-connections*. If specified the config.json file is copied to 
*/resin-boot/*.

**Installing a new Bootloader**

In case of a raspberry Pi the work is done after the last step. 

In a grub booted environment a new bootloader has to be installed. As boot images (boot.img / core.img) and offsets are 
not yet available for all x86 platforms the current approach is to create a grub configuration and call grub-install from 
within the initramfs.

All relevant files (mainly grub.cfg) have been prepared in stage 1 so the stage 2 script only places the files in the 
appropriate locations and calls grub-install with parameters prepared in stage 1. Calling grub-install from within 
initramfs has to be thoroughly tested for all relevant platforms and grub versions. The program requires files to be
copied to initramfs from */usr/share/grub* and attempts to access */usr/locale* but tolerates it not being available. 
Having ready made boot.img / core.img files (even integrated into the images) might be a more reliable solution.

**Unmounting partitions and reboot**

Last step is to unmount all mounted partitions, reboot the system and hope for the best..




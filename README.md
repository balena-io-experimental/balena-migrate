# Project STEM


Migrating deployed customer devices to resinOS

## Device Hardware/Software

Known so far (please correct):
- Device Architecture is x86
- Device OS is Ubuntu 14.04  
- Memory is ~2GB
- hard disk / flash is ~16GB 

According to Greg Hard disk looks like standard Ubuntu 14.04 setup, so assuming:
- GRUB 2.02 boot loader
- 14 GB root Partition 
- 2 GB (extended) Partition with SWAP

__Example__

```bash
fdisk -l /dev/sda

Disk /dev/sda: 17.2 GB, 17179869184 bytes
255 heads, 63 sectors/track, 2088 cylinders, total 33554432 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x000ae07e

   Device Boot      Start         End      Blocks   Id  System
/dev/sda1   *        2048    29360127    14679040   83  Linux
/dev/sda2        29362174    33552383     2095105    5  Extended
/dev/sda5        29362176    33552383     2095104   82  Linux swap / Solaris

```
  
## Observation from intel-nuc resin-flash Configuration

Flashes image directly onto first found matching block device (going through configured list of device names)

Scripts in /bin/resin-

Image from /opt/

Config in /etc/resin

I am assuming a grub boot loader is part of the image. Configuration files are present and copied for GRUB 2 boot loader. 
Preparations for additional boot stages are present but not used in intel-nuc config.

## Ideas for update Phase 1

### Idea A - Lightweight Deployment
Resin.io supplies an executable (e.g. shell script) that has to be deployed by the customer and executed 
on the target device with root privileges. 
The shell script: 
- is best option for size and compatibility / requirements and can
- ensure that requirements are met (space / swap / memory / bootloader) before continuing.
- prepare space eg, disable swap, reformat swap partition to make space for image.
- download image to freed space on swap.
- execute a (customer supplied) backup script to stop services and backup data on swap. 
- rollback if any of the above steps failed (only modification is reformated swap space).
- modify grub config to reboot from a system located on swap partition
- reboot the device to start the migration environment

Difference to standard resin.io deployment methods is that the script has to place a bootable environment in the reformated 
swap space without flashing it (via DD). Instead it will be unacking a tar downloaded archive or similar. 
     

### Idea B - Deploying an Image

Resin.io supplies an executable (e.g. shell script) along with an image or archive that contains the actual 
migration environment.  The script is executed on the target device with root privileges. 
In contrast to plan A there has to be sufficient space to save the archive on the active data partition.  
The shell script can: 
- ensure that requirements are met (space / swap / memory / bootloader) before continuing.
- flash image or format and unpack archive to swap partition and activate that partition.  
- execute a (possibly customer supplied) backup script to stop services and backup data to swap. 
- rollback if any of the above steps failed (only modification is overwritten swap space).
- modify grub config to reboot from a system located on swap partition.
- reboot the device to start the migration environment

### Rollback Options

For both of the above procedures the device is bricked if we fail to boot from the setup on the former swap partition.
If reboot succeeds we still have options to rollback by resetting the boot manager to its former settings (save grub config)
but as the likely next step is to format or flash the former data partition that is not a big advantage.

If grub (v2) is used as boot manager an option would be to add a boot target for the new configuration 
instead of replacing it. This can be rather complex but would allow us to use grub-reboot to try and boot 
the new system only once and return to the prior configuration otherwise if it fails.   

## Update Phase 2 

We have now booted from the target device and are able to flash or format the former data partition.
The procedure can be quite similar to the regular flash process. 
Differences:
- we do not write to a hard disk but instead to a partition. As a result the image can not contain MBR and 
  partition table. 
- when using dd we have to make sure we do not damage the former swap partition that we have started from.
- As a result it might be safer to use format and deploy an archive instead of using dd to flash an image into 
the available space.   
    
When this process is finished we make sure grub points to a new valid grub config and reboot again.


## Update Phase 3

Tasks:
- restore backuped customer data to data partition.
- optionally delete the former swap partition and extend the data partition to use the freed space.
- download / activate supervisor and customer containers 

## Possible Enhancements

Have pre deployed customer application in original deployment 

   
## Collect

TODOs
- retrieve wifi access info from system
- try to flash image over system


  
  
   
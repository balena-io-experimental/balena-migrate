# ResinOS Migration Howto

This document describes in detail the steps involved in the migration of a device running a 
linux operating system to resinOS. The procedures described are valid and have been tested for
a x86_64 device running Ubuntu 14.04. 
     
 
## Modifying the Flasher Image

The reduce-img script contained in this repository is used to modify a standard-flasher image that will be used in stage1 
of the migration.    

The strategy used so far makes use of the swap partition of the device to install the flasher image and boot it. 
The standard flasher image for the intel-nuc takes up 2.6 GB of space which in most cases will be too much to be contained 
in the swap space. The strategy for reducing the size of the image is to compress the contained ResinOS image and 
shrink the flasher-rootA partition that contains it.

Also the resin-init-flasher script contained in the flasher-rootA needs to be replaced with a modified version. This is 
the migrate-stage2 script contained in this repository. 

Additionally you can use the script to exchange the config.json file contained in the boot partition of the flasher image 
against a different version that must be supplied.

The reduce-img script can be configured by changing the file reduce-img.conf supplied in this repository. The parameters 
of the reduce-img.conf are documented inside the file:

```bash
#!/bin/bash

# what type of MBR to create
TARGET_MBR_TYPE="msdos"

# temporary mount directories
MOUNT_DIR1="/mnt/resin-tmp1"
MOUNT_DIR2="/mnt/resin-tmp2"
# path to resinOS image in flasher-rootA
RESIN_IMG="/opt/resin-image-genericx86-64.resinos-img"

# blocks of free space for resized flasher-rootA partition
ADD_BLOCKS=81920   # 40MB in 512 byte blocks
# partition alignment (blocks)
PART_ALIGN=8192

# path to flasher-script
REPLACE_PATH=/usr/bin
# filename of flasher-script
REPLACE_SCRIPT=resin-init-flasher
# migrate stage 2 file to replace flasher script
MIGRATE_SCRIPT=./migrate-stage2
# MIGRATE_CFG=./migrate-stage2.cfg

# file to replace config.json, if empty nothing will be replaced
RESIN_CFG_SRC=./vresinx64.config.json
# name of target config file in the root of the boot partiontion
RESIN_CFG_TGT=config.json

```  

### Required Files

Using the above configuration the following files need to be supplied in the directory 
the command is executed in:

- A standard flasher image for the target platform. The file name is specified on the command
line of reduce-img
- The stage 2 migration script (migrate-stage2) from this repository.
- A config.json file, specified above as ```vresinx64.config.json ```

### Invoking the Script

The reduce-img script needs to be called with sudo as it uses the mount command. 

It is called with the name of the flasher-image file and the name of the output 
image file:

```bash
sudo ./reduce-img resin-vresinx64-intel-nuc-2.13.6+rev1-dev-v7.14.0.img reduced-full.img   
```
 
 This command (if successful) will write 2 files:
 - reduced-full.img the reduced image
 - reduced-full-devmap.txt - a partition map of the image used by stage1 to partition the target drive if the provided 
 image is compressed.  
 
 
 
 
 

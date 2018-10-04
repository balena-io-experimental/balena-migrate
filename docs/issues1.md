# Issues 1

The final goal of this project is to find a way to modify a devices main partition and install resinOS there without manual 
interaction virtually from within the running system. 
This cannot be achieved while we are running in a system, that has booted from the partition that we want to 
modify.   

The strategy we are currently pursuing is to use the swap partition as an intermediate (migration) stage 
boot partition. The intermediate goal is to install a bootable migration environment on the former swap partition. 
This environment once booted can then flash a resinOS to the main partition to create the 
final setup.

## Resrictions of the SWAP based strategy
One downside to this approach is, that it is only viable on systems that actually use a swap partition and a boot 
manager that can be modified boot from there. On a raspberry pi the boot process is completely different and 
swap partitions are not common (and do not make much sense).

Generally systems running on SD Cards are unlikely to make extensive use of swap for obvious reasons. To be able to 
support these systems a different strategy will have to be used.  

## Challenges using the SWAP based strategy

I assume I am starting with a script running on root privileges inside a linux OS.  
After determining the environment and identifying free space the upgrade script needs to prepare the migration environment
for reboot.

Obviously resinOS is well suited for the target environment and contains all the drivers necessary to establish network communication and communcation channels to 
resin.io systems. 

I have been looking at flasher images for intel-nuc devices and found the following problems:

a) Size
The standard flash image (e.g. for a intel-nuc) is too big to fit the approx 2 GB we 
are assuming as swap space. The standard image contains a full system plus the resin.os image that is meant
to be installed on the device. The overall size of the image is 2.693 GB
The contained resin.io image is about 1.8GB in size.

```bash
sudo parted resin-vresinx64-intel-nuc-2.13.6+rev1-dev-v7.14.0.img print
Model:  (file)
Disk /home/thomas/develop/resin.io/images/resin-vresinx64-intel-nuc-2.13.6+rev1-dev-v7.14.0.img: 2693MB
Sector size (logical/physical): 512B/512B
Partition Table: msdos
Disk Flags: 

Number  Start   End     Size    Type      File system  Flags
 1      4194kB  46.1MB  41.9MB  primary   fat16        boot, lba    # boot
 2      46.1MB  2668MB  2621MB  primary   ext4                      # resin-rootA
 3      2668MB  2672MB  4194kB  primary   ext4                      # resin-rootB
 4      2672MB  2693MB  21.0MB  extended               lba          # extended
 5      2676MB  2680MB  4194kB  logical                             # state
 6      2684MB  2693MB  8389kB  logical                             # data
```

b ) Writing the Image

The second problem with this approach is, that the standard flasher images are disk 
images in contrast to partition images. This means they contain an MBR and partition table 
both of which should not be written to a partition.

To write this image to our swap space (assuming reduced size) we need to first create the appropriate amount and 
size of partitions inside the extended partition that the swap partition resides in (standard ubuntu setup) and then 
write each contained partition to the allocated target space using dd.

c) parted 
 

      
The possible strategies are:

a) Install a modified version of the flash image
This is the startegy I am are currently primarily investigating because:
- the flasher image uses resin.os which is well suited for the environment we are targeting 
and is available for all targeted platforms.
- The image contains all components necessary to set up communication to resin.io systems.

 
   
 


  
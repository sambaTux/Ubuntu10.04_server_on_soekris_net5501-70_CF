a) Purpose of these scripts:
----------------------------

These scripts are intendet to run on a Soekris net5501-70 (512 MB RAM) embedded system 
with a 4 GB Compact Flash (CF) as storage device. But with little modifications 
they can also be used to run on other devices. 

Because NAND CFs have "only" a write endurance of ~1,000,000 cycles per location, it 
is a good idea to swap highly used parts of the OS to a ramdisk. In this case /var.
Like this we can increase the CF lifetime and mount i.e. the root partition in read only.

As a little gadget the soekris GPIO error LED is activated when a script error occures.

Tests here were made with an Ubuntu10.04 server 32Bit system on Soekris net5501-70 hardware.


b) Howto use these scripts:
---------------------------

1) The CF partition sheme must consist of these partitions:
   /          #root tree partition, i.e. 3,5GB
   /var       #var partition, i.e. 200MB
   /varbak    #varbak partition, i.e. 200MB. This is a helper partition for syncing data etc...

2) run os-config.sh once to prepare the OS for "var2rd.sh" and "varbak.sh", for 
   soekris serial console, etc... 

3) copy "error-led.sh" to /usr/local/sbin. This script is used by "var2rd.sh" and "varbak.sh" 

4) copy "var2rd.sh" to /usr/local/sbin and use /etc/rc.local to use it as startup script.
   Note: If you want to mount the root partition in read only, use rc.local. Otherwise 
         the script may disturb itself by accessing / while remounting / in read only.

5) copy "varbak.sh" to /usr/local/sbin and use it as cronjob in order to save data from ramdisk to CF. 


c) Brief overview about the tasks that these scripts accomplish:
----------------------------------------------------------------

os-config.sh

   - set kernel parameters
   - turn off fsck for root partition
   - deactivate  "multiverse" and "universe" repos to save ~60MB in /var/lib/apt/lists/
   - set swappiness to 0 (def. = 60)
   - create mount points for logfiles and create /var/err

var2rd.sh

   - check for errors (/var/err), else activate error LED and quit
   - create tmpfs for logfile 
   - check if /var and /varbak are partitions
   - get list of processes which are accessing /var
   - stop/kill those proccesses
   - clean /var/cache
   - unmount tmpfs /var/lock and /var/run
   - sync /var (CF) with /varbak (CF)
   - format ramdisk /dev/ram0
   - mount ramdisk on /var
   - sync /var (ramdisk) with /varbak (CF)
   - start processess again
   - unmount logfile tmpfs

varbak.sh

   - check for errors (/var/err), else activate error LED and quit
   - create tmpfs for logfile 
   - check if /dev/ram0 is mounted
   - check if /var and /varbak are partitions
   - get list of processes which are accessing /var
   - stop/kill those proccesses
   - if enough free RAM, use another tmpfs to sync data between /var (ramdisk) and /varbak (tmpfs)
     if not enough free RAM, use /varbak (CF) to sync data
   - clean /var/cache
   - sync /varbak (CF/tmpfs) with /var (ramdisk)
   - unmount /var (ramdisk)
   - sync /var (CF) with /varbak (CF/tmpfs)
   - mount ramdisk on /var
   - start processess again
   - unmount logfile tmpfs

error-led.sh

   - load GPIO kernel modules
   - create error LED nod
   - create GPIO nod
   - activate error LED



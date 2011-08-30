a) Purpose of these scripts
----------------------------

These scripts are intended to run on a Soekris net5501-70 (512 MB RAM) embedded system 
with a 4 GB Compact Flash (CF) as storage device. But with little modifications 
they can also be used to run on other devices. 

Because NAND CF has "only" a write endurance of ~1,000,000 cycles per location, it 
is a good idea to swap highly used parts of the OS to a ramdisk. In this case /var.
Like this we can increase the CF lifetime and mount i.e. the root partition in read only.

As a little gadget the soekris GPIO error LED is activated when a script error occurs.

Tests here were made with an Ubuntu10.04 server 32Bit system on Soekris net5501-70 hardware.


b) How to use these scripts
---------------------------

1) The CF partition scheme must consist of these partitions:
   /          #root tree partition, i.e. 3,5GB. 
               Mount options: noatime
   /var       #var partition, i.e. 200MB. 
               Mount options: nodev, nosuid, noatime
   /varbak    #varbak partition, i.e. 200MB. This is a helper partition for syncing data etc. 
               Mount options: nodev, nosuid, noatime, noexec

2) run "os-config.sh" once to prepare the OS for "var2rd.sh" and "varbak.sh", for 
   soekris serial console, etc... 

3) copy "error-led.sh" to /usr/local/sbin. This script is used by "var2rd.sh" and "varbak.sh" 

4) copy "var2rd.sh" to /usr/local/sbin and use /etc/rc.local to use it as startup script.
   Note: If you want to mount the root partition in read only, use rc.local. Otherwise 
         the script may disturb itself by accessing / while remounting / in read only.

5) copy "varbak.sh" to /usr/local/sbin and use it as cronjob in order to save data from ramdisk to CF. 


c) Brief overview about the tasks that these scripts accomplish
---------------------------------------------------------------

os-config.sh

   - set kernel parameters
   - turn off fsck for root partition
   - deactivate  "multiverse" and "universe" repos to save ~60MB in /var/lib/apt/lists/
   - set swappiness to 0 (def. = 60)

var2rd.sh

   - check for errors (/var/err), else activate error LED and quit
   - create tmpfs for logfile 
   - check if /var and /varbak are partitions
   - get list of processes which are accessing /var
   - stop/kill those proccesses
   - clean /var/cache
   - sync /varbak/{run,lock} (CF) with /var/{run,lock} (tmpfs)
   - unmount /var/{run,lock} (tmpfs)
   - sync /varbak (CF) with /var (CF)
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



d) PXE installation of Ubuntu10.04 server 32Bit on Soekris net5501-70
---------------------------------------------------------------------

NOTE: The following steps where tested with a Ubuntu10.04 Desktop 32Bit system.


1) Serial connection to net5501
===============================

   1.1) Install minicom:

        > apt-get install minicom

   1.2) Use these configurations for /etc/minicom/minirc.dfl:

        ------------------------------------
        pu port             /dev/ttyUSB0
        pu baudrate         19200
        pu bits             8
        pu parity           N
        pu stopbits         1
        pu rtscts           No
        pu zauto            C
        -------------------------------------

        Note:  - The default baud rate of the net5501 is:  19200
               - Soekris doesn't support any kind of Flow Control. 

  1.3) Connect to net5501:

       > minicom
  
  1.4) comBIOS update:

       Note: Without an update it is probable that the comBIOS will not recognize newer Compact Flash cards.

       Now that we have a connection, we want to update the comBIOS.

       Download newest comBIOS: http://soekris.com/downloads.html

       Look here for a update how to: http://wiki.soekris.info/Updating_Bios

       As we have just configured "minicom", I recommend to use it here, too.


2) DHCP server
==============

   2.1) Install DHCP server:
  
        > apt-get install dhcp3-server

   2.2) Config DHCP server:
  
        2.2.1) Append the following lines to /etc/dhcp3/dhcpd.conf and adapt addresses to your needs:
  
        ----------------------------------------------
        subnet 192.168.0.0 netmask 255.255.255.0 {
            range 192.168.0.200 192.168.0.253;
            option broadcast-address 192.168.0.255;
            option routers 192.168.0.1;
            option domain-name-servers 192.168.0.1;
        }  

        host soekris {
           # tftp client/soekris hardware address
           hardware ethernet 00:00:24:??:??:??;
           filename "pxelinux.0";
        }
        ----------------------------------------------
   
        2.2.2) Define your NIC in /etc/default/dhcp3-server
 
               INTERFACES=eth?

   2.3) Start dhcp server

        > /etc/init.d/dhcp3-server start


3) TFTP server
==============


   3.1) Install TFTP server:

        > apt-get install tftpd-hpa


4) INETD server
===============

   4.1) Install INETD server:
     
        > apt-get install openbsd-inetd      
  
   4.2) Config INETD server:

        Append this line to /etc/inetd.conf

        ------------------------------------------------------------------------------------------------------
        tftp           dgram   udp     wait    root  /usr/sbin/in.tftpd /usr/sbin/in.tftpd -s /var/lib/tftpboot 
        ------------------------------------------------------------------------------------------------------

   4.3) Start INETD server:

        > /etc/init.d/openbsd-inetd start


5) netboot.tar.gz
=================

   5.1) Download file:
  
        > wget http://archive.ubuntu.com/ubuntu/dists/lucid/main/installer-i386/current/images/netboot/netboot.tar.gz
 
   5.2) Extract file:

        > tar xzfv netboot.tar.gz -C /var/lib/tftpboot/

   5.3) Config installer:

       5.3.1) var/lib/tftpboot/pxelinux.cfg must look like this:
 
       -----------------------------------------------------------
       CONSOLE 0
       SERIAL 0 19200 0
       include ubuntu-installer/i386/boot-screens/menu.cfg
       default ubuntu-installer/i386/boot-screens/vesamenu.c32
       prompt 0
       timeout 0
       -----------------------------------------------------------


       5.3.2) /var/lib/tftpboot/ubuntu-installer/i386/boot-screens/text.cfg must look like this:

       -----------------------------------------------------------------------------------------------------------
       default install
         label install
           menu label ^Install
           menu default
           kernel ubuntu-installer/i386/linux
           append tasks=server vga=normal initrd=ubuntu-installer/i386/initrd.gz -- console=ttyS0,19200 noplymouth
         label cli
           menu label ^Command-line install
           kernel ubuntu-installer/i386/linux
           append tasks=standard pkgsel/language-pack-patterns= pkgsel/install-language-support=false vga=normal initrd=ubuntu-installer/i386/initrd.gz -- console=ttyS0,19200
       -----------------------------------------------------------------------------------------------------------
 
       NOTE: - "tasks=server" in the "append" line tells the installer to install a Ubuntu server. Use "tasksel --list-tasks" 
               to get other options for tasks=...
             - Dont't forget to append "console=ttyS0,19200"
             - noplymouth turns of the grafical Boot Splash


        

6) Soekris and PXE
==================

   Note: These 2 comBIOS parameters must be set as follows, otherwise the net5501 won't boot from PXE.

     - PCIROMS = Enabled                                                             
     - PXEBoot = Enabled 

   Note: Typ "show" in comBIOS prompt to see all comBIOS settings.


   6.1) Boot from PXE:

        > boot F0

        Now, at the "boot:" prompt typ:

        > install

        That's the name of the "label" in /var/lib/tftpboot/ubuntu-installer/i386/boot-screens/text.cfg

        Note: At the beginning of the installation it is likely that you won't see any output for a while (~ 10-15 min.).
              But this will normally change and the system download will start.
        Note: Don't forget to use the partition scheme mentioned above.
        Note: After the installation the OS doesn't start automatically from CF.

        To start it manually, typ:

        > boot 80        

        Note: 80 = 1. dev.

        This of course only works if the CF is the Primary Master device. 
        To verify that, watch the net5501 boot screen (Pri Mas):

        -------------------------------------------------------------------------------
        0512 Mbyte Memory                        CPU Geode LX 500 Mhz                  
                                                                               
        Pri Mas  SanDisk CompactFlash 200x       LBA Xlt 971-128-63  3917 Mbyte
        -------------------------------------------------------------------------------


        AND in the comBIOS settings check this option by entering "show":

        -------------------------------------------------------------------------------
        FLASH = Primary
        -------------------------------------------------------------------------------
       

        - Workaround to let Soekris automatically boot from CF: 

        Set the following option after entering the comBIOS monitoring mode (press CTRL+P at boot time)

        > set BootDrive=80 80 F0

        Note: - 80 = 1. device
              - 81 = 2. device
              - F0 = PXE

        Note: Default is:  BootDrive=80 81 F0 FF


That's it.  

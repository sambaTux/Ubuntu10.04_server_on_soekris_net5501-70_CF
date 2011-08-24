#!/bin/bash

#Title        : os-config.sh
#Author       : sambaTux <sambatux@web.de>
#Start date   : 09.08.2011
#Finish date  : 13.08.2011
#OS tested    : Ubuntu10.04
#OS supported : Ubuntu10.04 ...
#BASH version : 4.1.5(1)-release
#Requires     : 
#Version      : 0.1
#Task(s)      : configure OS to run on Compact Flash


#define vars
grub_conf='/etc/default/grub'     
rd='ramdisk_size=170000'          #~170MB. Size for /dev/ramX devices.
con='console=ttyS0,19200'         #serial console settings needed for soekris net5501
el='elevator=noop'                #best for flash memory
ply='noplymouth'                  #turn of plymouth boot splash

#set kernel parameter 
if [[ -f "$grub_conf" ]]; then
   cp -p "$grub_conf" ${grub_conf}.bak
   sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="'$rd' '$con' '$el' '$ply'"/' "$grub_conf" \
   && update-grub
fi

#turn off counter based fsck for root dev
rootdev=`rdev | cut -d ' ' -f 1`
tune2fs -c -1 "$rootdev"

#deactivate  "multiverse" and "universe" repos in order to save ~60MB in /var/lib/apt/lists/
sources="/etc/apt/sources.list"
if [[ -f "$sources" ]]; then
   cp -p "$sources" ${sources}.bak
   sed -i 's/^deb.*\(universe\|multiverse\)$/#&/' "$sources" \
   && apt-get update
fi

#set swappiness to 0 (def. = 60). 0 means that the kernel should preferably not use the swapp partition.
sysctl="/etc/sysctl.conf"
if [[ -f "$sysctl" ]]; then
   echo "" >>"$sysctl"
   echo "#set swappiness to 0, meaning that the swapp partition should preferably not be used by the kernel" >>"$sysctl"
   echo "vm.swappiness=0" >>"$sysctl"
fi

#create mount points for the logfiles of "var2rd.sh" and "varbak.sh"
#The scripts will mount a tmpfs to hold the logfiles while their exec. 
mkdir -m 700 /media/var2rd
mkdir -m 700 /media/varbak

#create /var/err. See var2rd.sh (at the top) to know why.  
mkdir -m 700 /var/err

exit 0

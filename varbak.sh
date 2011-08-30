#!/bin/bash

# Title        : varbak.sh
# Author       : sambaTux <sambatux@web.de>
# Start date   : 09.08.2011
# OS tested    : ubuntu10.04
# BASH version : 4.1.5(1)-release
# Requires     : grep pgrep free expr du uniq awk sed cut cat lsof touch
#                initctl find rsync ps killall mount umount chmod mkdir 
# Version      : 0.2
# Script type  : cronjob, shutdown
# Task(s)      : copy files from /var ramdisk to /var on CompactFlash (CF).  

# NOTE         : - The /varbak/err/err.txt must be delete manually after a failure occured.
#                - The "error-led.sh" script is started as bg job.

# LICENSE      : Copyright (C) 2011 Robert Schoen

#                This program is free software: you can redistribute it and/or modify it under the terms 
#                of the GNU General Public License as published by the Free Software Foundation, either 
#                version 3 of the License, or (at your option) any later version.
#                This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
#                without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
#                See the GNU General Public License for more details. [http://www.gnu.org/licenses/]


###################################################################################
###################################################################################
###   SECTION: Trap

# Path to "error-led.sh" script.
error_led="/usr/local/sbin/error-led.sh"

# This function is executed by "trap" and therefore not defined in the "function" section 
function lastact() {

  dt=`date +%Y.%m.%d-%H:%M:%S`

  # Create "err.txt" to publish an error. This mark will also be checked 
  # by the script varbak.sh. If this file exists, varbak.sh and var2rd.sh won't run !!
  errdir="/varbak/err"
  err="${errdir}/err.lock"
  errlf="${errdir}/varbak-error.log"

  # We need to check if /varbak (tmpfs) is not already mounted.
  # If so, we have to unmount it first in order to save the error logfile on /varbak (CF),
  # and not on /varbak (tmpfs); else we would lose the logfile after reboot.
  tempfs=`df -hT | grep '^tmpfs.*/varbak$'`

  # Lazy unmount /varbak (tmpfs). Not nice ...
  [[ -n "$tempfs" ]] && umount -l /varbak 
  
  # Create error dir, if not already done
  [[ ! -d "$errdir" ]] && mkdir -m 700 "$errdir"

  # Create err.txt
  echo "A fatal error occured !!!!" >"$err"
  echo "That means that neither var2rd.sh nor varbak.sh will start again until this file is deleted." >>"$err"
  echo "This file was created by $0 at $dt" >>"$err"
  echo "Please investigate ... " >>"$err"  
  chmod 400 "$err"

  # Save logfile (or piece of it)
  if [[ -e "$lf" ]]; then
     cat "$lf" >>"$errlf"
  fi

  # Activate error led
  "$error_led" --fatal "$errlf" &
  exit 1
}

# If sth. goes wrong ...
trap 'lastact' TERM KILL INT


###################################################################################
###################################################################################
###   SECTION: Misc.

# Are we root?
[[ $(id -u) -ne 0 ]] && echo "ERROR: Must be root!" && exit 1

# Check if var2rd.sh hasn't produced any error. If so, this script can be executed, 
# otherwise not.
errdir="/varbak/err"
err="${errdir}/err.txt"

if [[ -e "$err" ]]; then
   echo "ERROR: $err exists! Aborting ..."

   # Activate error led
   "$error_led" --fatal &
   exit 1
fi

# In order to have a safe place for the logfile, when this script crashes, we have to make sure
# that /var/err/ exists. In case that a script fails, it will write the logfile to 
# /varbak/err/. Yes, /varbak/err. We can only tell rsync to exclude dirs or
# files in the source, and not in the destination. Thus, we create /var/err/ in the source 
# in order to preserve /varbak/err while syncing /varbak with /var.
[[ ! -d /var/err ]] && mkdir -m 700 /var/err


###################################################################################
###################################################################################
###   SECTION: Define vars and configure script

# stop_list       Assoc. array of processes that should be stopped. We need a assoc. array to keep the name 
#                 and type (upstart / initV / non-daemon) of a process.
#                 This array is filled automatically!
# stop_excludes   Array of processes that should NOT be stopped. 
#                 I.e ssh during system startup.
#                 This array must be filled manually.
# start_excludes  Array of processes that we don't want to start again after stopping them. 
#                 I.e. dhclient3. Usefull when we mount the root fs in read only.
#                 This array must be filled manually.

# NOTE: A "start_list" assoc. array is not requiered. 
#       We simply use the "stop_list" and "start_excluded" arrays instead.
declare -a stop_excludes start_excludes
declare -A stop_list  

stop_excludes=("`basename "$0"`" "grep" "cut" "uniq")
start_excludes=("dhclient3" "dhclient")


# NOTE: sizes are in MB.
lfdir="/media/varbak"         #mount point for logfile
lf="${lfdir}/varbak.log"      #logfile
logtmpfs_size="200k"          #size for logfile tmpfs
t=`date +%Y.%m.%d-%H:%M:%S`
var="/var"
varbak="/varbak"
memtotal=`free -m | grep '^Mem:' | awk -F ' ' '{ print $2 }'`      #total system RAM
memused=`free -m | grep '^Mem:' | awk -F ' ' '{ print $3 }'`       #RAM currently used by OS
memdiff=`expr $memtotal - $memused`                              
mempeak=`expr $memtotal / 4 \* 3`                                  #set RAM threshold
varsize=`du -sh "$var" | awk -F ' ' '{ print $1 }' | sed 's/.$//'` #current size of /var (CF)
tmpfssize=`expr $varsize + 10`                                     #set tmpfs size used for data sync. 
maxtmpfssize="170"                                    #max. size of tmpfs for data sync.
rdmountopts="-t ext2 -o rw,nosuid,nodev,nouser"       #ramdisk mount options
rsyncopts="-rogptl --delete-before"                   #options for rsync cmd
ramdisk="/dev/ram0"


# Check if "var2rd.sh" has created the mount point for the logfile (tmpfs).
# If not try to create it. Hopefully /media is not mounted in read only. 
if [[ ! -d "$lfdir" ]]; then 
   [[ ! `mkdir -m 700 "$lfdir"` ]] && exit 1
fi


# To keep the logfile of this script while its running, we need a temporary place
# until this script has done its job. This is because we are doing a mount round trip. 
# Hence we will mount a tmpfs somewhere to keep the logfile for a while.
mount -t tmpfs -o rw,size="$logtmpfs_size",mode=600 tmpfs "$lfdir"


# Create logfile if not already done
if [[ ! -f "$lf" ]]; then
   touch "$lf"
   chown root.root "$lf"
   chmod 0640 "$lf"
fi


# Insert start flag into logfile
echo "" >>"$lf"
echo "##################################################" >>"$lf"
echo "["$t"]: START "$0"" >>"$lf"


# Check if /dev/ram0 is mounted!! This means that var2rd.sh has been invoked
# and everything should be ready for this script to work.
rd=`mount | grep -wo "/dev/ram0"`

if [[ -z "$rd" ]]; then
   echo "ERROR: /dev/ram0 not mounted. Aborting ..." >>"$lf"
   exit 1
fi


# Is /var and /varbak a partition
varpart=`df -h |  grep "$var"$ | awk -F' ' '{ print $3 }'`
varbakpart=`df -h |  grep "$varbak"$ | awk -F' ' '{ print $3 }'`

if [[ -z "$varbak" ]] || [[ -z "$varbakpart" ]]; then
   echo "["$t"]: ERROR: $varpart or $varbakpart is not a partition! Aborting ..." >>"$lf"
   exit 1
fi

# Write info summary into logfile
echo "SUMMARY:" >>"$lf"
echo "MemTotal:       $memtotal MB"     >>"$lf"
echo "MemUsed:        $memused MB"      >>"$lf"
echo "MemDiff:        $memdiff MB"      >>"$lf"
echo "MemPeak:        $mempeak MB"      >>"$lf"
echo "/var size:      $varsize MB"      >>"$lf"
echo "tmpfs size:     $tmpfssize MB"    >>"$lf"
echo "ramdisk:        $ramdisk "      >>"$lf"
echo "Max tmpfs size: $maxtmpfssize MB" >>"$lf"
echo "" >>"$lf" 


###################################################################################
###################################################################################
###   SECTION: Define functions

# This function classifies the type of a process (upstart / initV / non-daemon)
function get_ptype() {

   # NOTE: initctl uses exit code 1 for errors AND daemons that are already stopped/started!
   #       Hence we cannot use exit codes here.
   ptype=`initctl list | grep -wo "$p"`

   if [[ -n "$ptype" ]]; then
      # p is upstart      
      echo "INFO: "$p" is an upstart daemon." >>"$lf"
      ptype="upstart"

   elif [[ -x /etc/init.d/"$p" ]]; then
        # p is initV
        echo "INFO: "$p" is an initV daemon." >>"$lf"
        ptype="initV"

   else
        # p is non-daemon   
        echo "INFO: "$p" is a non-daemon." >>"$lf"
        ptype="non-daemon"
   fi

}


# This function kills non-daemons and checks if they are really dead
function pkiller() {

 echo "INFO: "$p" is a non-daemon. Killing it gracefully ..." >>"$lf"
 killall -e -15 "$p" >>"$lf" 2>&1

 # Check if process was really killed, if not, try to kill it hardly
 if [[ $(ps -e | grep -wo "$p") ]]; then
    echo "INFO: Non-daemon "$p" is unwilling to die. Killing it brutal ..." >>"$lf"
    killall -e -9 "$p" >>"$lf" 2>&1

    # Check again if process is really dead
    if [[ ! $(ps -e | grep -wo "$p") ]]; then
       echo "INFO: Non-daemon "$p" killed." >>"$lf"
    else
       echo "ERROR: Non-daemon "$p" is immortal !! Aborting..." >>"$lf"
       exit 1
    fi
 else
    echo "INFO: Non-daemon "$p" killed." >>"$lf"
 fi
}


# This function checks if a process is really dead
function chkd() {
  if [[ `pgrep -g $pid` ]]; then
     echo "ERROR: Could not stop "$p". Aborting..." >>"$lf"
     exit 1
  else
     echo "INFO: "$p" really killed/stopped." >>"$lf"
  fi
}


# This funcition stops daemons/non-daemons
function pstopper() {
  
  n=1

  # Stop all daemons/non-daemons
  for p in ${!stop_list[@]} ; do

    # Get p PID for the "chkd" function.
    pid=`pgrep "$p"`

    echo "STOP-$n: Stopping "$p" ..." >>"$lf"

    # Stop p
    case ${stop_list["$p"]} in
         "upstart")  initctl stop "$p" >>"$lf" 2>&1
                     chkd
         ;;

         "initV")    /etc/init.d/${p} stop >>"$lf" 2>&1
                     chkd
         ;;

         "non-daemon") pkiller
         ;;
    esac

    echo "STOP-$n: Done." >>"$lf"

    # Inc.
    ((n++))
  done
  echo "INFO: all deamons/non-daemons stopped." >>"$lf"

}

# This function writes data from /var (ramdisk) back to /var on CF
function syncer() {

  # Delete all regular files in /var/cache, but keep dir. struct. 
  # that saves ~30MB in /var/cache/ (at least after OS installation)
  echo "FIND: Start deleting regular files in /var/cache" >>"$lf"
  find /var/cache/ -type f -exec rm -r '{}' \; >/dev/null 2>>"$lf"
  echo "FIND: Done." >>"$lf"

  # Sync /varbak (tmpfs/CF) with /var (ramdisk)
  echo "RSYNC: Start sync $varbak (tmpfs/CF) with $var (ramdisk)"  >>"$lf" 2>&1
  rsync $rsyncopts "${var}/" "${varbak}/" 2>> "$lf"
  echo "RSYNC: Done." >>"$lf"

  # Unmount /var (ramdisk)
  echo "UMOUNT: Unmounting ${ramdisk} ..." >>"$lf"
  umount "$ramdisk" >>"$lf" 2>&1 
  echo "UMOUNT: Done." >>"$lf"

  # Sync /var (CF) with /varbak (tmpfs/CF)
  echo "RSYNC: Start sync $var (CF) with $varbak (tmpfs/CF)" >>"$lf"
  rsync $rsyncopts "${varbak}/" "${var}/" 2>>"$lf"
  echo "RSYNC: Done." >>"$lf"

  # Mount /var (ramdisk) again
  echo "MOUNT: Mounting ramdisk on $var (CF)" >>"$lf"
  mount $rdmountopts "$ramdisk" "$var" >>"$lf" 2>&1
  echo "MOUNT: Done." >>"$lf"

}

# This function starts daemons/non-daemons
function pstarter() {
   
   # Start daemons/non-daemons again, but ignore those mentioned in "start_exclude" array.
   echo "START: Starting daemons/non-daemons again..." >>"$lf"
   for p in ${!stop_list[@]} ; do

     match=0
     for px in ${start_excludes[@]}; do
         if [[ "$px" = "$p" ]]; then
            echo "INFO: Will not start "$p", as configured." >>"$lf"
            match=1
         fi
     done

     # Start p
     if [[ $match -eq 0 ]]; then

        case ${stop_list["$p"]} in
             "upstart")     echo "INFO: Starting upstart daemon "$p" ..." >>"$lf"
                            initctl start "$p" >>"$lf" 2>&1
             ;;
             "initV")       echo "INFO: Starting initV daemon "$p" ..." >>"$lf"
                            /etc/init.d/"$p" start >>"$lf" 2>&1
             ;;
             "non-daemon")  echo "INFO: Starting non-daemon "$p" ..." >>"$lf"
                            "$p" >>"$lf" 2>&1
             ;;
        esac
     fi
   done
echo "START: Done." >>"$lf"

}


###################################################################################
###################################################################################
###   SECTION: Main program

# Get a list of daemons/non-daemons that are currently accessing /var
plist=`lsof +c 15 2>/dev/null | grep "$var" | cut -d ' ' -f 1 | uniq`

echo "LIST: List of daemons/non-daemons that are accessing $var" >>"$lf"
echo "$plist" >>"$lf"
echo "" >>"$lf"

# Build array "stop_list" with captured daemons/non-daemons, but ignore those 
# mentioned in the "stop_excludes" array
for p in $plist; do

  # Rename rsyslogd to rsyslog !!
  if [[ "$p" = "rsyslogd" ]]; then
     echo "INFO: Renaming rsyslogd to rsyslog." >>"$lf"
     p="rsyslog"
  fi

  # Exclude p
  match=0
  for px in ${stop_excludes[@]}; do
      if [[ "$px" = "$p" ]]; then
         match=1
         echo "INFO: Excluding "$p" from stop_list." >>"$lf"
      fi
  done

  # Build assoc. array "stop_list"
  if [[ $match -eq 0 ]]; then
     # Get p type 
     get_ptype

     # fill array
     echo "INFO: Adding "$p" to stop_list." >>"$lf"
     stop_list["$p"]="$ptype"
  fi

done

echo "" >>"$lf"


# If used memory is greater than memory peak, we will use /varbak on CF as a cache 
# to sync back data from /var ramdisk to /var on CF. Otherwise we use /varbak 
# tmpfs to sync back the data.

if [[ $memused -ge $mempeak ]]; then

   # Sync data by using /varbak on CF
   echo "INFO: Using varbak on CF because used RAM greater than configured RAM peak." >>"$lf"
   
   # Activate warning led because memused is greater than mempeak
   echo "INFO: Calling $error_led with --warning parameter ..." >>"$lf"
   "$error_led" --warning "$lf" & 

   # Stop daemons/non-daemons
   pstopper
   # Sync data
   syncer   
   # Start daemons/non-daemons again
   pstarter
   
elif [[ $memused -lt $mempeak ]] && [[ $varsize -gt $maxtmpfssize ]]; then

     # Use /varbak on CF because we dont want to accupy to much RAM.
     echo "INFO: Using varbak on CF because we do not have enough free RAM." >>"$lf"
    
     # Activate warning led because varsize is greater than maxtmpfssize
     echo "INFO: Calling $error_led with --warning parameter ..." >>"$lf"
     "$error_led" --warning "$lf" & 

     # Stop daemons/non-daemons
     pstopper
     # Sync data
     syncer
     # Start daemons/non-daemons again
     pstarter
else 
     # Use /varbak on tmpfs because we have enough free RAM
     echo "INFO: Using varbak on tmpfs because there is enough free RAM." >>"$lf"

     # Deactivate warning led because we have enough free RAM.
     echo "KILLALL: Killing $error_led ..." >>"$lf"
     killall -e -9 `basename $error_led` >>"$lf" 2>&1
     echo "KILLALL: Done." >>"$lf"
     echo "INFO: Calling $error_led with --warn-off parameter ..." >>"$lf"
     "$error_led" --warn-off "$lf" 
     
     # Mount tmpfs
     echo "MOUNT: Mount tmpfs with size $tmpfssize MB ..." >>"$lf"
     mount -t tmpfs -o size=${tmpfssize}M tmpfs "$varbak"
     echo "MOUNT: Done." >>"$lf"

     # Stop daemons/non-dameons
     pstopper   
     # Sync data
     syncer
     # Start daemons/non-daemon again
     pstarter
 
     # Umount tmpfs and free RAM again
     echo "UMOUNT: Unmounting tmpfs ..." >>"$lf"
     umount "$varbak"
     echo "UMOUNT: Done." >>"$lf" 
fi
 

# Copy logfile from tmpfs to /var (ramdisk)
# Note this logfile will be saved to CF (/var) only the next time 
# this script runs.
echo "CAT: Append "$lf" (tmpfs) to ${var}/log/varbak.log (ramdisk)" >>"$lf"
cat "$lf" >>"${var}/log/varbak.log"


# Change path to logfile 
lf="${var}/log/varbak.log"
echo "CAT: Done" >>"$lf"


# Unmount logfile tmpfs
echo "UMOUNT: Unmounting logfile tmpfs ..." >>"$lf"
umount "$lfdir"
echo "UMOUNT: Done." >>"$lf"


# Insert end flag into logfile
echo "" >>"$lf"
echo "["$t"]: END "$0"" >>"$lf"
echo "##################################################" >>"$lf"
echo "" >>"$lf"

 
exit 0

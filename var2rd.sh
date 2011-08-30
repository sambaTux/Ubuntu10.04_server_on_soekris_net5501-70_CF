#!/bin/bash

# Title        : var2rd.sh
# Author       : sambaTux <sambatux@web.de>
# Start date   : 09.08.2011
# OS tested    : Ubuntu10.04
# BASH version : 4.1.5(1)-release
# Requires     : grep pgrep uniq awk df cp cut cat lsof initctl find rsync mkfs ps killall
#                basename chmod chown mkdir mount umount
# Version      : 0.2
# Script type  : system startup (rc.local)
# Task(s)      : Create ramdisk for /var at system startup 

# NOTE         : - The /varbak/err/err.txt must be delete manually after a failure occured.
#                - SET "ramdisk_size=..." KERNEL PARAMETER in /etc/default/grub before running this script !!
#                  I.e. "ramdisk_size=170000" (~ 170 MB). And dont forget to invoke "update-grub" and "reboot" so
#                  that ramdisk size is active. This config can also be done with "os-config.sh" script.
#                - If you want to mount the root partition in read only mode, don't use this script but use 
#                  /etc/rc.local instead, because it's possible that the script disturbs itself while remounting /. 
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
  errlf="${errdir}/var2rd-error.log"
   
  # Create error dir if not already done
  [[ -d "$errdir" ]] || mkdir -m 700 "$errdir"

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
trap 'lastact' TERM INT KILL 


###################################################################################
###################################################################################
###   SECTION: Tests

# Are we root?
[[ $(id -u) -ne 0 ]] && exit 1

# Check if varbak.sh hasn't produced any error. If so, this script can be executed, 
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
if [[ ! -d /var/err ]]; then
   echo "MKDIR: Creating /var/err (CF) ..." 
   mkdir -m 700 /var/err
   echo "MKDIR: Done."
fi

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

stop_excludes=("`basename "$0"`" "grep" "cut" "uniq" "plymouthd" "rc.local" "ssh")
start_excludes=("dhclient3")

lfdir="/media/var2rd"       #mount point for the logfile (tmpfs)
lfdir2="/media/varbak"      #mount point for the logfile (tmpfs) of "varbak.sh"
lf="${lfdir}/var2rd.log"    #logfile
logtmpfs_size="200k"        #size for logfile tmpfs 
t=`date +%Y.%m.%d-%H:%M:%S` 
ramdisk="/dev/ram0"
var="/var"
varbak="/varbak"
rdfstype="-t ext2"                                    #option for mkfs AND mount.
rdmountopts="-o rw,nosuid,nodev,nouser"               #options for mount cmd to mount ramdisk
rdlabel="varrd"                                       #ramdisk label
rsyncopts1="-rogptl --delete-before"                             #sync /varbak/{run,lock} (CF) with /var/{run,lock} (tmpfs)
rsyncopts2="-rogptl --delete-before --exclude=err --exclude=run --exclude=lock"    #sync /varbak/ (CF) with /var/ (CF)
rsyncopts3="-rogptl --delete-before"                             #sync /var (ramdisk) with /varbak (CF)


# Create mount points for the logfile (tmpfs) of "var2rd.sh" and "varbak.sh"
# Creating it for "varbak.sh" now is usefull when we want to mount / in read only later.
if [[ ! -d "$lfdir" ]]; then
   echo "MKDIR: Creating mount point $lfdir ..."
   mkdir -m 700 "$lfdir" 
   echo "MKDIR: Done."
fi
if [[ ! -d "$lfdir2" ]]; then
   echo "MKDIR: Creating mount point $lfdir ..."
   mkdir -m 700 "$lfdir2"
   echo "MKDIR: Done."
fi


# To keep the logfile of this script while it is running, we need a temporary place
# until this script has done its job. This is because we are doing a mount round trip. 
# Hence we will mount a tmpfs somewhere to keep the logfile for a while.
echo "MOUNT: Mounting tmpfs for logfile ..."
mount -t tmpfs -o rw,size="$logtmpfs_size",mode=600 tmpfs "$lfdir"
echo "MOUNT: Done."


# Create logfile if not already done
if [[ ! -f "$lf" ]]; then
   echo "INFO: Creating logfile ..."
   touch "$lf"
   chown root.root "$lf"
   chmod 0600 "$lf"
fi


# Insert start flag into logfile
echo "" >>"$lf"
echo "#####################################################" >>"$lf"
echo "["$t"]: START "$0"" >>"$lf"


# Are /var and /varbak partitions
varpart=`df -h |  grep "$var"$ | awk -F' ' '{ print $3 }'`
varbakpart=`df -h |  grep "$varbak"$ | awk -F' ' '{ print $3 }'`

if [[ -z "$varpart" ]] || [[ -z "$varbakpart" ]]; then
   echo "["$t"]: ERROR: $var or $varbak is not a partition! Aborting ..." >>"$lf" 
   exit 1
fi


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


# This function checks if a daemon has really been stopped
function chkd() {
  if [[ `pgrep -g $pid` ]]; then
     echo "ERROR: Could not stop "$p". Aborting..." >>"$lf"
     exit 1
  else
     echo "INFO: "$p" really killed/stopped." >>"$lf"
  fi
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
unset p match

echo "" >>"$lf"

echo "INFO: Stopping daemons/non-daemons ..." >>"$lf"
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
unset p 


# Delete all regular files in /var/cache, but keep dir. struct. 
# This saves ~30MB in /var/cache/ (at least after OS installation)
echo "FIND: Deleting regular files in /var/cache" >>"$lf"
find /var/cache/ -type f -exec rm -r '{}' \; >/dev/null 2>>"$lf"
echo "FIND: Done." >>"$lf"


# Before we can unmount /var/lock and /var/run, we have to save their data first.
# That's because both dirs are using a tmpfs (at least on Ubuntu 10.04).
# The very first time this script runs, there is no /varbak/{run,lock} dir, thus we create it.
if [[ ! -d "${varbak}/run" ]]; then
   echo "MKDIR: Creating $varbak/run" >>"$lf"
   mkdir -m 755 "${varbak}/run" >> "$lf" 2>&1
   echo "MKDIR: Done." >>"$lf"
fi

if [[ ! -d "${varbak}/lock" ]]; then 
   echo "MKDIR: Creating $varbak/lock" >>"$lf"
   mkdir -m 1777 "${varbak}/lock" >>"$lf" 2>&1
   echo "MKDIR: Done." >>"$lf"
fi

echo "RSYNC: Start sync. /varbak/run (CF) with /var/run (tmpfs)" >>"$lf"
rsync $rsyncopts1 /var/run/ /varbak/run >>"$lf"
echo "RSYNC: Done." >>"$lf"
 
echo "RSYNC: Start sync. /varbak/lock (CF) with /var/lock (tmpfs)" >>"$lf"
rsync $rsyncopts1 /var/lock/ /varbak/lock >>"$lf"
echo "RSYNC: Done." >>"$lf"


# Unmount /var/lock and /var/run
echo "UMOUNT: Unmounting /var/lock and /var/run ..." >>"$lf"
umount "${var}/lock" >>"$lf" 2>&1
umount "${var}/run" >>"$lf" 2>&1
echo "UMOUNT: Done." >>"$lf"


# Sync /varbak with /var 
echo "RSYNC: Start sync. $varbak (CF) with $var (CF):" >>"$lf"
rsync $rsyncopts2 "${var}/" "${varbak}/" >>"$lf" 2>&1
echo "RSYNC: Done." >>"$lf"

 
# Format ramdisk 
echo "MKFS: Formating ramdisk ..." >>"$lf"
mkfs $rdfstype -m 0 -L "$rdlabel" "$ramdisk" >>"$lf" 2>&1 
echo "MKFS: Done." >>"$lf"


# Mount /var.
# NOTE: /var/run & /var/lock use tmpfs by default. We use ramdisk with ext2 instead.
echo "MOUNT: Mounting ramdisk on $var" >>"$lf"
mount $rdfstype $rdmountopts "$ramdisk" "$var" >>"$lf" 2>&1
echo "MOUNT: Done." >>"$lf"


# Sync /var (ramdisk) with /varbak (CF)
echo "RSYNC: Start syncing $var (ramdisk) with $varbak (CF)" >>"$lf"
rsync $rsyncopts3 "${varbak}/" "${var}/" >>"$lf" 2>&1
echo "RSYNC: Done." >>"$lf"


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


# Copy logfile from tmpfs to /var (ramdisk)
# NOTE: this logfile will NOT be saved to CF (/var) until the script
#       "varbak.sh" runs!
echo "CAT: Append "$lf" (tmpfs) to $var/log/var2rd.log (ramdisk)" >>"$lf"
cat "$lf" >>"${var}/log/var2rd.log"

# Change path to logfile
lf="${var}/log/var2rd.log"
echo "CAT: Done" >>"$lf"


# Unmount logfile tmpfs
echo "UMOUNT: Unmounting logfile tmpfs $lfdir ..." >>"$lf"
umount "$lfdir" >>"$lf" 2>&1
echo "UMOUNT: Done." >>"$lf"


# To ensure that "varbak.sh" can use the soekris error led, even if / is mounted
# in read only, this script prepares everthing for that usage, because now / is 
# still writable. "error-led.sh" uses the same logfile as this script does.
echo "INFO: Calling $error_led ..." >>"$lf"
"$error_led" --prepare "$lf"


# Insert end flag into logfile
echo "" >>"$lf"
echo "["$t"]: END "$0"" >>"$lf"
echo "#####################################################" >>"$lf"
echo "" >>"$lf"

exit 0

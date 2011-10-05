#!/bin/bash

# Title        : varbak.sh
# Author       : sambaTux <sambatux AT web DOT de>
# Start date   : 09.08.2011
# OS tested    : ubuntu10.04
# BASH version : 4.1.5(1)-release
# Requires     : grep pgrep free expr du uniq awk sed cut cat lsof touch
#                initctl find rsync ps killall mount umount chmod mkdir 
# Version      : 0.7
# Script type  : shutdown, reboot, cronjob
# Task(s)      : copy files from /var ramdisk/tmpfs to /var on CompactFlash (CF).  

# NOTE         : - The /varbak/err/err.lock must be delete manually after a failure occured.
#                - In case of an error/warning the "error-led.sh" script is started as bg job.

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

# Save command history of this script in array by using trap.
# This may be useful for debugging purpose in case of a script crash/error.
# This array is used by lastact().
declare -a cmdhist
trap 'cmdhist[${#cmdhist[@]}]=$BASH_COMMAND' DEBUG

# Path to "error-led.sh" script.
error_led="/usr/local/sbin/error-led.sh"

# This function is executed by "trap" and therefore not defined in the "function" section 
function lastact() {

  # Exec. trap code only if an explicit exit code > 0, or a SIG??? has been trapped.
  # Like this the harmless "exit 0" is omitted. 
  if (( $? != 0 )); then
     dt=`date +%Y.%m.%d-%H:%M:%S`

     # Create "err.lock" to publish an error. This mark will also be checked 
     # by the script varbak.sh. If this file exists, varbak.sh and var2rd.sh won't run !!
     errdir="/varbak/err"
     err="${errdir}/err.lock"
     errlf="${errdir}/varbak-error.log"

     # We need to check if /varbak (tmpfs) is already mounted.
     # If so, we have to unmount it first in order to save the error logfile on /varbak (CF),
     # and not on /varbak (tmpfs); else we would lose the logfile after unmounting tmpfs or a reboot.
     tempfs=`cat /proc/mounts | grep '^tmpfs /varbak '`

     # Lazy unmount /varbak (tmpfs). Not nice ...
     [[ -n "$tempfs" ]] && umount -l /varbak 
  
     # Create error dir, if not already done
     [[ ! -d "$errdir" ]] && mkdir -m 700 "$errdir"

     # Create err.lock
     echo "A fatal error occured !!!!" >>"$err"
     echo "That means that neither var2rd.sh nor varbak.sh will start again until this file is deleted." >>"$err"
     echo "This file was created by $0 at $dt" >>"$err"
     echo "Please investigate ... " >>"$err"     
     echo "" >>"$err"
     echo "Script cmd history:" >>"$err"
     for cmd in "${cmdhist[@]}"; do
         echo $cmd >>"$err"
     done
     echo "" >>"$err"  
     chmod 400 "$err"

     # Save logfile (or piece of it)
     if [[ -e "$lf" ]]; then
        cat "$lf" >>"$errlf"
     fi

     # Activate error led
     "$error_led" --fatal "$errlf" &
  fi
}

# If sth. goes wrong ...
trap 'lastact; exit 0' KILL TERM INT ERR EXIT


###################################################################################
###################################################################################
###   SECTION: Misc.

# Are we root?
[[ $(id -u) -ne 0 ]] && echo "ERROR: Must be root!" && exit 1

# Check if var2rd.sh hasn't produced any error. If so, this script can be executed, 
# otherwise not.
errdir="/varbak/err"
err="${errdir}/err.lock"

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
# rename_procs    Assoc. array to rename daemon/non-daemon processes which are using an other COMMAND name
#                 as their PROCESS name. I.e. "rsyslogd" becomes "rsyslog", or "mysqld" becomes "mysql", ...
#                 This array must be filled manually.

# NOTE: A "start_list" assoc. array is not requiered. 
#       We simply use the "stop_list" and "start_excluded" arrays instead.
declare -a stop_excludes start_excludes
declare -A stop_list rename_procs

stop_excludes=("`basename "$0"`" "grep" "cut" "uniq")
start_excludes=("dhclient3" "dhclient")
rename_procs=([rsyslogd]="rsyslog" [mysqld]="mysql")

# /sbin/init invokes this script in runlevel 0 & 6 with the "stop" argument.
# In that case we don't need to start the daemons/non-daemons again after they were stopped. 
# And we don't need to mount the /var ramdisk/tmpfs again.
syshalt="$1"

# NOTE: sizes are in MB.
lfdir="/media/varbak"         #mount point for logfile
lf="${lfdir}/varbak.log"      #logfile
logtmpfs_size="200k"          #size for logfile tmpfs
logtmpfsmountopts="rw,nosuid,nodev,nouser,noexec,size=200k,mode=600" #logfile tmpfs mount options
t=`date +%Y.%m.%d-%H:%M:%S`
var="/var"
varbak="/varbak"
memtotal=`free -m | grep '^Mem:' | awk -F ' ' '{ print $2 }'`      #total system RAM
memused=`free -m | grep '^Mem:' | awk -F ' ' '{ print $3 }'`       #RAM currently used by OS
memdiff=`expr $memtotal - $memused`                              
mempeak=`expr $memtotal / 4 \* 3`                                  #set RAM threshold
varsize=`du -sh "$var" | awk -F ' ' '{ print $1 }' | sed 's/.$//'` #current size of /var (CF)
tmpfssize=`expr $varsize + 10`                                     #set tmpfs size used for data sync.
tmpfssize="${tmpfssize}m"                                          #set tmpfs size in MB.
maxtmpfssize="170"                                                 #max. size of tmpfs for data sync.
ramdisk=`cat /proc/mounts | grep "/dev/ram." | cut -d ' ' -f 1`    #get ramdisk
rdfstype=`cat /proc/mounts | grep "/dev/ram." | awk -F ' ' '{ print $3 }'`                #get ramdisk fs type
rdmountopts=`cat /proc/mounts | grep "/dev/ram." | awk -F ' ' '{ print $(NF-2) }'`        #get ramdisk mount options
tmpfsmountopts=`cat /proc/mounts | grep "^tmpfs $var " | awk -F ' ' '{ print $(NF-2) }'`  #get /var (tmpfs) mount options
rsyncopts="-rogptlD --delete-before"                                                      #options for rsync cmd


# Check if "var2rd.sh" has created the mount point for the logfile (tmpfs).
# If not try to create it. Hopefully /media is not mounted in read only. 
if [[ ! -d "$lfdir" ]]; then 
   if [[ ! `mkdir -m 700 "$lfdir"` ]]; then
      echo "ERROR: Missing my mount point $lfdir. Aborting ..."
      exit 1
   fi
fi


# To keep the logfile of this script while its running, we need a temporary place
# until this script has done its job. This is because we are doing a mount round trip. 
# Hence we will mount a tmpfs somewhere to keep the logfile for a while.
mount -t tmpfs -o $logtmpfsmountopts tmpfs "$lfdir"


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


# Check if /dev/ram? or tmpfs is mounted on /var!! 
# This means that var2rd.sh has been invoked and everything should be 
# ready for this script, or this script ran earlier without an error.
if [[ -z "$ramdisk" ]] && [[ -z "$tmpfsmountopts" ]]; then
   echo "ERROR: No $ramdisk and tmpfs mounted on $var !! Aborting ..." >>"$lf"
   exit 1
elif [[ -n "$ramdisk" ]]; then 
     # Mark that we are using rd on /var. Info needed to unmount /var later.
     echo "INFO: var2rd.sh has mounted $ramdisk on $var." >>"$lf"
     method="rd"
elif [[ -n "$tmpfsmountopts" ]]; then
     # Mark that we are using tmpfs on /var. Info needed to unmount /var later.
     echo "INFO: var2rd.sh has mounted tmpfs on $var." >>"$lf"
     method="tmpfs"
fi


# Is /var and /varbak a partition
varpart=`df -h |  grep "$var"$ | awk -F' ' '{ print $3 }'`
varbakpart=`df -h |  grep "$varbak"$ | awk -F' ' '{ print $3 }'`

if [[ -z "$varbak" ]] || [[ -z "$varbakpart" ]]; then
   echo "["$t"]: ERROR: $varpart or $varbakpart is not a partition! Aborting ..." >>"$lf"
   exit 1
fi

# Write brief overview into logfile
echo "" >>"$lf"
echo "MemTotal:            $memtotal MB"     >>"$lf"
echo "MemUsed:             $memused MB"      >>"$lf"
echo "MemDiff:             $memdiff MB"      >>"$lf"
echo "MemPeak:             $mempeak MB"      >>"$lf"
echo "$var size:           $varsize MB"      >>"$lf"
echo "$varbak tmpfs size:  ${tmpfssize%?} MB"     >>"$lf"
echo "tmpfs max. size:     $maxtmpfssize MB"      >>"$lf"
echo "ramdisk (rd):        ${ramdisk:--}"         >>"$lf"
echo "rd fs:               ${rdfstype:--}"        >>"$lf"
echo "rd mount opts:       ${rdmountopts:--}"     >>"$lf"
echo "tmpfs mount opts:    ${tmpfsmountopts:--}"  >>"$lf"
echo "rsync opts:          $rsyncopts"            >>"$lf"
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


# This function kills non-daemons and checks if they are really dead.
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
  if [[ `pgrep "$p"` ]]; then
     echo "ERROR: Could not stop "$p". Aborting..." >>"$lf"
     exit 1
  else
     echo "INFO: "$p" really killed/stopped." >>"$lf"
  fi
}


# This function stops daemons/non-daemons
function pstopper() {
  
  n=1

  # Stop all daemons/non-daemons
  for p in ${!stop_list[@]} ; do

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
  echo "INFO: all daemons/non-daemons stopped." >>"$lf"

}

# This function writes data from /var (ramdisk/tmpfs) back to /var (CF).
# In case of a system reboot/shutdown, this function will not remount 
# a ramdisk/tmpfs on /var, otherwise it will.
function syncer() {

  # Delete all regular files in /var/cache, but keep dir. struct. 
  # that saves ~30MB in /var/cache/ (at least after OS installation)
  echo "FIND: Start deleting regular files in /var/cache" >>"$lf"
  find /var/cache/ -type f -exec rm -r '{}' \; >/dev/null 2>>"$lf"
  echo "FIND: Done." >>"$lf"

  # Sync /varbak (tmpfs/CF) with /var (ramdisk/tmpfs)
  echo "RSYNC: Start sync $varbak (tmpfs/CF) with $var (ramdisk/tmpfs)" >>"$lf" 2>&1
  rsync $rsyncopts "${var}/" "${varbak}/" 2>> "$lf"
  echo "RSYNC: Done." >>"$lf"

  # Unmount /var (ramdisk/tmpfs)
  if [[ "$method" = "rd" ]]; then
     echo "UMOUNT: Unmounting $ramdisk ..." >>"$lf"
     umount "$ramdisk" >>"$lf" 2>&1 

  elif [[ "$method" = "tmpfs" ]]; then
     echo "UMOUNT: Unmounting $var (tmpfs) ..." >>"$lf"
     umount "$var" >>"$lf" 2>&1
  fi
  echo "UMOUNT: Done." >>"$lf"

  # Sync /var (CF) with /varbak (tmpfs/CF)
  echo "RSYNC: Start sync $var (CF) with $varbak (tmpfs/CF)" >>"$lf"
  rsync $rsyncopts "${varbak}/" "${var}/" 2>>"$lf"
  echo "RSYNC: Done." >>"$lf"

  # Mount /var (ramdisk/tmpfs) again, only if we are not in a system reboot/shutdown process.
  if [[ "$syshalt" != "stop" ]]; then
     echo "INFO: System is NOT in reboot/shutdown process ..." >>"$lf"

     if [[ "$method" = "rd" ]]; then
        echo "MOUNT: Mounting $ramdisk on $var (CF)" >>"$lf"
        mount -t $rdfstype -o $rdmountopts "$ramdisk" "$var" >>"$lf" 2>&1
        echo "MOUNT: Done." >>"$lf"

     elif [[ "$method" = "tmpfs" ]]; then 
          echo "MOUNT: Mounting tmpfs on $var (CF)" >>"$lf"   
          mount -t tmpfs -o $tmpfsmountopts tmpfs "$var" >>"$lf" 2>&1
          echo "MOUNT: Done." >>"$lf"

         # Unlike ramdisk, tmpfs loses all data after unmounting it.
         # Hence we have to sync. /var (tmpfs) with /varbak (tmpfs/CF).
         echo "RSYNC: Start sync $var (tmpfs) with $varbak (tmpfs/CF)" >>"$lf" 
         rsync $rsyncopts "${varbak}/" "${var}/" >>"$lf" 2>&1
         echo "RSYNC: Done." >>"$lf"
     fi
  else
     echo "INFO: System is in reboot/shutdown process ..." >>"$lf"
     echo "...   Thus remounting ramdisk/tmpfs on $var is needless." >>"$lf"
  fi

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
   
  # Rename processes. This is needed because some procs have COMMAND names which are different 
  # from their PROC names.
  # I.e. "rsyslogd" => "rsyslog", "mysqld" => "mysql" ...
  for pr in "${!rename_procs[@]}"; do
      if [[ "$pr" = "$p" ]]; then
         echo "INFO: Renaming $pr to ${rename_procs[$pr]}." >>"$lf"
         p=${rename_procs[$pr]}
      fi
  done

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
# to sync back data from /var ramdisk/tmpfs to /var on CF. Otherwise we use /varbak 
# tmpfs to sync back the data.

if [[ $memused -ge $mempeak ]]; then

   # Sync data by using /varbak on CF
   echo "INFO: Using varbak on CF because used RAM greater than configured RAM peak." >>"$lf"
   
   
   # Deactivate running error-led.sh and activate warning led because memused is greater than mempeak.
   # But don't do it if we are in reboot/shutdown process.
   if [[ "$syshalt" != "stop" ]]; then
      if [[ $(pgrep $(basename "$error_led")) ]]; then
         echo "KILLALL: Killing $error_led ..." >>"$lf"
         killall -e -9 `basename "$error_led"` >>"$lf" 2>&1
         echo "KILLALL: Done." >>"$lf"
      fi
      echo "INFO: Calling $error_led with --warning parameter ..." >>"$lf"
      "$error_led" --warning "$lf" & 
   fi

   # Stop daemons/non-daemons
   pstopper
   # Sync data
   syncer   
   # Start daemons/non-daemons again, but only if we are not in system reboot/shutdown process.
   if [[ "$syshalt" != "stop" ]]; then
      pstarter
   else
      echo "INFO: We are in reboot/shutdown process...will not restart daemons/non-daemons." >>"$lf"
   fi
   
elif [[ $memused -lt $mempeak ]] && [[ $varsize -gt $maxtmpfssize ]]; then

     # Use /varbak on CF because we dont want to accupy to much RAM.
     echo "INFO: Using varbak on CF because we do not have enough free RAM." >>"$lf"
    
     # Deactivate running error-led.sh an activate warning led because varsize is greater than maxtmpfssize.
     # But don't do it if we are in reboot/shutdown process.
     if [[ "$syshalt" != "stop" ]]; then
        if [[ $(pgrep $(basename "$error_led")) ]]; then
           echo "KILLALL: Killing $error_led ..." >>"$lf"
           killall -e -9 `basename "$error_led"` >>"$lf" 2>&1
           echo "KILLALL: Done." >>"$lf"
        fi
        echo "INFO: Calling $error_led with --warning parameter ..." >>"$lf"
        "$error_led" --warning "$lf" & 
     fi

     # Stop daemons/non-daemons
     pstopper
     # Sync data
     syncer
     # Start daemons/non-daemons again, but only if we are not in system reboot/shutdown process.
     if [[ "$syshalt" != "stop" ]]; then
        pstarter
     else
        echo "INFO: We are in reboot/shutdown process...will not restart daemons/non-daemons." >>"$lf"
     fi
else 
     # Use /varbak on tmpfs because we have enough free RAM
     echo "INFO: Using varbak on tmpfs because there is enough free RAM." >>"$lf"

     # Deactivate running error-led.sh and warning led because we have enough free RAM.
     # But don't do it if we are in reboot/shutdown process.
     if [[ "$syshalt" != "stop" ]]; then
        if [[ $(pgrep $(basename "$error_led")) ]]; then 
           echo "KILLALL: Killing $error_led ..." >>"$lf"
           killall -e -9 `basename "$error_led"` >>"$lf" 2>&1
           echo "KILLALL: Done." >>"$lf"
        fi
        echo "INFO: Calling $error_led with --warn-off parameter ..." >>"$lf"
        "$error_led" --warn-off "$lf" 
     fi
     
     # Mount tmpfs for data sync.
     echo "MOUNT: Mount tmpfs on $varbak with size ${tmpfssize%?} MB ..." >>"$lf"
     mount -t tmpfs -o size=${tmpfssize} tmpfs "$varbak"
     echo "MOUNT: Done." >>"$lf"

     # Stop daemons/non-dameons
     pstopper   
     # Sync data
     syncer
     # Start daemons/non-daemons again, but only if we are not in system reboot/shutdown process.
     if [[ "$syshalt" != "stop" ]]; then
        pstarter
     else
        echo "INFO: We are in reboot/shutdown process...will not restart daemons/non-daemons." >>"$lf"
     fi 

     # Umount tmpfs and free RAM again
     echo "UMOUNT: Unmounting $varbak (tmpfs) ..." >>"$lf"
     umount "$varbak"
     echo "UMOUNT: Done." >>"$lf" 
fi
 

# Copy logfile from tmpfs to /var (ramdisk/tmpfs/CF)
# Note this logfile will be saved to CF (/var) only the next time 
# this script runs, or if we are in reboot/shutdown process.
echo "CAT: Append "$lf" (tmpfs) to ${var}/log/varbak.log (ramdisk/tmpfs)" >>"$lf"
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

# Happy end 
exit 0

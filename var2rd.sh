#!/bin/bash

# Title        : var2rd.sh 
# Author       : sambaTux <sambatux AT web DOT de>
# Start date   : 09.08.2011
# OS tested    : Ubuntu10.04
# BASH version : 4.1.5(1)-release
# Requires     : grep pgrep uniq awk sed df cp cut cat lsof initctl find rsync mkfs ps killall
#                basename chmod chown mkdir mount umount tune2fs touch rdev 
# Version      : 0.7
# Script type  : system startup (rc.local)
# Task(s)      : Create and mount ramdisk or tmpfs on /var at system startup 

# NOTE         : - The /varbak/err/err.lock must be delete manually after a failure occured.
#                - If you want to use a ramdisk, do the following first: 
#                  SET "ramdisk_size=..." KERNEL PARAMETER in /etc/default/grub before running this script !!
#                  I.e. "ramdisk_size=170000" (~ 170 MB). And dont forget to invoke "update-grub" and "reboot" so
#                  that ramdisk size is active. This config can also be done with "os-config.sh" script.
#                - If you want to mount the root partition in read only mode, don't use this script but use 
#                  /etc/rc.local instead, because it's possible that the script disturbs itself while remounting /. 
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
     errlf="${errdir}/var2rd-error.log"
   
     # Create error dir if not already done
     [[ -d "$errdir" ]] || mkdir -m 700 "$errdir"

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
###   SECTION: Tests

# Are we root?
[[ $(id -u) -ne 0 ]] && exit 1

# Check if varbak.sh hasn't produced any error. If so, this script can be executed, 
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
#                 I.e ssh during system startup or this script itself.
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

stop_excludes=("`basename "$0"`" "grep" "cut" "uniq" "plymouthd" "rc.local" "ssh")
start_excludes=("dhclient3")
rename_procs=([rsyslogd]="rsyslog" [mysqld]="mysql")

# Use ramdisk or tmpfs for /var. Options are: "rd" and "tmpfs".
# tmpfs:   - Pro:    RAM size grows/shrinks dynamically.
#          - Contra: tmpfs uses swap partition if necessary, even with swappiness = 0.
# ramdisk: - Pro:    Never uses swap partition. 
#          - Contra: RAM size is static.
rdORtmpfs="tmpfs"             

lfdir="/media/var2rd"       #mount point for the logfile (tmpfs)
lfdir2="/media/varbak"      #mount point for the logfile (tmpfs) of "varbak.sh"
lf="${lfdir}/var2rd.log"    #logfile
logtmpfsmountopts="rw,nosuid,nodev,nouser,noexec,size=200k,mode=600" #logfile tmpfs mount options
t=`date +%Y.%m.%d-%H:%M:%S` 
ramdisk="/dev/ram0"
var="/var"
varlock=`df | awk '/\/var\/lock$/ {print $NF}'`  #is /var/lock a partition. Note: Unlike grep, awk uses exit code 0 if 
#                                                                                 it doesn't find pattern. This is important to 
#                                                                                 not invoke "trap" by mistake. 
varrun=`df | awk '/\/var\/run$/ {print $NF}'`    #is /var/run a partition.       
varbak="/varbak"
rdfstype="ext2"                            #ramdisk fs type for mkfs AND mount! 
rdmountopts="rw,nosuid,nodev,nouser"       #ramdisk mount options
rdlabel="varrd"                            #ramdisk label
rdfsck="off"                               #turn on/off /var (ramdisk) fsck. Options are: "on" and "off"
rootfsck="off"                             #turn on/off / fsck. Options are: "on" and "off"
tmpfsmountopts="rw,nosuid,nodev,nouser,size=200m"  #tmpfs mount options
rsyncopts1="-rogptlD --delete-before"                             #sync /varbak/{run,lock} (CF) with /var/{run,lock} (tmpfs)
rsyncopts2="-rogptlD --delete-before --exclude=err --exclude=run --exclude=lock"    #sync /varbak/ (CF) with /var/ (CF)
rsyncopts3="-rogptlD --delete-before"                             #sync /var (ramdisk) with /varbak (CF)

# Make sure that this script doesn't run serveral times (for whatever reason).
rdexists=`df | grep -wo ^"$ramdisk ".*" $var"$ || :`
tmpfsexists=`df | grep -wo ^"tmpfs ".*" $var"$ || :`

if [[ -n "$rdexists" || -n "$tmpfsexists" ]]; then
   echo "ERROR: `basename "$0"` was already invoked once !! Aborting ..."
   exit 1
fi

# Create mount points for the logfile (tmpfs) of "var2rd.sh" and "varbak.sh"
# Creating it for "varbak.sh" now is useful when we want to mount / in read only later.
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
mount -t tmpfs -o $logtmpfsmountopts tmpfs "$lfdir"
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
echo "" >>"$lf"
echo "Method:                         $rdORtmpfs"  >>"$lf"
echo "`basename $0` log file mount point: $lfdir"  >>"$lf"
echo "varbak.sh log file mount point: $lfdir2"     >>"$lf"
echo "Log file:                       $lf"         >>"$lf"
echo "Log file mount opts: $logtmpfsmountopts"      >>"$lf"
echo "Ramdisk (rd):        $ramdisk"                >>"$lf"
echo "rd fs type:          $rdfstype"               >>"$lf"
echo "rd mount opts:       $rdmountopts"            >>"$lf"
echo "rd label:            $rdlabel"                >>"$lf"
echo "rd fsck:             $rdfsck"                 >>"$lf"
echo "root fsck:           $rootfsck"               >>"$lf"
echo "tmpfs mount opts:    $tmpfsmountopts"         >>"$lf"
echo "rsync 1 opts:        $rsyncopts1"             >>"$lf"
echo "rsync 2 opts:        $rsyncopts2"             >>"$lf"
echo "rsync 3 opts:        $rsyncopts3"             >>"$lf"
echo "" >>"$lf"

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
   ptype=`initctl list | awk -F ' ' '/^'"$p"' / { print $1 }'`
   
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

 # Check if process was really killed, if not, try again
 proc=$(ps -e | awk -F ' ' '/'" "$p"$"'/ { print $NF }')

 if [[ -n "$proc" ]]; then
    echo "INFO: Non-daemon "$p" is unwilling to die. Killing it brutal ..." >>"$lf"
    killall -e -9 "$p" >>"$lf" 2>&1

    # Check again if process is really dead
    unset proc
    proc=$(ps -e | awk -F ' ' '/'" "$p"$"'/ { print $NF }')

    if [[ -z "$proc" ]]; then
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
  if [[ `pgrep "$p"` ]]; then
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
unset p match

echo "" >>"$lf"

echo "INFO: Stopping daemons/non-daemons ..." >>"$lf"
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


# Unmount /var/lock and /var/run if they are mounted. Should be the case in Ubuntu10.04.
# NOTE: /var/run & /var/lock use each one a tmpfs by default. (at least in Ubuntu10.04)
if [[ -n "$varlock" ]]; then
   echo "UMOUNT: Unmounting $varlock ..." >>"$lf"
   umount "${var}/lock" >>"$lf" 2>&1
   echo "UMOUNT: Done." >>"$lf"
fi
if [[ -n "$varrun" ]]; then
   echo "UMOUNT: Unmounting $varrun ..." >>"$lf"
   umount "${var}/run" >>"$lf" 2>&1
   echo "UMOUNT: Done." >>"$lf"
fi


# Sync /varbak with /var 
echo "RSYNC: Start sync. $varbak (CF) with $var (CF):" >>"$lf"
rsync $rsyncopts2 "${var}/" "${varbak}/" >>"$lf" 2>&1
echo "RSYNC: Done." >>"$lf"

 
# If we use ramdisk, format it and turn of fsck if wanted.
if [[ "$rdORtmpfs" = "rd" ]]; then
   echo "MKFS: Formating ramdisk ..." >>"$lf"
   mkfs -t $rdfstype -m 0 -L "$rdlabel" "$ramdisk" >>"$lf" 2>&1 
   echo "MKFS: Done." >>"$lf"
   
   if [[ "$rdfsck" = "off" ]]; then
      # Turn off counter and time based fsck for /var (ramdisk)
      echo "TUNE2FS: Turning off counter and time based fsck for "$var" (ramdisk)..." >>"$lf"
      tune2fs -c 0 -i 0 "$ramdisk" >>"$lf" 2>&1
      echo "TUNE2FS: Done." >>"$lf"
   fi
fi


# Mount ramdisk or tmpfs on /var.
if [[ "$rdORtmpfs" = "rd" ]]; then
   echo "MOUNT: Mounting ramdisk on $var" >>"$lf"
   mount -t $rdfstype -o $rdmountopts "$ramdisk" "$var" >>"$lf" 2>&1
   echo "MOUNT: Done." >>"$lf"

elif [[ "$rdORtmpfs" = "tmpfs" ]]; then
     echo "MOUNT: Mounting tmpfs on $var" >>"$lf"
     mount -t tmpfs -o $tmpfsmountopts tmpfs "$var" >>"$lf" 2>&1
     echo "MOUNT: Done." >>"$lf"

     echo "SWAP: Setting swappiness to 0 ..." >>"$lf"
     echo 0 >/proc/sys/vm/swappiness
     echo "SWAP: Done." >>"$lf"
fi

# Sync /var (ramdisk/tmpfs) with /varbak (CF)
echo "RSYNC: Start syncing $var (ramdisk/tmpfs) with $varbak (CF)" >>"$lf"
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


# Turn off / fsck
if [[ "$rootfsck" = "off" ]]; then
   rootdev=`rdev | cut -d ' ' -f 1` 
   echo "TUNE2FS: Turning off counter and time based fsck for "$rootdev" ..." >>"$lf"
   tune2fs -c 0 -i 0 "$rootdev" >>"$lf" 2>&1
   echo "TUNE2FS: Done." >>"$lf"
fi


# Insert end flag into logfile
echo "" >>"$lf"
echo "["$t"]: END "$0"" >>"$lf"
echo "#####################################################" >>"$lf"
echo "" >>"$lf"

# Happy end
exit 0

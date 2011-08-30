#!/bin/bash

# Title        : error-led.sh
# Author       : sambaTux <sambatux@web.de>
# Start date   : 18.08.2011
# OS tested    : Ubuntu10.04
# BASH version : 4.1.5(1)-release
# Requires     : modprobe, grep, cut, cat, mknod, rm, sleep
# Version      : 0.2
# Task(s)      : create nodes for soekris net5501 error LED and de-/activate it

# NOTE         : See http://www.kernel.org/pub/linux/docs/device-list/devices.txt 
#                for info about minor and major device numbers.

# LICENSE      : Copyright (C) 2011 Robert Schoen

#                This program is free software: you can redistribute it and/or modify it under the terms 
#                of the GNU General Public License as published by the Free Software Foundation, either 
#                version 3 of the License, or (at your option) any later version.
#                This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
#                without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
#                See the GNU General Public License for more details. [http://www.gnu.org/licenses/]


# Define vars
dev="/dev/error_led"
# Define logfile. Use the same as the calling script.
lf="$2" 


# Prepare everything for the error led usage. "--prepare" is only used by "var2rd.sh".
# This ensures that "varbak.sh" can also use the error led, even if / is mounted in read only.
case "$1" in
   "--prepare")
        
        echo "TASK: Preparing everything for the error led usage ..." >>"$lf" 
       
        # Load required modules
        echo "MODPROBE: Loading modules ..." >>"$lf"
        modprobe cs5535_gpio >>"$lf" 2>&1
        modprobe pc8736x_gpio >>"$lf" 2>&1
        echo "MODPROBE: Done." >>"$lf"

        major=$(cat /proc/devices | grep "cs5535_gpio$" | cut -d ' ' -f 1)
        minor=6

        # Create node
        echo "MKNOD: Creating $dev ..." >>"$lf"
        if [[ -e "$dev" ]]; then
           rm -f "$dev"
           mknod "$dev" c $major $minor >>"$lf" 2>&1
        else
           mknod "$dev" c $major $minor >>"$lf" 2>&1
        fi
        echo "MKNOD: Done." >>"$lf"        

        # GPIO (General Purpose Input Output)
        gpiodev="/dev/gpio"

        major=$(cat /proc/devices | grep "pc8736x_gpio$" | cut -d ' ' -f 1)

        # Minor values for GPIO. These ones should work:
        # 4 5 10 11 16 17 18 19 20 21 22 23 and 254
        minor=254

        # Create gpio node
        echo "MKNOD: Creating $gpiodev ..." >>"$lf"
        if [[ -e "$gpiodev" ]]; then
           rm -f "$gpiodev"
           mknod "$gpiodev" c $major $minor >>"$lf" 2>&1
        else
           mknod "$gpiodev" c $major $minor >>"$lf" 2>&1
        fi   
        echo "MKNOD: Done." >>"$lf"
        
        echo "TASK: Done." >>"$lf"
   ;;


   "--fatal")    # A script failed/crashed
                 [[ -n "$2" ]] && echo "FATAL ERROR: Activating fast blinking error led ..." >>"$lf"
                 while true; do
                   echo 1 >"$dev"
                   sleep 0.3
                   echo 0 >"$dev"
                   sleep 0.3
                 done                           
   ;;

   "--warning")  # A script doesn't run optimal.
                 # I.e. when not enough free RAM available for "varbak.sh" to sync. data.
                 echo "WARN: Activating slow blinking error led. Not enough free RAM for data sync." >>"$lf"
                 while true; do
                   echo 1 >"$dev"
                   sleep 1
                   echo 0 >"$dev"
                   sleep 1
                 done
   ;; 
   
   "--warn-off") # Deactivate warning led. I.e when "varbak.sh" has enough free RAM again.
                 echo "INFO: Deactivating slow blinking error led ..." >>"$lf"
                 echo 0 >"$dev"
   ;;                 
esac

exit 0

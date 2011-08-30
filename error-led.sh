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

# Prepare everything for the error led usage. "--prepare" is only used by "var2rd.sh".
# This ensures that "varbak.sh" can also use the error led, even if / is mounted in read only.
case "$1" in
   "--prepare")
        
        # Define logfile. Use the same as "var2rd.sh".
        lf="$2"    
 
        echo "TASK: Preparing everything for the error led usage ..." >>"$lf" 
       
        # Create error led node:
        dev="/dev/error_led"

        # Load required modules
        echo "MODPROBE: Loading modules ..." >>"$lf"
        modprobe cs5535_gpio >>"$lf" 2>&1
        modprobe pc8736x_gpio >>"$lf" 2>&1
        echo "MODPROBE: Done." >>"$lf"

        major=$(cat /proc/devices | grep "cs5535_gpio$" | cut -d ' ' -f 1)
        minor=6

        # Create nod
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

        # Create gpio nod
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
                 echo 1 >"$dev"    
   ;;

   "--warning")  # A script doesn't run in optimal modus. 
                 # I.e. when not enough free RAM available for "varbak.sh" to sync. data.
                 while true; do
                   echo 1 >"$dev"
                   sleep 1
                   echo 0 >"$dev"
                   sleep 1
                 done
   ;; 
   
   "--warn-off") # Deactivate warning led. I.e when "varbak.sh" has enough free RAM again.
                 echo 0 >"$dev"
   ;;                 
esac

exit 0

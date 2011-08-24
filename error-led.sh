#!/bin/bash

#Title        : error-led.sh
#Author       : sambaTux <sambatux@web.de>
#Start date   : 18.08.2011
#Finish date  : 18.08.2011
#OS tested    : Ubuntu10.04
#OS supported : Ubuntu10.04 ...
#BASH version : 4.1.5(1)-release
#Requires     : modprobe, grep, cut, cat, mknod, rm, sleep
#Version      : 0.1
#Task(s)      : create node for soekris net5501 error LED and activate it

#create error_led node:
dev="/dev/error_led"

#load required modules
modprobe cs5535_gpio
modprobe pc8736x_gpio

major=$(cat /proc/devices | grep "cs5535_gpio$" | cut -d ' ' -f 1)
minor=6

#create nod
if [[ -e "$dev" ]]; then
   rm -f "$dev"
   mknod "$dev" c $major $minor
else
   mknod "$dev" c $major $minor
fi

#GPIO
gpiodev="/dev/gpio"

major=$(cat /proc/devices | grep "pc8736x_gpio$" | cut -d ' ' -f 1)

# Minor values for GPIO. Theses one should work:
# 4 5 10 11 16 17 18 19 20 21 22 23 and 254
minor=254

#create nod
if [[ -e "$gpiodev" ]]; then
   rm -f "$gpiodev"
   mknod "$gpiodev" c $major $minor
else
   mknod "$gpiodev" c $major $minor
fi

#activate error led 
while true; do
  echo 1 >"$dev"
  sleep 0.5
  echo 0 >"$dev"
  sleep 0.5
done



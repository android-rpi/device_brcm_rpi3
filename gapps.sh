#!/bin/bash

#
# OpenGApps installation script for Raspberry Pi 3
# Author: Igor Kalkov
# https://github.com/RTAndroid/android_device_brcm_rpi3/blob/aosp-n/gapps.sh
#

package="open_gapps-arm-6.0-pico-20160815.zip"
address="192.168.1.37"

# ------------------------------------------------
# Helping functions
# ------------------------------------------------

reboot_now()
{
  adb reboot bootloader > /dev/null &
  sleep 10
}

is_booted()
{
  [[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]
}

wait_for_adb()
{
  while true; do
    sleep 1
    adb kill-server > /dev/null
    adb connect $address > /dev/null
    if is_booted; then
      break
    fi
  done
}

# ------------------------------------------------
# Script entry point
# ------------------------------------------------

echo "GApps installation script for RPi"
echo "Used package: $package"
echo "Device address: $address"

if [ ! -d org ]; then
  echo " * Downloading GApps package..."
  wget https://github.com/opengapps/arm/releases/download/20160815/$package
  unzip $package -d org
fi

echo " * Extracting supplied packages..."
rm -rf tmp
mkdir -p tmp
find . -name "*.tar.xz" -exec tar -xf {} -C tmp/ \;

echo " * Removing not needed packages..."
echo "  - SetupWizard (Tablet)"
rm -rf tmp/setupwizardtablet*
echo "  - PackageInstaller (Google)"
rm -rf tmp/packageinstallergoogle*

echo " * Creating system partition..."
rm -rf sys
mkdir -p sys
for dir in tmp/*/
do
  pkg=${dir%*/}
  dpi=$(ls -1 $pkg | head -1)

  echo "  - including $pkg/$dpi"
  rsync -aq $pkg/$dpi/ sys/
done

echo " * Enabling root access..."
wait_for_adb
adb root

echo " * Remounting system partition..."
wait_for_adb
adb remount

echo " * Pushing system files..."
adb push sys /system

echo " * Enforcing a reboot, please be patient..."
wait_for_adb
reboot_now

echo " * Waiting for the device (errors are OK)..."
wait_for_adb

echo " * Applying correct permissions..."
adb shell "pm grant com.google.android.gms android.permission.ACCESS_COARSE_LOCATION"
adb shell "pm grant com.google.android.gms android.permission.ACCESS_FINE_LOCATION"
adb shell "pm grant com.google.android.setupwizard android.permission.READ_PHONE_STATE"

echo "All done. The device will be rebooted once again."
wait_for_adb
reboot_now
adb kill-server

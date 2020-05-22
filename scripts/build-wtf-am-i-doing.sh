#!/usr/bin/env bash

# File: scripts/build-wtf-am-i-doing.sh
# Date: 22 May 2020
# Author: Kyle Olsen <kyle.g.olsen@gmail.com>
#
# Description: I'm out of my damn mind. Going to try debootstrapping a custom Raspbian image from scratch
#   in order to minimize the final cluster image so TFTP doesn't have to send gigabytes of useless crap
#   every time a new cluster member boots/reboots.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Fail on any non-0 command exit
set -e

# Check that script is running with EUID 0 (root)
if (( EUID != 0 )); then
  echo "ERROR: must run as root"
  exit 1
fi

IMG_FILE="k3s-base-image.img"
# Create an empty 1GiB image
dd if=/dev/zero of="${IMG_FILE}" bs=1M count=1024

# Partition image (yes, using parted would look nicer but fdisk means I don't have to do math. Yet. It's coming.
fdisk "${IMG_FILE}" <<EOF
n
p
1
2048
+100M
t
c
n
p
2


w
EOF

# Setup loopback FS, create filesystems and mountpoints, mount
declare -a parts
IFS=$'\n'; for part in $(fdisk -l "${IMG_FILE}" | tail -2); do
  partsizes=$(echo "${part}"|awk '{print $2*512,$4*512}');
  parts[${#parts[@]}]="${partsizes}"
done

mkdir -p /mnt/raspbian/{boot,root}

mount -v -o offset="$(echo "${parts[0]}"|awk '{print $1}')",sizelimit="$(echo "${parts[0]}"|awk '{print $2}')" \
  -t vfat "${IMG_FILE}" /mnt/raspbian/boot
mount -v -o offset="$(echo "${parts[1]}"|awk '{print $1}')",sizelimit="$(echo "${parts[1]}"|awk '{print $2}')" \
  -t ext4 "${IMG_FILE}" /mnt/raspbian/root

# Put boot files into place
git clone --depth 1 git://github.com/raspberrypi/firmware.git /tmp/firmware
mv /tmp/firmware/boot/* /mnt/raspbian/boot/
touch /mnt/raspbian/boot/ssh

# Bootstrap the Raspbian root
debootstrap --no-check-gpg --foreign --arch=armhf buster /mnt/raspbian/root/ http://archive.raspbian.org/raspbian
cp /usr/bin/qemu-arm-static /mnt/raspbian/root/usr/bin/
mount -o remount -t proc /proc /mnt/raspbian/root/proc/
mount -o remount -t sysfs /sys /mnt/raspbian/root/sys/
mount -o remount,bind /dev /mnt/raspbian/root/dev/
chroot /mnt/raspbian/root /debootstrap/debootstrap --second-stage

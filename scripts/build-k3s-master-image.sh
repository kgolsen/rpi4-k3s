#!/usr/bin/env bash

# File: scripts/build-k3s-master-image.sh
# Date: 18 Oct 2019
# Author: Kyle Olsen <kyle.g.olsen@gmail.com>
#
# Description: this script builds off of the base-k3sup-image.img to ready a k3s master
#
# IMPORTANT: this script is intended to be run in a debian:buster Docker container with a local directory bind mounted
#   to /var/local.

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

if [[ -f /var/local/base-k3s-image.img ]]; then
  cp /var/local/base-k3s-image.img /tmp/k3s-base.img
  K3S_IMG="/tmp/k3s-base.img"
fi

if [[ -z "${K3S_IMG}" ]]; then
  echo "ERROR: unable to find k3s Raspbian image in /var/local"
  exit 1
fi

# Get image partition data, mount parts
echo "Gathering image partition data..."
declare -a parts
IFS=$'\n'; for part in $(fdisk -l "${K3S_IMG}" | tail -2); do
  partsizes=$(echo "${part}"|awk '{print $2*512,$4*512}');
  parts[${#parts[@]}]="${partsizes}"
done

mkdir -p /mnt/raspbian/boot
mkdir -p /mnt/raspbian/root

echo "Mounting partitions..."
mount -v -o offset="$(echo "${parts[0]}"|awk '{print $1}')",sizelimit="$(echo "${parts[0]}"|awk '{print $2}')" \
  -t vfat "${K3S_IMG}" /mnt/raspbian/boot &> /dev/null
mount -v -o offset="$(echo "${parts[1]}"|awk '{print $1}')",sizelimit="$(echo "${parts[1]}"|awk '{print $2}')" \
  -t ext4 "${K3S_IMG}" /mnt/raspbian/root &> /dev/null

# chroot to Raspbian and setup hostname
cat << EOF | chroot /mnt/raspbian/root &> /dev/null
echo "rpi-k3s-master" > /etc/hostname
sed -i -e 's/k3s-base/rpi-k3s-master/' /etc/hosts
EOF

# chroot to Raspbian, setup rc.local to prepare PXE boot server on first boot
echo "Creating initial setup tasks..."
cat << EOF | chroot /mnt/raspbian/root &> /dev/null
cat << EORC | tee /etc/rc.local &> /dev/null
#!/bin/bash
# pull bootp setup script
wget -q --compression=auto https://raw.githubusercontent.com/kgolsen/rpi4-k3s/master/scripts/bootp-server-setup.sh \
  -O /usr/local/bin/bootp-server-setup.sh
chmod +x /usr/local/bin/*.sh

/usr/local/bin/bootp-server-setup.sh
chmod -x /etc/rc.local
systemctl reboot
EORC
chmod +x /etc/rc.local
exit
EOF

# Unmount and copy new image to local host
echo "Unmounting and copying image to local host..."
umount /mnt/raspbian/boot
umount /mnt/raspbian/root
cp "${K3S_IMG}" /var/local/rpi-k3s-master.img

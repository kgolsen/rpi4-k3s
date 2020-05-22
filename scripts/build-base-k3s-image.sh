#!/usr/bin/env bash

# File: scripts/build-base-k3s-image.sh
# Date: 18 Oct 2019
# Author: Kyle Olsen <kyle.g.olsen@gmail.com>
#
# Description: this script builds a base image with k3sup utilizing a common RSA key for the pi user to simplify
#   later joining/creating a k3s cluster.
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

# Get necessary utilities
echo "Installing utilities..."
apt-get update &> /dev/null
apt install -y wget curl unzip &> /dev/null

for cmd in wget curl unzip; do
  if [[ -z $(command -v "${cmd}") ]]; then
    echo "ERROR: ${cmd} not found"
    exit 1
  fi
done

RASPBIAN_URL="https://downloads.raspberrypi.org/raspbian_lite_latest"

# Fetch file (if necessary), unpack Raspbian, get Raspbian image name
if [[ ! -f /var/local/raspbian.zip ]]; then
  echo "Fetching Raspbian..."
  wget -q --compression=auto "${RASPBIAN_URL}" -O /var/local/raspbian.zip
fi
echo "Unpacking Raspbian..."
unzip -d /tmp /var/local/raspbian.zip &> /dev/null && rm /var/local/raspbian.zip
RASPBIAN_IMG=$(find /tmp -name '*raspbian-*-lite.img' -type f)

if [[ -z "${RASPBIAN_IMG}" ]]; then
  echo "ERROR: unable to find Raspbian image in /tmp"
  exit 1
fi

# Get image partition data, mount parts
echo "Gathering image partition data..."
declare -a parts
IFS=$'\n'; for part in $(fdisk -l "${RASPBIAN_IMG}" | tail -2); do
  partsizes=$(echo "${part}"|awk '{print $2*512,$4*512}');
  parts[${#parts[@]}]="${partsizes}"
done

mkdir -p /mnt/raspbian/{boot,root}

echo "Mounting partitions..."
mount -v -o offset="$(echo "${parts[0]}"|awk '{print $1}')",sizelimit="$(echo "${parts[0]}"|awk '{print $2}')" \
  -t vfat "${RASPBIAN_IMG}" /mnt/raspbian/boot &> /dev/null
mount -v -o offset="$(echo "${parts[1]}"|awk '{print $1}')",sizelimit="$(echo "${parts[1]}"|awk '{print $2}')" \
  -t ext4 "${RASPBIAN_IMG}" /mnt/raspbian/root &> /dev/null

echo "Configuring rpi settings and enabling ssh..."
# Add container capabilities to the kernel boot command
CMDLINE=$(cat /mnt/raspbian/boot/cmdline.txt)
echo "${CMDLINE} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" | \
  tee /mnt/raspbian/boot/cmdline.txt &> /dev/null
# Reduce GPU memory to the minimum allowed, as we are running headless
echo "gpu_mem=16" | cat - /mnt/raspbian/boot/config.txt | tee /mnt/raspbian/boot/config.txt &> /dev/null
# Don't load snd_bcm2835, as we are running headless
sed -i -e 's/audio=on/audio=off/' /mnt/raspbian/boot/config.txt
# Enable SSH
touch /mnt/raspbian/boot/ssh
# chroot to Raspbian and setup SSH
cat << EOF | chroot /mnt/raspbian/root &> /dev/null
echo "k3s-base" > /etc/hostname
sed -i -e 's/raspberrypi/k3s-base/' /etc/hosts
mkdir -p /home/pi/.ssh
cd /home/pi/.ssh
ssh-keygen -f k3s-masterkey -t rsa -b 4096 -N '' -m PEM -q
mv k3s-masterkey k3s-masterkey.pem
cat k3s-masterkey.pub > authorized_keys
chmod 644 authorized_keys
chmod 400 k3s-masterkey.pem
chmod 700 /home/pi/.ssh
chown -R pi:pi /home/pi/.ssh
EOF

echo "Copying SSH masterkeys to local host..."
cp /mnt/raspbian/root/home/pi/.ssh/k3s-masterkey* /var/local/

# chroot to Raspbian, setup rc.local to install k3sup
echo "Creating initial setup tasks..."
cat << EOF | chroot /mnt/raspbian/root &> /dev/null
cat << EORC | tee /etc/rc.local &> /dev/null
#!/bin/bash
# update and upgrade everything
apt-get update
apt-get upgrade -y
apt-get full-upgrade -y

# pull k3sup installer and run
wget -q --compression=auto https://get.k3sup.dev -O /usr/local/bin/install-k3sup.sh
chmod +x /usr/local/bin/*.sh
/usr/local/bin/install-k3sup.sh && rm /usr/local/bin/install-k3sup.sh

# disable password auth for SSH
sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# disable swapfile
systemctl disable dphys-swapfile.service
systemctl stop dphys-swapfile.service
chmod -x /etc/rc.local
EORC
chmod +x /etc/rc.local
exit
EOF

# Unmount and copy new image to local host
echo "Unmounting and copying image to local host..."
umount /mnt/raspbian/boot
umount /mnt/raspbian/root
cp "${RASPBIAN_IMG}" /var/local/base-k3s-image.img

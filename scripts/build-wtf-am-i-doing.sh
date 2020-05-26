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

# Get partition offsets and sizes
declare -a parts
IFS=$'\n'; for part in $(fdisk -l "${IMG_FILE}" | tail -2); do
  partsizes=$(echo "${part}"|awk '{print $2*512,$4*512}');
  parts[${#parts[@]}]="${partsizes}"
done

mkdir -p /mnt/raspbian/{boot,root}

# Create filesystems on image partitions
LO=$(losetup -f --show -o "$(echo "${parts[0]}"|awk '{print $1}')" --size "$(echo "${parts[0]}"|awk '{print $2}')" "${IMG_FILE}")
mkfs.vfat "${LO}"
losetup -D
LO=$(losetup -f --show -o "$(echo "${parts[1]}"|awk '{print $1}')" --size "$(echo "${parts[1]}"|awk '{print $2}')" "${IMG_FILE}")
mkfs.ext4 "${LO}"
losetup -D

# Mount image partitions
BOOT="/mnt/raspbian/boot"
ROOT="/mnt/raspbian/root"
mount -v -o offset="$(echo "${parts[0]}"|awk '{print $1}')",sizelimit="$(echo "${parts[0]}"|awk '{print $2}')" \
  -t vfat "${IMG_FILE}" "${BOOT}"
mount -v -o offset="$(echo "${parts[1]}"|awk '{print $1}')",sizelimit="$(echo "${parts[1]}"|awk '{print $2}')" \
  -t ext4 "${IMG_FILE}" "${ROOT}"

# Put boot files into place
git clone --depth 1 git://github.com/raspberrypi/firmware.git /tmp/firmware
mv /tmp/firmware/boot/* "${BOOT}"
touch "${BOOT}/ssh"
# Add container capabilities to the kernel boot command
CMDLINE=$(cat "${BOOT}/cmdline.txt")
echo "${CMDLINE} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" | tee "${BOOT}/cmdline.txt"
# Reduce GPU memory to the minimum allowed, as we are running headless
echo "gpu_mem=16" | cat - "${BOOT}/config.txt" | tee "${BOOT}/config.txt"
# Don't load snd_bcm2835, as we are running headless
sed -i -e 's/audio=on/audio=off/' "${BOOT}/config.txt"

# Bootstrap the Raspbian root
debootstrap --no-check-gpg --foreign --arch=armhf buster "${ROOT}" http://archive.raspbian.org/raspbian
cp /usr/bin/qemu-arm-static "${ROOT}/usr/bin/"
mount -o remount -t proc /proc "${ROOT}/proc/"
chroot "${ROOT}" /debootstrap/debootstrap --second-stage

# chroot to Raspbian and setup SSH
cat << EOF | chroot "${ROOT}"
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
cp "${ROOT}/home/pi/.ssh/k3s-masterkey*" /var/local/

# chroot to Raspbian, setup rc.local to install k3sup
cat << EOF | chroot "${ROOT}"
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

# Unmount and copy image to volume
umount "${BOOT}"
umount "${ROOT}"
cp "${IMG_FILE}" /var/local/

#!/usr/bin/env bash

# File: scripts/build-k3s-cluster-image.sh
# Date: 22 May 2020
# Author: Kyle Olsen <kyle.g.olsen@gmail.com>
#
# Description: Debootstrap a custom minbase Raspbian image from in order to minimize the
#   image TFTP has to serve every time a new cluster member boots/reboots.

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
for i in 0 1; do
  LO=$(losetup -f --show -o "$(echo "${parts[$i]}"|awk '{print $1}')" --size "$(echo "${parts[$i]}"|awk '{print $2}')" "${IMG_FILE}")
  if (( i == 0 )); then
    mkfs.vfat "${LO}"
  else
    mkfs.ext4 "${LO}"
  fi
  losetup -D
done

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
CMDLINE="console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet"
echo "${CMDLINE} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" | tee "${BOOT}/cmdline.txt"

# Generate config.txt
cat << EOF | tee "${BOOT}/config.txt"
gpu_mem=16
dtparam=audio=off
ignore_lcd=1
disable_splash=1

[pi4]
# Might not be necessary
dtoverlay=vc4-fkms-v3d
max_framebuffers=2
EOF

# Bootstrap the Raspbian root
qemu-debootstrap --no-check-gpg --variant=minbase --arch=armhf buster "${ROOT}" http://archive.raspbian.org/raspbian
cp /usr/bin/qemu-arm-static "${ROOT}/usr/bin/"

# chroot to Raspbian and setup SSH
cat << EOF | chroot "${ROOT}" /usr/bin/qemu-arm-static /bin/bash
# Install OpenSSH and wget
apt-get install -y openssh-server openssh-client openssh-blacklist openssh-blacklist-extra wget

# Setup hostname and hosts file
echo "k3s-base" > /etc/hostname
cat << EEOF | tee /etc/hosts
127.0.0.1 localhost
127.0.0.1 k3s-base

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EEOF

# Setup k3s user and RSA keys
useradd -m -r -U k3s
mkdir -p /home/k3s/.ssh
cd /home/k3s/.ssh
ssh-keygen -f k3s-masterkey -t rsa -b 4096 -N '' -m PEM -q
mv k3s-masterkey k3s-masterkey.pem
cat k3s-masterkey.pub > authorized_keys
chmod 644 authorized_keys
chmod 400 k3s-masterkey.pem
chmod 700 /home/k3s/.ssh
chown -R k3s:k3s /home/k3s/.ssh

# setup rc.local to install k3sup
cat << EORC | tee /etc/rc.local &> /dev/null
#!/bin/bash
# update and upgrade everything (no effect if booted shortly after image creation)
apt-get update
apt upgrade -y

# pull k3sup installer and run
wget -q --compression=auto https://get.k3sup.dev -O /tmp/install-k3sup.sh
chmod +x /usr/local/bin/*.sh
/tmp/install-k3sup.sh && rm /tmp/install-k3sup.sh

# disable password auth for SSH
sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# disable swapfile
systemctl disable dphys-swapfile.service
systemctl stop dphys-swapfile.service

# Change master hostname
echo "rpi-k3s-origin" > /etc/hostname
sed -i -e 's/k3s-base/rpi-k3s-origin/' /etc/hosts

# Get and run bootp setup script
wget -q --compression=auto https://raw.githubusercontent.com/kgolsen/rpi4-k3s/master/scripts/bootp-server-setup.sh \
  -O /usr/local/bin/bootp-server-setup.sh
chmod +x /usr/local/bin/*.sh

/usr/local/bin/bootp-server-setup.sh

chmod -x /etc/rc.local
EORC
chmod +x /etc/rc.local
exit
EOF

# Copy RSA keys to volume
cp "${ROOT}/home/k3s/.ssh/k3s-masterkey.pem" /var/local/
cp "${ROOT}/home/k3s/.ssh/k3s-masterkey.pub" /var/local/

# Unmount and shrink image
umount "${BOOT}"
umount "${ROOT}"

MIN_IMG_FILE="${IMG_FILE:0:-4}-min.img"
wget https://raw.githubusercontent.com/kgolsen/PiShrink/master/pishrink.sh -O pishrink.sh
/bin/bash pishrink.sh -p "${IMG_FILE}" "${MIN_IMG_FILE}"

# Copy raw and shrunk images to volume
cp "${IMG_FILE}" /var/local/
cp "${MIN_IMG_FILE}" /var/local/

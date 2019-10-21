#!/usr/bin/env bash

# File: scripts/build-rpi-image.sh
# Date: 18 Oct 2019
# Author: Kyle Olsen <kyle.g.olsen@gmail.com>
#
# Description: this script fetches the latest Raspbian Lite, unpacks, and mounts the images partitions in /mnt.
#   It then updates the pi users password, adds container capabilities to the boot command, then downloads and installs
#   k3s and k3sup.
#
# IMPORTANT: this script is intended to be run in a debian:buster Docker container with a local directory bind mounted
#   to /var/local.

# Fail on any non-0 command exit
set -e

# Get necessary utilities
apt-get update && apt install -y wget unzip curl

if [[ -z $(command -v wget) ]]; then
  echo "ERROR: wget not found"
  exit 1
fi

if [[ -z $(command -v curl) ]]; then
  echo "ERROR: curl not found"
  exit 1
fi

if [[ -z $(command -v unzip) ]]; then
  echo "ERROR: unzip not found"
  exit 1
fi

if [[ -z "${1}" ]]; then
  echo "ERROR: must supply new password for pi user as first argument"
  exit 1
fi

RASPBIAN_URL="https://downloads.raspberrypi.org/raspbian_lite_latest"

# Fetch file, unpack Raspbian, get Raspbian image name
echo "Fetching and unpacking Raspbian..."
wget -q --compression=auto "${RASPBIAN_URL}" -O /tmp/raspbian.zip
unzip -d /tmp /tmp/raspbian.zip && rm /tmp/raspbian.zip
RASPBIAN_IMG=$(find /tmp -name '*raspbian-*-lite.img' -type f)

if [[ -z "${RASPBIAN_IMG}" ]]; then
  echo "ERROR: unable to find Raspbian image in /tmp"
  exit 1
fi

# Get image partition data, mount partitions
echo "Gathering image partition data..."
declare -a partitions
IFS=$'\n'; for part in $(fdisk -l "${RASPBIAN_IMG}" | tail -2); do
  partsizes=$(echo "${part}"|awk '{print $2*512,$4*512}');
  partitions[${#partitions[@]}]="${partsizes}"
done

mkdir -p /mnt/raspbian/boot
mkdir -p /mnt/raspbian/root

echo "Mounting partitions..."
mount -v -o offset="$(echo "${partitions[0]}"|awk '{print $1}')",sizelimit="$(echo "${partitions[0]}"|awk '{print $2}')" \
  -t vfat "${RASPBIAN_IMG}" /mnt/raspbian/boot
mount -v -o offset="$(echo "${partitions[1]}"|awk '{print $1}')",sizelimit="$(echo "${partitions[1]}"|awk '{print $2}')" \
  -t ext4 "${RASPBIAN_IMG}" /mnt/raspbian/root

# Chroot into root partition, change pi user password
echo "Changing pi user password..."
cat << EOF | chroot /mnt/raspbian/root
echo "pi:${1}" | chpasswd
exit
EOF

# Add container capabilities to the kernel boot command
# shellcheck disable=SC2046
echo "cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" | \
  tee -a /mnt/raspbian/boot/cmdline.txt &> /dev/null

# Reduce GPU memory to the minimum allowed, as we are running headless
echo "gpu_mem=16" | cat - /mnt/raspbian/boot/config.txt | tee /mnt/raspbian/boot/config.txt &> /dev/null

# Don't load snd_bcm2835, as we are running headless
sed -i -e 's/audio=on/audio=off/' /mnt/raspbian/boot/config.txt

# Enable SSH
touch /mnt/raspbian/boot/ssh

# chroot to Raspbian and fetch k3s and k3sup
echo "Fetching k3s and k3sup..."
cat << EOF | chroot /mnt/raspbian/root
export ARCH=armhf
curl -sfL https://get.k3s.io | sh -
wget https://github.com/alexellis/k3sup/releases/download/0.4.3/k3sup-armhf -O /usr/local/bin/k3sup
chmod +x /usr/local/bin/k3sup
exit
EOF

# Unmount and copy new image to local host
echo "Unmounting and copying image to local host..."
umount /mnt/raspbian/boot
umount /mnt/raspbian/root
cp "${RASPBIAN_IMG}" /var/local/

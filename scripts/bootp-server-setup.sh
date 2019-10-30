#!/bin/bash

# File: scripts/bootp-server-setup.sh
# Date: 21 Oct 2019
# Author: Kyle Olsen <kyle.g.olsen@gmail.com>
#
# Description: this script runs at the k3s master's first boot to install and configure a TFTP BOOTP server for cluster
#   slaves' PXE boot.

# Fail on any non-0 command exit
set -e

# Must be run as root
if (( EUID != 0 )); then
  echo "ERROR: must be run as root"
  exit 1
fi

# Install kernel NFS server, rsync
apt install -y nfs-kernel-server rsync

# Create directory structure and copy FS
mkdir -p /tftp/k3s/client
mkdir /tftp/boot
rsync -xa --exclude /tftp / /tftp/k3s/client

# Setup TFTP boot
chmod 777 /tftp/boot
cp -r /boot/* /tftp/boot

# Setup NFS exports for boot, root FS
echo "/tftp/k3s/client *(rw,sync,no_subtree_check,no_root_squash)" | tee -a /etc/exports
echo "/tftp/boot *(rw,sync,no_subtree_check,no_root_squash)" | tee -a /etc/exports

# Enable rpcbind and NFS
systemctl enable rpcbind
systemctl enable nfs-kernel-server

# Chroot to client and prep
# TODO: (in rc.local) ssh reconfig, hostname reconfig, k3s reconfig
cd /tftp/k3s/client
mount --bind /dev dev
mount --bind /sys sys
mount --bind /proc proc
cat << EOF | chroot . &> /dev/null
rm /etc/ssh/ssh_host_*
EOF

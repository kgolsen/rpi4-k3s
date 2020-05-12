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
apt install -y nfs-kernel-server rsync dnsmasq

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

# Turn off DHCP for eth0
echo << EOF | tee /etc/systemd/network/10-eth0.netdev
[Match]
Name=eth0
[Network]
DHCP=no
EOF

# Set static IP for eth0
echo << EOF | tee /etc/systemd/network/11-eth0.netdev
[Match]
Name=eth0

[Network]
Address=10.100.100.100/32
Gateway=10.100.100.1
EOF

# Stop dhcpd and disable
systemctl stop dhcpd
systemctl disable dhcpd

# Configure dnsmasq for PXE boot
cat << EOF | tee /etc/dnsmasq.conf
interface=eth0
no-hosts
dhcp-range=10.100.100.10,10.100.100.20,12h
log-dhcp
enable-tftp
tftp-root=/tftp/boot
pxe-service=0,"k3s Master Boot"
EOF

# Enable rpcbind and NFS
systemctl enable rpcbind
systemctl enable nfs-kernel-server
systemctl enable dnsmasq

# Setup TFTP boot command
cat << EOF | tee /tftp/boot/cmdline.txt
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.100.100.100:/tftp/k3s/client,vers=3 rw ip=dhcp rootwait elevator=deadline
EOF

# Chroot to client and prep
# TODO: (in rc.local) ssh reconfig, hostname reconfig, k3s reconfig
cd /tftp/k3s/client
mount --bind /dev dev
mount --bind /sys sys
mount --bind /proc proc
cat << EOF | chroot . &> /dev/null
# remove host SSH keys
rm /etc/ssh/ssh_host_*

# Configure fstab for PXE boot
cat << EOFS | tee /etc/fstab
proc       /proc        proc     defaults    0    0
10.100.100.100:/tftp/boot /boot nfs defaults,vers=3 0 0
EOFS

# Create rc.local to reconfigure SSH and hostname on first boot
cat << EORC | tee /etc/rc.local
#!/bin/bash

dpkg-reconfigure openssh-server
systemctl enable ssh

# Change hostname
SERNO=$(cat /proc/cpuinfo |grep Serial | awk '{ print $3 }')
HOSTN="rpi-k3s-node-${SERNO}"
echo "${HOSTN}" > /etc/hostname
sed -i -e "s/rpi-k3s-master/${HOSTN}/" /etc/hosts
hostname "${HOSTN}"

EORC
EOF

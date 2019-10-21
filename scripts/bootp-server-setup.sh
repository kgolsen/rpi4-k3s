#!/usr/bin/env bash

# File: scripts/bootp-server-setup.sh
# Date: 21 Oct 2019
# Author: Kyle Olsen <kyle.g.olsen@gmail.com>
#
# Description: this script runs at the k3s master's first boot to install and configure a TFTP BOOTP server for cluster
#   slaves' PXE boot.

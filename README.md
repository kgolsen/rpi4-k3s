# rpi4-k3s
Automation for setting up a k3s cluster on Raspberry Pi 4 SBCs.

Builds a custom Raspbian Lite image pre-configured for k3s.

Does a few things.
1. Use Docker to build a custom Raspbian Lite image preconfigured for k3s.
2. Exports PEM and public key to access cluster machines during build.
3. Sets up cloud-init installation for first boot.
4. Sets up installation and configuration of BOOTP server for first boot.

Eventually, PXE boot images will be served to new machines joining the cluster that
include cloud-init config for automatic host naming, cluster joining, etc. Eventually.
I'm not made of free time and nobody's paying me for this.

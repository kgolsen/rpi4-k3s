# rpi4-k3s
Automation for setting up a k3s cluster on Raspberry Pi 4 SBCs.

Builds a custom Raspbian Lite image pre-configured for k3s.

Does a few things.
1. ~~Use Docker to build a custom Raspbian Lite image~~ preconfigured for k3s. (Now builds a minbase debootstrapped Raspbian)
2. Exports PEM and public key to access cluster machines during build. (this seems important to keep)
3. ~~Sets up cloud-init installation for first boot.~~ cloud-init was just complicating things
4. Sets up installation and configuration of BOOTP server for first boot. (also kinda important to hang onto)

~~Eventually, PXE boot images will be served to new machines joining the cluster that
include cloud-init config for automatic host naming, cluster joining, etc.~~ Eventually.
I'm not made of free time and nobody's paying me for this.

2020-05-12: Now that I'm working on the PXE boot, it's important to note that
the cluster IP space is set (and small). I'm building this cluster behind a Mikrotik
CRS112-8P-4S-IN, so it's important the cluster is sitting behind a
programmable router or network issues will ensue.

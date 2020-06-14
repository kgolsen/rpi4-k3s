# rpi4-k3s
Automation for setting up a k3s cluster on Raspberry Pi 4 SBCs.

Builds a custom Raspbian image pre-configured for k3s.

Does a few things.
1. Provides a Dockerfile to create a minbase Raspbian image with k3s and k3sup preinstalled.
2. Exports PEM and public key to access cluster machines.
3. Sets up rc.local so that on first boot, the cluster master installs and configures a PXE boot environment for other machines.

---

### Usage

##### To Get a Cluster Running

###### Option 1
1. `git clone https://github.com/kgolsen/rpi4-k3s.git`
2. `cd rpi4-k3s; docker build . -t rpi4-k3s; docker run --rm --privileged -v <some_dir>:/var/local rpi4-k3s`

###### Option 2
1. `docker run --rm --privileged -v <some_dir>:/var/local kgolsen/rpi4-k3s:latest`

###### Note:
On Linux hosts, you may have to add `--cap-add=CAP_MKNOD` to allow creation of loopback devices in the container.

###### Continue...

3. You now have an image, `k3s-base-image.img`, burnable to MicroSD with something like Etcher.
   - You also have the RSA keypair `k3s-masterkey.{pem,pub}`, which will allow you to SSH into any cluster member as the user `k3s`.
4. Boot up the rpi4 you intend to be the cluster master. First boot will take several minutes as the PXE boot
environment is built. Afterwards, rc.local will have its execute bit disabled and the rpi4 will reboot. You are now
ready to add more nodes to the cluster.
5. More coming soon...

---

### Notes

2020-05-12: Now that I'm working on the PXE boot, it's important to note that
the cluster IP space is set (and small). I'm building this cluster behind a Mikrotik
CRS112-8P-4S-IN, so it's important the cluster is sitting behind a
programmable router or network issues will ensue.

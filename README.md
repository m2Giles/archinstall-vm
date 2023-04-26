# archinstall-vm
Quick install script for installing arch

To use:

Boot arch-install media. As root run the following:

curl -O https://raw.githubusercontent.com/m2Giles/archinstall-vm/main/archinstall.sh

chmod +x ./archinstall.sh

./archinstall.sh

This will install a basic arch installation on ext4. Setups a user and installs xfce4 with lightdm. Total install size should be less than 3.5 GB.

Bootloader is systemd-boot. Uses UKIs to boot.

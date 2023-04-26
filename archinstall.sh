#!/bin/bash

set -e

ask () {
    read -p "> $1 " -r
    echo
}

passask () {
    while true; do
      echo
      echo "> $1"
      read -r -s PASS1
      echo
      echo "> Verify $1"
      read -r -s PASS2
      echo
      [ "$PASS1" = "$PASS2" ] && break || echo "Passwords do not Match. Please try again."
    done
    echo -n "$PASS2" > "$2"
    chmod 000 "$2"
    print "$1 can be reviewed at $2 prior to reboot"
    unset PASS1
    unset PASS2
}

umountandexport () {
    print "Umount all partitions"
    umount -R /mnt
}

print () {
    echo -e "\n\033[1m> $1\033[0m\n"
}

# Partition Drive
print "Choose Drive to install on and partition"
select ENTRY in $(ls /dev/disk/by-id);
do
  DISK="/dev/disk/by-id/$ENTRY"
  echo "$DISK" > /tmp/disk
  echo "Installing on $ENTRY and partitioning"
  break
done

print "Partitioning Drive"
# EFI Partition
sgdisk -Zo "$DISK"
sgdisk -n1:1M:+300M -t1:EF00 -c1:EFI "$DISK"
EFI="$DISK-part1"

# Root Parition
sgdisk -n3:0:-100m -t3:8304 -c3:ROOT "$DISK"
ROOT="$DISK-part3"

# notify Kernel
partprobe "$DISK"

# Format EFI Partition
sleep 1
print "Formatting EFI Partition"
mkfs.vfat -F32 "$EFI"

sleep 1
print "Formatting ROOT Partition"
mkfs.ext4 "$ROOT"

# Set Root Account Password
print "Set Root Account Password for new Installtion"
ROOTKEY=/tmp/root.key
passask "Root Password" "/tmp/root.key"
awk '{ print "root:" $0 }' "$ROOTKEY" > /tmp/root-chpasswd.key

# Set User Account Password
print "Set User Account Name and Password for new Installtion"
USERKEY=/tmp/user.key
ask "Username?"
USERNAME=$REPLY
passask "$USERNAME's Password" "/tmp/user.key"
echo "$USERNAME:$(cat $USERKEY)" > /tmp/user-chpasswd.key

ask "Please enter hostname for Installation:"
HOSTNAMEINSTALL="$REPLY"

print "Mount Partitions"
mount "$ROOT" /mnt
mkdir -p /mnt/efi
mount "$EFI" /mnt/efi
mkdir -p /mnt/efi/EFI/Linux

# Sort Mirrors
print "Sorting Fastest Mirrors in US"
echo "--country US" >> /etc/xdg/reflector/reflector.conf
systemctl start reflector

print "Configure Pacman for Color and Parallel Downloads"
sed -i 's/#\(Color\)/\1/' /etc/pacman.conf
sed -i "/Color/a\\ILoveCandy" /etc/pacman.conf
sed -i 's/#\(Parallel\)/\1/' /etc/pacman.conf

# Install
print "Pacstrap"
pacstrap /mnt linux \
      base              \
      linux-firmware    \
      intel-ucode       \
      nano              \
      git               \
      reflector         \
      networkmanager    \
      openssh           \
      bash-completion   \
      xfce4             \
      xfce4-goodies     \
      lightdm           \
      lightdm-gtk-greeter \
      chromium \
      sudo \
      which \
      systemd-resolvconf

print "Configure Pacman for Color and Parallel Downloads"
sed -i 's/#\(Color\)/\1/' /mnt/etc/pacman.conf
sed -i "/Color/a\\ILoveCandy" /mnt/etc/pacman.conf
sed -i 's/#\(Parallel\)/\1/' /mnt/etc/pacman.conf

# Copy Reflector Over
print "Copy Reflector Configuration"
cp /etc/xdg/reflector/reflector.conf /mnt/etc/xdg/reflector/reflector.conf

# FSTAB
print "Generate /etc/fstab"
genfstab -U /mnt  >> /mnt/etc/fstab

# Set Hostname and configure /etc/hosts
echo "$HOSTNAMEINSTALL" > /mnt/etc/hostname
cat > /mnt/etc/hosts <<EOF
#<ip-address> <hostname.domaing.org>  <hostname>
127.0.0.1 localhost $HOSTNAMEINSTALL
::1       localhost $HOSTNAMEINSTALL
EOF

# Set and Prepare Locales
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
sed -i 's/#\(en_US.UTF-8\)/\1/' /mnt/etc/locale.gen

# mkinitcpio
print "mkinitcpio UKI configuration"
CMDLINE="rw root=PARTLABEL=ROOT"
echo "$CMDLINE" > /mnt/etc/kernel/cmdline

cat > /mnt/etc/mkinitcpio.d/linux.preset <<EOF
# mkinitcpio preset file for the linux package

ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_microcode="/boot/intel-ucode.img"

PRESETS=('default' 'fallback')

#default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux.img"
default_uki="/efi/EFI/Linux/archlinux-linux.efi"

#fallback_config="/etc/mkinitcpio.conf"
fallback_image="/boot/initramfs-linux-fallback.img"
fallback_uki="/efi/EFI/Linux/archlinux-linux-fallback.efi"
fallback_options="-S autodetect"
EOF

# Systemd Resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

# Chroot!
print "Chroot into System"
arch-chroot /mnt /bin/bash -xe << EOF
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime
hwclock --systohc
locale-gen
bootctl install
systemctl enable    \
  NetworkManager    \
  systemd-resolved  \
  systemd-timesyncd \
  reflector.timer   \
  lightdm           \
  sshd              \
  systemd-boot-update.service
EOF

print "SSH Configuration"
mkdir /mnt/etc/ssh/sshd.d/
echo "Include /etc/ssh/sshd.d/override.conf" >> /mnt/etc/ssh/sshd
cat > /mnt/etc/ssh/sshd.d/override.conf << EOF
PermitRootLogin prohibit-password
PubkeyAuthentication yes
AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys
PasswordAuthentication yes
EOF
chmod 0644 /mnt/etc/ssh/sshd.d/override.conf

print "Restore mkinitcpio pacman hooks"

arch-chroot /mnt /bin/mkinitcpio -P
print "Setting archlinux-linux.efi as Default Boot Option."
cat > /mnt/efi/loader/loader.conf <<"EOF"
default archlinux-linux.efi
#timeout 3
#console-mode max
EOF

print "Making Pacman Hooks"
mkdir -p /mnt/etc/pacman.d/hooks
cat > /mnt/etc/pacman.d/hooks/95-systemd-boot.hook << "EOF"
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
EOF

# Set root passwd
print "Setting Root Account Password"
chpasswd --root /mnt/ < /tmp/root-chpasswd.key

print "Create User and Set Password and make sudoer"
useradd --root /mnt/ -mG wheel $USERNAME
chpasswd --root /mnt/ < /tmp/user-chpasswd.key
echo "$USERNAME ALL=(ALL) PASSWD: ALL" > /mnt/etc/sudoers.d/$USERNAME

umountandexport

echo -e "\e[32mAll OK"

count=5
print "System will reboot automatically in $count Seconds. Cancel with CTRL+C. Pull out the install media"
(( ++count ))
while (( --count > 0 )); do
    echo "Reboot in $count Seconds"
    sleep 1
done
echo "Rebooting System"
sleep 1
reboot

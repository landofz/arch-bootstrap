#!/bin/bash
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### Get some info from user ###
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

drive_password=$(dialog --stdout --passwordbox "Enter disk encryption password" 0 0) || exit 1
clear
: ${drive_password:?"disk encryption password cannot be empty"}
drive_password2=$(dialog --stdout --passwordbox "Enter disk encryption password again" 0 0) || exit 1
clear
[[ "$drive_password" == "$drive_password2" ]] || ( echo "Passwords did not match"; exit 1; )

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installtion disk" 0 0 0 ${devicelist}) || exit 1
clear

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

### Set up networking ###
echo "Checking networking"
if ! ping -c 2 google.com; then
    use_wifi=$(dialog --stdout --clear --yesno "Use WiFi?" 0 0) || exit 1
    if [ "$use_wifi" ]; then
        wifi-menu
    fi
    if ! ping -c 2 google.com; then
        echo "Could not connect to net"
        exit 1
    fi
fi

### Update system clock ###
echo "Updating system clock"
timedatectl set-ntp true

### Set up the disk and partitions ###
echo "Preparing disk"
parted --script "${device}" -- \
  mklabel msdos \
  mkpart primary ext2 1Mib 257MiB \
  set 1 boot on \
  mkpart primary 257MiB 100%

part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_root="$(ls ${device}* | grep -E "^${device}p?2$")"

mkfs.ext2 "${part_boot}"

### Wipe disk ###
if dialog --stdout --clear --yesno "Wipe disk?" 0 0; then
    echo "Wiping disk"
    cryptsetup open --type plain "${part_root}" container --key-file /dev/random
    dd if=/dev/zero of=/dev/mapper/container status=progress
    cryptsetup close container
fi
clear

### Set up disk encryption ###
echo "Setting disk encryption"
echo "${drive_password}" | cryptsetup luksFormat --type luks2 "${part_root}"
echo "${drive_password}" | cryptsetup open "${part_root}" cryptolvm
pvcreate /dev/mapper/cryptolvm
vgcreate MyVol /dev/mapper/cryptolvm
lvcreate -l 100%FREE MyVol -n root
mapper_root=/dev/mapper/MyVol-root
mkfs.ext4 "${mapper_root}"
part_root_uuid="$(blkid --output value ${part_root} | head -n1)"

mount "${mapper_root}" /mnt
mkdir /mnt/boot
mount "${part_boot}" /mnt/boot

### Install and configure the basic system ###
echo "Generating mirror list"
curl "https://www.archlinux.org/mirrorlist/?country=AT&country=HR&country=DE&protocol=https&ip_version=4" > /etc/pacman.d/mirrorlist
sed -i -e 's/#Server = /Server = /' /etc/pacman.d/mirrorlist

echo "Installing base system"
pacstrap /mnt base base-devel
genfstab -U /mnt >> /mnt/etc/fstab
echo "Created fstab:"
echo "*** begin fstab ***"
cat /mnt/etc/fstab
echo "*** end fstab ***"

echo "Configuring base system"
echo "${hostname}" > /mnt/etc/hostname
echo "127.0.1.1 ${hostname}.localdomain  ${hostname}" >> /mnt/etc/hosts
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Zagreb /etc/localtime
arch-chroot /mnt hwclock --systohc
sed -i -e 's/^#en_US.UTF-8/en_US.UTF-8/' /mnt/etc/locale.gen
sed -i -e 's/^#hr_HR.UTF-8/hr_HR.UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=hr_HR.UTF-8" > /etc/locale.conf

### Set up bootloader ###
echo "Configuring initramfs"
sed -i -e 's/^HOOKS=\(.*\) block /HOOKS=\1 keyboard keymap block encrypt lvm2 /' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux
echo "Setting up bootloader"
arch-chroot /mnt pacman --noconfirm -S --needed grub
arch-chroot /mnt grub-install --target=i386-pc "${device}"
arch-chroot /mnt pacman --noconfirm -S --needed intel-ucode
sed -i -e "s#^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"#GRUB_CMDLINE_LINUX_DEFAULT=\"\1 cryptdevice=UUID=${part_root_uuid}:cryptlvm root=/dev/mapper/MyVol-root\"#" /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

### Set up users ###
echo "Setting up users"
arch-chroot /mnt useradd -mU "${user}"
echo "${user}:${password}" | chpasswd --root /mnt
echo "${user} ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/10_${user}
passwd --root /mnt -l root

echo "Setting up home encryption"
modprobe ecryptfs
arch-chroot /mnt pacman --noconfirm -S --needed rsync lsof ecryptfs-utils
echo "${password}" | arch-chroot /mnt ecryptfs-migrate-home -u ${user}
arch-chroot /mnt su -c exit -l ${user}
sed -i -e '/^auth      required  pam_unix.so/aauth      required  pam_ecryptfs.so unwrap' /mnt/etc/pam.d/system-auth
sed -i -e '/^password  required  pam_unix.so/ipassword  optional  pam_ecryptfs.so' /mnt/etc/pam.d/system-auth
sed -i -e '/^session   required  pam_unix.so/asession   optional  pam_ecryptfs.so unwrap' /mnt/etc/pam.d/system-auth

### Install packages ###
echo "Installing WiFi packages"
arch-chroot /mnt pacman --noconfirm -S --needed iw wpa_supplicant dialog

### Reboot ###
echo "Unmounting drives"
cp stdout.log /mnt/root/bootstrap_stdout.log
cp stderr.log /mnt/root/bootstrap_stderr.log
umount -R /mnt
reboot

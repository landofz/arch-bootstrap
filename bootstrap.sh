#!/bin/bash
# This script will bootstrap a new Arch installation on a machine. It assumes
# the machine has an Intel CPU. The result is a bare bones system with
# networking and a sudo capable initial user.

set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### Get some info from user ###
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter main user username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter main user password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter main user password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

setup_disk=0
if dialog --stdout --clear --yesno "Setup disk?" 0 0; then
    setup_disk=1
fi
clear

if [[ "$setup_disk" == "1" ]]; then
    drive_password=$(dialog --stdout --passwordbox "Enter disk encryption password" 0 0) || exit 1
    clear
    : ${drive_password:?"disk encryption password cannot be empty"}
    drive_password2=$(dialog --stdout --passwordbox "Enter disk encryption password again" 0 0) || exit 1
    clear
    [[ "$drive_password" == "$drive_password2" ]] || ( echo "Passwords did not match"; exit 1; )

    devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
    device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
    device_size=$(fdisk -l | grep "Disk" | grep "${device}" | cut -d" " -f5)
    clear

    wipe_disk=0
    if dialog --stdout --clear --yesno "Wipe disk?" 0 0; then
        wipe_disk=1
    fi
    clear
else
    partlist=$(lsblk -plnx size -o name,size | grep -E "sd.[0-9]" | tac)
    part_root=$(dialog --stdout --menu "Select partition with encrypted root" 0 0 0 ${partlist}) || exit 1
    part_root_uuid="$(blkid --output value ${part_root} | head -n1)"
    clear
fi

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

### Set up networking ###
echo "Checking networking"
if ! ping -c 2 google.com; then
    use_wifi=$(dialog --stdout --clear --yesno "No network connectivity. Use WiFi?" 0 0) || exit 1
    clear
    if [ "$use_wifi" ]; then
        wifi-menu -o
    fi
    if ! ping -c 2 google.com; then
        echo "Could not connect to net"
        exit 1
    fi
fi

### Update system clock ###
echo "Updating system clock"
timedatectl set-ntp true

if [[ "$setup_disk" == "1" ]]; then
    ### Set up disk and partitions ###
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
    if [[ "$wipe_disk" == "1" ]]; then
        echo "Wiping disk"
        cryptsetup open --type plain "${part_root}" container --key-file /dev/random
        dd if=/dev/zero of=/dev/mapper/container status=progress
        cryptsetup close container
    fi

    ### Set up disk encryption ###
    echo "Setting disk encryption"
    echo "${drive_password}" | cryptsetup luksFormat --type luks2 "${part_root}"
    echo "${drive_password}" | cryptsetup open "${part_root}" cryptolvm
    pvcreate /dev/mapper/cryptolvm
    vgcreate MyVol /dev/mapper/cryptolvm
    forty_gb=40000000000
    if [[ "${device_size}" -le "${forty_gb}" ]]; then
        lvcreate -l 100%FREE MyVol -n root
    else
        lvcreate -L 30G MyVol -n root
        lvcreate -l 100%FREE MyVol -n home
    fi
    mapper_root=/dev/mapper/MyVol-root
    mkfs.ext4 "${mapper_root}"
    part_root_uuid="$(blkid --output value ${part_root} | head -n1)"
    if [[ "${device_size}" -gt "${forty_gb}" ]]; then
        mapper_home=/dev/mapper/MyVol-home
        mkfs.ext4 "${mapper_home}"
    fi

    echo "Mounting partitions"
    mount "${mapper_root}" /mnt
    mkdir /mnt/boot
    mount "${part_boot}" /mnt/boot
    mkdir /mnt/home
    if [[ "${device_size}" -gt "${forty_gb}" ]]; then
        mount "${mapper_home}" /mnt/home
    fi
fi

if [[ ! -d /mnt/boot ]]; then
        echo "Boot folder not found"
        exit 1
fi
if [[ ! -d /mnt/home ]]; then
        echo "Home folder not found"
        exit 1
fi

### Install and configure the basic system ###
echo "Generating mirror list"
curl "https://www.archlinux.org/mirrorlist/?country=AT&country=HR&country=DE&protocol=https&ip_version=4" > /etc/pacman.d/mirrorlist
sed -i -e 's/#Server = /Server = /' /etc/pacman.d/mirrorlist

echo "Installing base system"
pacstrap /mnt base base-devel
genfstab -U /mnt >> /mnt/etc/fstab

echo "Configuring base system"
### Networking ###
echo "${hostname}" > /mnt/etc/hostname
echo "127.0.1.1 ${hostname}.localdomain  ${hostname}" >> /mnt/etc/hosts
### Time ###
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Zagreb /etc/localtime
arch-chroot /mnt hwclock --systohc
### Locales ###
sed -i -e 's/^#en_US.UTF-8/en_US.UTF-8/' /mnt/etc/locale.gen
sed -i -e 's/^#hr_HR.UTF-8/hr_HR.UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
echo "LC_ADDRESS=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_COLLATE=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_IDENTIFICATION=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_MEASUREMENT=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_MONETARY=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_NAME=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_NUMERIC=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_PAPER=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_TELEPHONE=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "LC_TIME=hr_HR.UTF-8" >> /mnt/etc/locale.conf
echo "a4" >> /mnt/etc/papersize
### TRIM support ###
sed -i -e 's/issue_discards = 0/issue_discards = 1/' /mnt/etc/lvm/lvm.conf

### Set up bootloader ###
echo "Configuring initramfs"
sed -i -e 's/^HOOKS=\(.*\) block /HOOKS=\1 keyboard keymap block encrypt lvm2 /' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux
echo "Setting up bootloader"
arch-chroot /mnt pacman --noconfirm -S --needed grub
if [[ "$setup_disk" == "0" ]]; then
    device=$(df | grep "/boot$" | cut -d" " -f1 | head -n1)
    device=${device%?}
fi
arch-chroot /mnt grub-install --target=i386-pc "${device}"
arch-chroot /mnt pacman --noconfirm -S --needed intel-ucode
sed -i -e "s#^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"#GRUB_CMDLINE_LINUX_DEFAULT=\"\1 cryptdevice=UUID=${part_root_uuid}:cryptlvm:allow-discards root=/dev/mapper/MyVol-root\"#" /mnt/etc/default/grub
# These mounts are needed as a workaround for grub-mkconfig bug
mkdir /mnt/hostrun
mount --bind /run /mnt/hostrun
arch-chroot /mnt /bin/bash -c "mkdir /run/lvm && mount --bind /hostrun/lvm /run/lvm && grub-mkconfig -o /boot/grub/grub.cfg && umount /run/lvm && rmdir /run/lvm"
umount /mnt/hostrun
rmdir /mnt/hostrun

### Set up users ###
echo "Setting up users"
arch-chroot /mnt useradd -mU "${user}"
#echo "${user}:${password}" | chpasswd --root /mnt
echo "${user}:${password}" | arch-chroot /mnt chpasswd
echo "${user} ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/10_${user}
#passwd --root /mnt -l root
arch-chroot /mnt passwd -l root

arch-chroot /mnt pacman --noconfirm -S --needed rsync lsof ecryptfs-utils
if [[ "$setup_disk" == "1" ]]; then
    echo "Setting up home encryption"
    modprobe ecryptfs
    echo "${password}" | arch-chroot /mnt ecryptfs-migrate-home -u ${user}
    arch-chroot /mnt su -c exit -l ${user}
    find /mnt/home -name "${user}.*" | xargs rm -rf
fi
sed -i -e '/^auth      required  pam_unix.so/aauth      required  pam_ecryptfs.so unwrap' /mnt/etc/pam.d/system-auth
sed -i -e '/^password  required  pam_unix.so/ipassword  optional  pam_ecryptfs.so' /mnt/etc/pam.d/system-auth
sed -i -e '/^session   required  pam_unix.so/asession   optional  pam_ecryptfs.so unwrap' /mnt/etc/pam.d/system-auth

### Install networking packages ###
echo "Installing wired networking packages"
arch-chroot /mnt pacman --noconfirm -S --needed ifplugd
echo "Installing WiFi packages"
arch-chroot /mnt pacman --noconfirm -S --needed iw wpa_supplicant dialog wpa_actiond
echo "Creating netctl profiles"
for dev in $(ip -brief link | cut -d" " -f1 | grep "^enp"); do
    echo "Detected network device: $dev"
    profile="/mnt/etc/netctl/${dev}_dhcp"
    if [[ -e "$profile" ]]; then
        echo "Device $dev already configured"
        continue
    fi
    cp /mnt/etc/netctl/examples/ethernet-dhcp "$profile"
    sed -i -e "s/Interface=eth0/Interface=$dev/" "$profile"
    chmod 600 "$profile"
done
find /etc/netctl -type f -name "wl*" | xargs --no-run-if-empty -I '{}' cp {} /mnt{}

### Reboot ###
echo "Saving log files"
cp stdout.log /mnt/root/bootstrap_stdout.log
cp stderr.log /mnt/root/bootstrap_stderr.log
echo "Unmounting drives"
umount -R /mnt
reboot

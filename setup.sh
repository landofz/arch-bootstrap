#!/bin/bash
# TODO up network interfaces
# TODO configure and start needed services:
#    acpid, thermald, smartd, tlp
# TODO finish power management
# TODO udisks2, upower, uuidd
# TODO backlight - acpilight
# TODO autofs
# TODO xsecurelock, xss-lock
# TODO dunst
# TODO setup delayed hibernation
# TODO install haveged for entropy generation
# TODO polkit so user can reboot or poweroff
# TODO hardware video acceleration (va-api)
# TODO profile-sync-daemon
# TODO pdnsd or other dns caching server
# TODO weekly SSD trim (and LUKS allow_discards option or in crypttab and LVM issue_discards config)
# TODO cronie
# TODO powerline fonts
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### Set up logging ###
exec 1> >(tee "setup_stdout.log")
exec 2> >(tee "setup_stderr.log")

echo "Saving bootstrap log files"
if sudo ls /root/bootstrap_stdout.log 2>/dev/null; then
    sudo mv /root/bootstrap_stdout.log ~/bootstrap_stdout.log
    sudo chown $USER:$USER ~/bootstrap_stdout.log
fi
if sudo ls /root/bootstrap_stderr.log 2>/dev/null; then
    sudo mv /root/bootstrap_stderr.log ~/bootstrap_stderr.log
    sudo chown $USER:$USER ~/bootstrap_stderr.log
fi

echo "Configuring network profile autostart"
for dev in $(ip -brief link | cut -d" " -f1 | grep "^enp"); do
    echo "Detected network device: $dev"
    sudo systemctl enable "netctl-ifplugd@$dev.service"
    sudo systemctl start "netctl-ifplugd@$dev.service"
done

echo "Checking networking"
if ! ping -c 2 google.com; then
    echo "Could not connect to net"
    exit 1
fi

echo "Setting AUR helper"
mkdir ~/src
git clone https://aur.archlinux.org/yay.git ~/src/yay
pushd ~/src/yay
makepkg -si
popd

echo "Setting NTP"
sudo pacman --noconfirm -S --needed chrony
sudo sed -i -e '/! pool 3.arch/a pool pool.ntp.org offline' /etc/chrony.conf
sudo sed -i -e 's/! maxupdateskew 100/maxupdateskew 100/' /etc/chrony.conf
sudo systemctl disable systemd-timesyncd.service
sudo systemctl enable chronyd.service
sudo systemctl start chronyd.service
sudo chronyc online
sudo chronyc makestep
yay -S netctl-dispatcher-chrony

### Install packages ###
echo "Installing core packages"
sudo pacman --noconfirm -S --needed \
    git \
    bash-completion \
    stow \
    python \
    tmux \
    vim \
    neovim
# TODO install vundle.vim, and tpm

echo "Installing graphics packages"
# TODO test if we need to install xf86-video-intel as well
sudo pacman --noconfirm -S --needed \
    xf86-video-vesa \
    mesa \
    vulkan-intel
sudo pacman --noconfirm -S --needed \
    xorg-server \
    xorg-xinit \
    xorg-xrdb \
    xorg-xset \
    xorg-xinput \
    xorg-xprop \
    xorg-xev \
    xorg-xdpyinfo \
    xorg-xlsclients \
    xorg-xrandr \
    xorg-xbacklight \
    xorg-setxkbmap \
    xorg-xmodmap \
    xorg-fonts-100dpi \
    xdotool
sudo pacman --noconfirm -S --needed \
    i3-wm \
    i3blocks \
    i3lock \
    i3status \
    rxvt-unicode \
    rofi

echo "Installing audio packages"
sudo pacman --noconfirm -S --needed \
    alsa-utils \
    pulseaudio

echo "Installing power management packages"
# We don't install anything for fan speed control at the moment because on
# ThinkPads it is handled by EC automatically.
sudo pacman --noconfirm -S --needed \
    acpid \
    lm_sensors \
    cpupower \
    i7z \
    hddtemp \
    thermald \
    powertop \
    smartmontools \
    hdparm \
    ethtool \
    acpi_call \
    tp_smapi \
    x86_energy_perf_policy \
    lsb-release \
    tlp
sudo sed -i -e '/#STOP_CHARGE_THRESH_BAT1=80/a START_CHARGE_THRESH_BAT1=40\nSTOP_CHARGE_THRESH_BAT1=80' /etc/default/tlp
sudo systemctl enable tlp.service
sudo systemctl start tlp.service
sudo systemctl enable tlp-sleep.service
sudo systemctl start tlp-sleep.service
sudo systemctl mask systemd-rfkill.service
sudo systemctl mask systemd-rfkill.socket
sudo systemctl mask NetworkManager.service || true

echo "Installing security packages"
sudo pacman --noconfirm -S --needed \
    xscreensaver \
    xss-lock
yay -S xsecurelock-git

echo "Installing utility packages"
sudo pacman --noconfirm -S --needed \
    htop \
    iftop \
    iotop \
    dstat \
    links \
    jq \
    renameutils \
    run-parts \
    wmctrl \
    rsync \
    lsof \
    scrot \
    tldr \
    xsel \
    ufw
sudo pacman --noconfirm -S --needed \
    redshift \
    gimp \
    chromium \
    firefox

echo "Installing documentation packages"
sudo pacman --noconfirm -S --needed \
    linux-docs \
    dbus-docs \
    freedesktop-docs \
    xorg-docs \
    arch-wiki-docs

amixer sset Master unmute
systemctl enable fstrim.timer
sudo sensors-detect

pacman -Qqe > installed_packages.txt
git clone https://github.com/landofz/dotfiles.git
popd dotfiles
rm ~/.bashrc
stow -t ~/ bash
source ~/.bashrc
stow -t ~/ vim
stow -t ~/ x11
stow -t ~/ urxvt
stow -t ~/ tmux
stow -t ~/ i3

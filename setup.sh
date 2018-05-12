#!/bin/bash
# TODO up network interfaces
# TODO configure and start needed services
# TODO finish power management
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

echo "Setting NTP"
sudo pacman --noconfirm -S --needed chrony
sudo sed -i -e '/! pool 3.arch/a pool pool.ntp.org offline' /etc/chrony.conf
sudo sed -i -e 's/! maxupdateskew 100/maxupdateskew 100/' /etc/chrony.conf
sudo systemctl disable systemd-timesyncd.service
sudo systemctl enable chronyd.service
sudo systemctl start chronyd.service
sudo chronyc online
sudo chronyc makestep

### Install packages ###
echo "Installing core packages"
sudo pacman --noconfirm -S --needed \
    git \
    bash-completion \
    stow \
    tmux \
    vim \
    neovim
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
    thermald \
    powertop \
    smartmontools \
    hdparm \
    ethtool \
    tlp \
    acpi_call \
    tp_smapi
echo "Installing utility packages"
sudo pacman --noconfirm -S --needed \
    htop \
    links \
    jq \
    renameutils \
    run-parts \
    wmctrl \
    rsync \
    lsof \
    scrot \
    polkit \
    ufw
sudo pacman --noconfirm -S --needed \
    redshift \
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

#!/bin/bash
# TODO up network interfaces
# TODO configure and start needed services
# TODO finish power management
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### Set up logging ###
exec 1> >(tee "setup_stdout.log")
exec 2> >(tee "setup_stderr.log")

timedatectl set-ntp true

### Install packages ###
echo "Installing core packages"
pacman --noconfirm -S --needed \
    git \
    bash-completion \
    stow \
    tmux \
    vim \
    neovim
echo "Installing graphics packages"
# test if we need to install xf86-video-intel as well
pacman --noconfirm -S --needed \
    xf86-video-vesa \
    mesa \
    vulkan-intel
pacman --noconfirm -S --needed \
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
pacman --noconfirm -S --needed \
    i3 \
    rxvt-unicode \
    rofi
echo "Installing audio packages"
pacman --noconfirm -S --needed \
    alsa-utils \
    pulseaudio
echo "Installing power management packages"
pacman --noconfirm -S --needed \
    acpid \
    lm_sensors \
    cpupower \
    i7z \
    thermald \
    powertop \
    hdparm
echo "Installing utility packages"
pacman --noconfirm -S --needed \
    htop \
    links \
    jq \
    ufw
pacman --noconfirm -S --needed \
    chromium \
    firefox
echo "Installing documentation packages"
pacman --noconfirm -S --needed \
    linux-docs \
    dbus-docs \
    freedesktop-docs \
    xorg-docs \
    arch-wiki-docs

amixer sset Master unmute
git clone https://github.com/landofz/dotfiles.git

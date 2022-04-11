#!/bin/bash
# TODO make this script idempotent
# TODO configure and start needed services:
#    acpid
# TODO finish power management
# TODO udisks2, upower
# TODO autofs
# TODO setup delayed hibernation
# TODO polkit
# TODO hardware video acceleration (va-api)
# TODO profile-sync-daemon
# TODO pdnsd or other dns caching server
# TODO cronie, anacron
# TODO powerline fonts, nerd fonts, check font rendering
# TODO xf86-input-libinput, libinput
# TODO vdirsyncer, khal, khard
# TODO pipenv
# TODO docker, docker-compose, virtualbox
# TODO ripgrep, z.sh, up.sh
# TODO gvm, virtualenv, virtualenvwrapper
# TODO tig, zathura, command-not-found, zeal, diffoscope, syndaemon, fbreader
# TODO gpg-agent, ssh-agent, bluetoothd, mtp
# TODO cups, rsyslogd, irqbalance, haveged, avahi, colord/xiccd, accounts-daemon
# TODO intel-gpu-tools
# TODO borgbackup, neofetch, tldr, youtube-dl, rust, go, tmuxp, fd, bat, ncdu, rclone
# TODO ibus
# TODO aria2, sox, ctags, keychain, poppler
# TODO irqbalance
# TODO firejail
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

cd ~

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

echo "Configuring periodic TRIM"
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer

echo "Installing core packages"
sudo pacman --noconfirm -S --needed \
    alacritty \
    git \
    bash-completion \
    stow \
    python \
    python-pip \
    tmux \
    vim \
    neovim \
    elinks

if ! command -v yay > /dev/null; then
    echo "Setting AUR helper"
    sudo pacman --noconfirm -S --needed \
        go
    mkdir -p ~/src
    git clone https://aur.archlinux.org/yay.git ~/src/yay
    pushd ~/src/yay
    makepkg -si --noconfirm
    popd
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
yay -S --noconfirm --needed netctl-dispatcher-chrony

### Install packages ###
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
    xorg-setxkbmap \
    xorg-xmodmap \
    xorg-fonts-100dpi \
    xdotool
yay -S --noconfirm --needed acpilight
sudo pacman --noconfirm -S --needed \
    i3-wm \
    i3blocks \
    i3lock \
    i3status \
    rxvt-unicode \
    rofi \
    dunst \
    libnotify

echo "Installing audio packages"
sudo pacman --noconfirm -S --needed \
    alsa-utils \
    pulseaudio \
    pulseaudio-alsa \
    pavucontrol

echo "Installing power management packages"
# We don't install anything for fan speed control at the moment because on
# ThinkPads it is handled by EC automatically.
sudo pacman --noconfirm -S --needed \
    acpid \
    acpi \
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
# TODO: new TLP config from version 1.3.0 (/etc/tlp.conf)
sudo sed -i -e '/#DEVICES_TO_DISABLE_ON_STARTUP="bluetooth wifi wwan"/a DEVICES_TO_DISABLE_ON_STARTUP="bluetooth wwan"' /etc/default/tlp
sudo sed -i -e '/#STOP_CHARGE_THRESH_BAT0=80/a START_CHARGE_THRESH_BAT0=75\nSTOP_CHARGE_THRESH_BAT0=80' /etc/default/tlp
sudo sed -i -e '/#STOP_CHARGE_THRESH_BAT1=80/a START_CHARGE_THRESH_BAT1=50\nSTOP_CHARGE_THRESH_BAT1=90' /etc/default/tlp
sudo systemctl enable tlp.service
sudo systemctl start tlp.service
sudo systemctl enable tlp-sleep.service
sudo systemctl start tlp-sleep.service
sudo systemctl mask systemd-rfkill.service
sudo systemctl mask systemd-rfkill.socket
sudo systemctl mask NetworkManager.service || true
# https://www.smartmontools.org/wiki/Powermode
# do not complain if a device is removed after smartd starts
sudo sed -i -e '/^DEVICESCAN$/a DEVICESCAN -d removable -n standby' /etc/smartd.conf
sudo sed -i -e 's/^DEVICESCAN$/#DEVICESCAN/' /etc/smartd.conf
sudo systemctl enable smartd.service
sudo systemctl start smartd.service
sudo systemctl enable thermald.service
sudo systemctl start thermald.service

echo "Installing security packages"
sudo pacman --noconfirm -S --needed \
    xscreensaver \
    xss-lock \
    rng-tools \
    ufw
yay -S --noconfirm --needed xsecurelock-git
sudo systemctl enable rngd.service
sudo systemctl start rngd.service
sudo systemctl enable ufw.service
sudo systemctl start ufw.service
sudo ufw default deny
sudo ufw enable

echo "Installing utility packages"
sudo pacman --noconfirm -S --needed \
    htop \
    iftop \
    iotop \
    dstat \
    lynx \
    jq \
    exa \
    renameutils \
    run-parts \
    wmctrl \
    rsync \
    lsof \
    scrot \
    tldr \
    xsel \
    archiso \
    lshw \
    dmidecode \
    openbsd-netcat \
    xz \
    the_silver_searcher \
    fzf \
    w3m \
    ufw
sudo pacman --noconfirm -S --needed \
    redshift \
    gimp \
    chromium \
    qutebrowser \
    firefox

echo "Installing font packages"
sudo pacman --noconfirm -S --needed \
    ttf-font-awesome
yay -S --noconfirm --needed \
    ttf-ubuntu-mono-derivative-powerline-git \
    nerd-fonts-ubuntu-mono

echo "Installing documentation packages"
sudo pacman --noconfirm -S --needed \
    linux-docs \
    dbus-docs \
    freedesktop-docs \
    xorg-docs \
    arch-wiki-docs

amixer sset Master unmute
sudo sensors-detect --auto

pacman -Qqe > installed_packages.txt

rm -f ~/.bash_profile
mkdir -p ~/bin
mkdir -p ~/lib
git clone https://github.com/shannonmoeller/up.git ~/lib/up

mkdir -p ~/.config
mkdir -p ~/.local/share/applications
mkdir -p ~/.local/share/icons
mkdir -p ~/.vim/bundle
mkdir -p ~/.tmux/plugins
git clone https://github.com/landofz/dotfiles.git
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
git clone https://github.com/tmux-plugins/tpm.git ~/.tmux/plugins/tpm
pushd dotfiles
rm ~/.bashrc
rm ~/.bash_logout
stow -t ~/ bash
source ~/.bashrc
stow -t ~/ vim
stow -t ~/ x11
stow -t ~/ urxvt
stow -t ~/ tmux
stow -t ~/ i3
stow -t ~/ dunst
stow -t ~/ fzf
stow -t ~/ zathura
popd

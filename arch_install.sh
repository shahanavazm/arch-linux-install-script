#!/usr/bin/env bash
set -x -ueo pipefail
# -x print trace, -u define variables, -e error exit, -o pipefail for pipe errors

# Author: Shahanavaz Muhyideen, Date: Dec 31 2021.
# This script installs an arch system and bootloader refind to a drive which can be configured, such as /dev/sda.

# Usage:
# - Ensure the below configuration items are set to the correct values.
# - Run this script: ./arch_install.sh
# - The initial passwords for root and user are set as password.


# ---- Configuration begin.

# Drive to install to:
# Carefull. Make sure this is correct to prevent data loss.
DRIVE='/dev/sdx'

USERNAME='userx'
HOSTNAME='hnx'
TIMEZONE='America/New_York'
KEYMAP='us'
LOCALE1='LANG=en_US.UTF-8'
LOCALE2='en_US.UTF-8 UTF-8'
MIRRORS_COUNTRY='United States'

# ---- Configuration end.


main() {
    confirm_drive

    rank_mirrors

    partition 

    refind

    mount_partition 

    pacstrap    

    fstab    

    chroot

    umount_partition

    efibootmgr

    completed
}

inside_chroot() {
    bash_strictmode 

    hostname

    timezone

    locale

    keymap

    hosts

    root_password

    create_user

    network

    packages

    intel_ucode
}

confirm_drive() {
    echo Ensure install drive is correct: "$DRIVE"
    echo Press enter
    read -r
}

rank_mirrors() {
    reflector --verbose --country "$MIRRORS_COUNTRY" --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
    pacman -Sy
}

partition() {
    pacman --noconfirm --needed -S parted

    parted -s "$DRIVE" \
        mklabel gpt \
        mkpart ESP fat32 1MiB 512MiB \
        set 1 esp on \
        mkpart ROOT 512MiB 100%

    pacman --noconfirm --needed -S dosfstools
    mkfs.msdos -F 32 "$DRIVE"1

    mkfs.ext4 -F -L "$HOSTNAME" "$DRIVE"2
}

refind() {
    pacman --noconfirm --needed -S refind
    refind-install --usedefault "$DRIVE"1 --alldrivers
    umount "$DRIVE"1 || true # becuase refind-install seems to forget to do the unmount.
}

efibootmgr() {
    echo if needed run the following efibootmgr command:
    echo efibootmgr --create --disk "$DRIVE" --part 1 --loader /EFI/BOOT/bootx64.efi --label "refind-$HOSTNAME" --verbose
}

completed() {
    echo arch_install.sh completed successfully. 
}

mount_partition() {
    local arch_partition="$DRIVE"2
    mount "$arch_partition" /mnt
}

pacstrap() {
    # update system clock
    timedatectl set-ntp true

    # install base
    command pacstrap /mnt base linux linux-firmware
}

fstab() {
    genfstab -U /mnt > /mnt/etc/fstab
    # for usb destination change relatime to noatime in / line (ext4 line)
}

chroot() {
    export DRIVE USERNAME HOSTNAME TIMEZONE KEYMAP LOCALE1 LOCALE2
    export -f inside_chroot bash_strictmode hostname timezone locale keymap hosts root_password create_user network packages intel_ucode

    arch-chroot /mnt /bin/bash -c "inside_chroot"

    network_config
}

umount_partition() {
    umount -R /mnt
}

bash_strictmode() {
    set -x -ueo pipefail
    # -x print trace, -u define variables, -e error exit, -o pipefail for pipe errors
}

hostname() {
    echo "$HOSTNAME" > /etc/hostname
}

timezone() {
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

    # set hardware clock
    hwclock --systohc
}

locale() {
    echo "$LOCALE1" >> /etc/locale.conf
    echo "$LOCALE2" >> /etc/locale.gen
    locale-gen
}

keymap() {
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
}

hosts() {
    echo "127.0.0.1 localhost.localdomain localhost $HOSTNAME" >> /etc/hosts 
    echo "::1       localhost.localdomain localhost $HOSTNAME" >> /etc/hosts 
}

root_password() {
    local password="password"

    echo -en "$password\n$password" | passwd
    echo "root    ALL=(ALL) ALL" >> /etc/sudoers
}

create_user() {
    local password="password"

    useradd -m -s /bin/bash "$USERNAME" || true
    echo -en "$password\n$password" | passwd "$USERNAME"
    echo "%wheel    ALL=(ALL) ALL" >> /etc/sudoers
    usermod -aG wheel "$USERNAME"
}

network() {
    # systemd network config files are copied after chroot    

    systemctl enable systemd-networkd.service
    systemctl enable systemd-resolved.service

    # for wireless networking
    pacman --noconfirm --needed -S iwd
    systemctl enable iwd.service
}

network_config() {
    # copy systemd network config files
    cp -a /etc/systemd/network/*.network /mnt/etc/systemd/network/
    mkdir -p /mnt/var/lib/iwd
    cp -a /var/lib/iwd/*.psk /mnt/var/lib/iwd/ || true
}

packages() {
    declare -a packages

    packages+=(openssh sshfs gvim sudo man)

    # for debugging dhcp
    packages+=(dhcpcd)

    # allows to run startx and get a gui
    packages+=(xorg-server xterm)

    # firefox
    packages+=(firefox)

    # i3
    packages+=(i3-wm i3lock i3status dmenu)

    # login manager
    packages+=(lightdm lightdm-gtk-greeter)

    packages+=(pulseaudio pavucontrol)

    packages+=(archlinux-keyring)

    pacman --noconfirm --needed -S "${packages[@]}" 

    systemctl enable lightdm.service
}

intel_ucode() {
    pacman --noconfirm --needed -S intel-ucode
    local uuid
    uuid=$(blkid -o value -s UUID "$DRIVE"2)

    local params=""
    params+="root=UUID=$uuid "
    params+="rw "
    params+="add_efi_memmap "
    params+="initrd=boot\intel-ucode.img "
    params+="initrd=boot\initramfs-linux.img"

    echo "\"Boot using default options\" \"$params\"" > /boot/refind_linux.conf
}

main

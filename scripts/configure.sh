exit

echo Setting time
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc

echo Generating locale
sed -i 's/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/g' /etc/locale.gen
sed -i 's/#en_GB ISO-8859-1/en_GB ISO-8859-1/g' /etc/locale.gen
locale-gen

echo Setting locale
echo LANG=en_GB.UTF-8 > /etc/locale.conf

echo Setting keyboard layout
sed -i '/^keymap=/c\keymap="uk"' /etc/conf.d/keymaps
echo KEYMAP=uk > /etc/vconsole.conf

echo Enabling parallel pacman downloads
sed -i '/^#ParallelDownloads =/c\ParallelDownloads = 10' /etc/pacman.conf

echo Enabling lib32 repository
perl -0777 -i -pe 's:#\[lib32\]\n#Include = /etc/pacman.d/mirrorlist:\[lib32\]\nInclude = /etc/pacman.d/mirrorlist:g' /etc/pacman.conf

echo Adding universe repository
cat << EOF >> /etc/pacman.conf

[universe]
Server = https://universe.artixlinux.org/\$arch
Server = https://mirror1.artixlinux.org/universe/\$arch
Server = https://mirror.pascalpuffke.de/artix-universe/\$arch
Server = https://artixlinux.qontinuum.space/artixlinux/universe/os/\$arch
Server = https://mirror1.cl.netactuate.com/artix/universe/\$arch
Server = https://ftp.crifo.org/artix-universe/
EOF

echo Installing Arch repository support
pacman -Syu --noconfirm artix-archlinux-support

echo Adding omniverse \& Arch repositories
cat << EOF >> /etc/pacman.conf

[omniverse]
Server = http://omniverse.artixlinux.org/\$arch
    
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[community]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

echo Installing pacman rankmirrors utility
pacman -Syu --noconfirm pacman-contrib

echo Ranking Artix mirrors
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.backup
rankmirrors /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist

echo Getting and ranking up-to-date Arch mirrors
cp /etc/pacman.d/mirrorlist-arch /etc/pacman.d/mirrorlist-arch.backup
curl -s "https://archlinux.org/mirrorlist/?country=FR&country=GB&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' >> /etc/pacman.d/mirrorlist-arch.backup
rankmirrors /etc/pacman.d/mirrorlist-arch.backup > /etc/pacman.d/mirrorlist-arch

echo Adding chaotic-aur support
pacman-key --recv-key FBA220DFC880C036 --keyserver keyserver.ubuntu.com
pacman-key --lsign-key FBA220DFC880C036
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

echo Adding chaotic-aur repository
cat << EOF >> /etc/pacman.conf

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF

echo Installing all packages
pacman -Syyu --noconfirm grub efibootmgr alacritty alsa-utils amd-ucode btop dhcpcd discord dolphin exa ffmpegthumbnailer ffmpegthumbs firedragon fish gimp git gparted gtk3-nocsd-git gtk3-patched-filechooser-icon-view gwenview helix imagemagick kde-gtk-config kdegraphics-thumbnailers kdesdk-thumbnailers kimageformats libappindicator-gtk2 libappindicator-gtk3 linux-zen-headers nano neofetch noto-fonts-cjk ntfs-3g numlockx nvidia-dkms paru pipewire pipewire-alsa pipewire-pulse plasma-desktop plasma-pa plasma5-applets-window-appmenu powerdevil-light qt5-imageformats raw-thumbnailer resvg rustup rust-analyzer spotify steam sudo thunderbird tmux tor-browser ttf-liberation ttf-twemoji unbound unbound-openrc ungoogled-chromium wget xorg xorg-xinit pipewire-jack wireplumber phonon-qt5-vlc lib32-nvidia-utils gtk2-patched-filechooser-icon-view gtk3-patched-filechooser-icon-view glib2-patched-thumbnailer cryptsetup btrfs-progs git-credential-manager-core pass

cd /install

echo Installing mkinitcpio-numlock hook
paru -G mkinitcpio-numlock
chown nobody mkinitcpio-numlock/
cd mkinitcpio-numlock
sudo -u nobody makepkg
pacman -U --noconfirm mkinitcpio-numlock*.pkg.tar.zst
cd ..

echo Calculating swapfile offset
curl -O https://raw.githubusercontent.com/osandov/osandov-linux/master/scripts/btrfs_map_physical.c
gcc -O2 -o btrfs_map_physical btrfs_map_physical.c
./btrfs_map_physical /swap/swapfile.img | head -n 2 > swap_btrfs_map_physical
i=$(cat swap_btrfs_map_physical | head -n 1 | awk '{print gsub(/\t/,"")}')
let "i++"
n=$(cat swap_btrfs_map_physical | tail -n 1 | cut -f $i)
p=$(getconf PAGESIZE)
o=$(($n/$p))
cd /

echo Getting filesystem UUIDs
regex='\sUUID="([^"]+)'
[[ $(blkid /dev/mapper/root) =~ $regex ]]

cryptdev=$(cat /install/cryptdev)

echo Setting grub kernel options
sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 nvidia-drm.modeset=1 amd_iommu=on iommu=pt"' /etc/default/grub
sed -i '/^GRUB_CMDLINE_LINUX=/c\GRUB_CMDLINE_LINUX="cryptdevice=UUID=${cryptdev}:root:allow-discards resume=UUID=${BASH_REMATCH[1]} resume_offset=${o}"'

echo Installing grub \& making grub config
grub-install --bootloader-id=Grub
grub-mkconfig -o /boot/grub/grub.cfg

echo Adding mel user
useradd -G wheel -m mel

echo Setting wheel sudo permissions
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers

echo Setting hostname
echo mel-artix > /etc/hostname
sed -i '/^hostname=/c\hostname="mel-artix"' /etc/conf.d/hostname
cat << EOF >> /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    mel-artix
EOF

echo Setting up network
sed -i '/^#config_eth0=/c\config_eth0="dhcp"' /etc/conf.d/net
ln -s /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 default

echo Setting mkinitcpio hooks
sed -i '/^HOOKS=/c\HOOKS=(base udev autodetect keyboard keymap numlock modconf block encrypt resume filesystems fsck)' /etc/mkinitcpio.conf
mkinitcpio -P

#todo
#rc-update del agetty.tty1 default
#ln -s agetty-autologin agetty-autologin.tty1
#rc-update add agetty-autologin.tty1 default

echo Set root password
passwd

echo Set mel password
passwd mel

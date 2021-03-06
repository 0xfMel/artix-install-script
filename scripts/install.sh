set -e
set -o pipefail

echo Setting keyboard layout
loadkeys uk

read -p "Device to install to: " installdev
read -s -p "New System Encryption Password: " encpass
echo
read -s -p "Existing Data Disk Encryption Password: " hddpass
echo
read -s -p "Existing Data SSD 1 Encryption Password: " ssd1pass
echo
read -s -p "Existing Data SSD 2 Encryption Password: " ssd2pass
echo
read -p "Data Disk Device: " hdddev
read -p "SSD 1 Device: " ssd1dev
read -p "SSD 2 Device: " ssd2dev

read -p "Install to ${installdev}? " shouldcontinue

if [ shouldcontinue -ne "y" ]; then
  exit 1
fi

partprefix=""
if [[ ${1: -1} =~ ^-?[0-9]+$ ]]; then
  partprefix="p"
fi

echo Partitioning root device
printf "g\nn\n\n\n+128M\nn\n\n\n+512M\nn\n\n\n\nt\n1\n1\nt\n\n23\nw\n" | fdisk "$installdev"

echo Making EFI filesystem
part1="${installdev}${partprefix}1"
mkfs.fat -F 32 "$part1"

echo Setting EFI filesystem label...
until [ -e /dev/disk/by-label/EFI ]; do
  fatlabel "$part1" EFI
done
echo EFI filesystem label set

echo Making boot filesystem
mkfs.btrfs -L BOOT -f "${installdev}${partprefix}2"

echo Making encrypted root partition
part3="${installdev}${partprefix}3"
printf "$encpass" | cryptsetup luksFormat "$part3"
printf "$encpass" | cryptsetup open "$part3" root

echo Opening Data Disk
printf "$hddpass" | cryptsetup open "$hdddev" hdd
echo Opening SSD 1
printf "$ssd1pass" | cryptsetup open "$ssd1dev" ssd1
echo Opening SSD 2
printf "$ssd2pass" | cryptsetup open "$ssd2dev" ssd2

echo Making root filesystem
mkfs.btrfs -L ROOT -f /dev/mapper/root

echo Waiting for root filesystem
until [ -e /dev/disk/by-label/ROOT ]; do
  sleep 1
done
echo Got root filesystem

echo Mounting root devices
mount /dev/mapper/root /mnt
mkdir /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot
mkdir /mnt/boot/efi
mount /dev/disk/by-label/EFI /mnt/boot/efi

echo Mounting data devices
mkdir -p /mnt/data/hdd
mkdir /mnt/data/ssd
mount /dev/mapper/hdd /mnt/data/hdd
mount /dev/disk/by-label/Data\\x20SSD /mnt/data/ssd

echo Making swap file
btrfs subvolume create /mnt/swap
chattr +C /mnt/swap
truncate -s 0 /mnt/swap/swapfile.img
fallocate -l 24G /mnt/swap/swapfile.img
chmod 0600 /mnt/swap/swapfile.img
mkswap /mnt/swap/swapfile.img
swapon /mnt/swap/swapfile.img

echo Making new data device keys
mkdir -p /mnt/etc/keys
dd if=/dev/random of=/mnt/etc/keys/hddkey.key bs=64 count=1
dd if=/dev/random of=/mnt/etc/keys/ssd1key.key bs=64 count=1
dd if=/dev/random of=/mnt/etc/keys/ssd2key.key bs=64 count=1

echo Adding new Data Disk key
printf "$hddpass" | cryptsetup luksAddKey "$hdddev" /mnt/etc/keys/hddkey.key
echo Adding new SSD 1 key
printf "$ssd1pass" | cryptsetup luksAddKey "$ssd1dev" /mnt/etc/keys/ssd1key.key
echo Adding new SSD 2 key
printf "$ssd2pass" | cryptsetup luksAddKey "$ssd2dev" /mnt/etc/keys/ssd2key.key

chmod 000 /mnt/etc/keys/*
chmod -R g-rxw,o-rwx /mnt/etc/keys

echo Enabling parallel pacman downloads
sed -i '/^#ParallelDownloads =/c\ParallelDownloads = 10' /etc/pacman.conf

echo Installing artix base, runit, and linux-zen kernel
basestrap /mnt base base-devel runit elogind elogind-runit linux-zen linux-firmware

echo Generating fstab
fstabgen -U /mnt >> /mnt/etc/fstab

echo Copying installation \& config files to root
mkdir /mnt/install
cp -r ./scripts /mnt/install

echo Saving root encrpyted device UUID to root
regex='\sUUID="([^"]+)'
[[ $(blkid "$part3") =~ $regex ]]
echo ${BASH_REMATCH[1]} > /mnt/install/cryptdev

echo Running configure script in root
artix-chroot /mnt sh /install/scripts/configure.sh

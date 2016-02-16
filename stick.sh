#!/bin/bash
set -x

TARGET=/dev/sdb
KSFILE=yttrium.ks

echo 'partition table wrangling'
cat sfdisk.script | sudo sfdisk ${TARGET}

echo 'write mbr booter for syslinux'
sudo dd conv=notrunc bs=440 count=1 if=/usr/share/syslinux/mbr.bin of=${TARGET}

echo 'creating vfat fs'
sudo mkfs -t vfat -n "KICKSTART" ${TARGET}1

echo 'installing syslinux'
sudo syslinux ${TARGET}1

echo 'retrieving kernel'
curl -L -o vmlinuz http://mirrors.kernel.org/centos/7/os/x86_64/isolinux/vmlinuz

echo 'retrieving initrd'
curl -L -o initrd.img http://mirrors.kernel.org/centos/7/os/x86_64/isolinux/initrd.img

echo 'retrieving EFI kit'
curl -L -o unicode.pf2 http://mirrors.kernel.org/centos/7/os/x86_64/EFI/BOOT/fonts/unicode.pf2
curl -L -o grubx64.efi http://mirrors.kernel.org/centos/7/os/x86_64/EFI/BOOT/grubx64.efi
curl -L -o MokManager.efi http://mirrors.kernel.org/centos/7/os/x86_64/EFI/BOOT/MokManager.efi
curl -L -o BOOTX64.EFI http://mirrors.kernel.org/fedora/releases/23/Workstation/x86_64/os/EFI/BOOT/BOOTX64.EFI

echo 'copying EFI imagery'
sudo env MTOOLS_SKIP_CHECK=1 mmd -i ${TARGET}1 EFI
sudo env MTOOLS_SKIP_CHECK=1 mmd -i ${TARGET}1 EFI/BOOT
sudo env MTOOLS_SKIP_CHECK=1 mmd -i ${TARGET}1 EFI/BOOT/fonts
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 unicode.pf2 ::EFI/BOOT/fonts
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 grubx64.efi ::EFI/BOOT
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 grub.cfg ::EFI/BOOT
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 MokManager.efi ::EFI/BOOT
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 BOOTX64.EFI ::EFI/BOOT

echo 'copying vmlinuz, initrd to usb stick'
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 vmlinuz ::
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 initrd.img ::

echo 'copying syslinux.cfg to usb stick'
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 syslinux.cfg ::

echo "copying ${KSFILE} to usb stick as ks.cfg"
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 ${KSFILE} ::ks.cfg

sync

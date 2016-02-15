#!/bin/bash
set -x

TARGET=/dev/sdb
KSFILE=lunarsea.ks

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

echo 'copying vmlinuz, initrd to usb stick'
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 vmlinuz ::
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 initrd.img ::

echo 'copying syslinux.cfg to usb stick'
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 syslinux.cfg ::

echo "copying ${KSFILE} to usb stick as ks.cfg"
sudo env MTOOLS_SKIP_CHECK=1 mcopy -i ${TARGET}1 ${KSFILE} ::ks.cfg

sync

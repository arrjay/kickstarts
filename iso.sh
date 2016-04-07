#!/bin/bash
set -x

ISOFILE=kickstart.iso
KSFILE=lunarsea.ks
OUTPUT=$(pwd)/ks.iso

echo 'creating scratch directory'
WORK=$(mktemp -d)

echo 'finding isolinux loader'

isolx=''
if [ -f /usr/share/syslinux/isolinux.bin ] ; then
  isolx="/usr/share/syslinux/isolinux.bin"
fi

if [ -z "${isolx}" ] ; then
  echo 'isolinux not found aborting'
  exit 2
fi

echo 'retrieving kernel'
#curl -L -o vmlinuz http://mirrors.kernel.org/centos/7/os/x86_64/images/pxeboot/vmlinuz

echo 'retrieving initrd'
#curl -L -o initrd.img http://mirrors.kernel.org/centos/7/os/x86_64/images/pxeboot/initrd.img

echo 'retrieving stage2'
#curl -L -o squashfs.img http://mirrors.kernel.org/centos/7/os/x86_64/LiveOS/squashfs.img

echo 'retrieving EFI kit'
#curl -L -o unicode.pf2 http://mirrors.kernel.org/fedora/releases/23/Server/x86_64/os/EFI/BOOT/fonts/unicode.pf2
#curl -L -o grubx64.efi http://mirrors.kernel.org/fedora/releases/23/Server/x86_64/os/EFI/BOOT/grubx64.efi
#curl -L -o MokManager.efi http://mirrors.kernel.org/fedora/releases/23/Server/x86_64/os/EFI/BOOT/MokManager.efi
#curl -L -o BOOTX64.EFI http://mirrors.kernel.org/fedora/releases/23/Workstation/x86_64/os/EFI/BOOT/BOOTX64.EFI

echo 'populating isolinux scratch dir'
mkdir $WORK/isolinux
cp $isolx $WORK/isolinux

echo 'copying EFI imagery'
mkdir -p $WORK/EFI/BOOT/fonts
cp unicode.pf2 $WORK/EFI/BOOT/fonts
cp grubx64.efi $WORK/EFI/BOOT
cp grub.cfg $WORK/EFI/BOOT
cp MokManager.efi $WORK/EFI/BOOT
cp BOOTX64.EFI $WORK/EFI/BOOT

echo 'copying vmlinuz, initrd, install to scratch dir'
mkdir -p $WORK/images/pxeboot
cp vmlinuz $WORK/images/pxeboot
cp initrd.img $WORK/images/pxeboot

echo 'copying syslinux.cfg to scratch dir'
cp syslinux.cfg $WORK/isolinux/isolinux.cfg

echo 'creating image links'
(cd $WORK/isolinux && ln ../images/pxeboot/vmlinuz)
(cd $WORK/isolinux && ln ../images/pxeboot/initrd.img)

mkdir -p $WORK/LiveOS
cp squashfs.img $WORK/LiveOS

echo 'creating iso'
mkisofs -r -T -J -V "KICKSTART" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -v -o ${OUTPUT} ${WORK}

rm -rf "${WORK}"

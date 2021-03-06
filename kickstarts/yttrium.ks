#version=DEVEL
# System authorization information
auth --enableshadow --passalgo=sha512

# leave this unset for closest-mirror setup
# Use network installation
url --url="http://mirrors.kernel.org/fedora/releases/22/Server/x86_64/os"
repo --name=everything --baseurl="http://mirrors.kernel.org/fedora/releases/22/Everything/x86_64/os"
repo --name=updates --baseurl="http://mirrors.kernel.org/fedora/updates/22/x86_64"

# Use text mode
text
# Don't run the Setup Agent on first boot
firstboot --disable
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang en_US.UTF-8

# reboot when done
reboot

# Network information
network  --bootproto=dhcp --device=br1 --bridgeslaves=enp10s0 --bridgeopts=ageing-time=15,stp=no --onboot=on --noipv4 --noipv6
network  --bootproto=dhcp --device=enp9s0 --onboot=off --ipv6=auto --noipv4 --noipv6
network  --bootproto=static --device=enp9s0 --vlanid=5 --ip=172.16.128.57 --gateway=172.16.128.254 --netmask=255.255.255.0 --nameserver=172.16.128.36 --nameserver=172.16.128.30 --ipv6=auto --activate --hostname=yttrium.produxi.net

# Root password
rootpw --iscrypted $6$m95xGSDD7uy.OlhR$1fkOb4IJhARxPZtuc7Mx85tHBY0nf9eEmEE7Zw4Xweh1M4n5kUZ/Ny7xPACUHHfbKNz3dFoxbOurCWpD89YPs.
# System timezone
timezone America/New_York --isUtc

# initialize raid devices in %pre, then present to kickstart
%pre
#!/bin/bash
# first, stop and DESTROY all md arrays
for md in /dev/md[0-9]* ; do
  parts=$(mdadm --detail $md | awk '$5 ~ "dev" { print $5 }')
  mdadm --stop $md
  mdadm --remove $md
  mdadm --zero-superblock ${parts}
done

# pci0000:00 is the root pci domain
# 0000:00:1f.2 is the AHCI controller
# NOTE: we are assuming there _are_ 4 disks here, just not what their names are.
dlist=$(for x in /sys/devices/pci0000\:00/0000\:00\:1f.2/ata*/*/*/*/block/* ; do basename $x | grep ^sd ; done)

# loop on the disk list and stamp out partition tables
for disk in $dlist ; do
  # delete any partition tables, including gpt backup header
  dd if=/dev/zero of=/dev/$disk bs=4096 count=35
  dd if=/dev/zero of=/dev/$disk bs=4096 count=35 seek=$(($(blockdev --getsz /dev/$disk)*512/4096 - 35))
  # create new GPT table
  # 501GB /boot, 201GB /boot/efi, remainder to RAID10
  printf 'mklabel gpt\nmkpart "" efi 1049kB 201mB\nmkpart "" boot 201mB 701mB\nmkpart "" system 701mB 100%%\nquit' | parted /dev/$disk
  # toggle RAID flags
  printf 'toggle 1 raid\ntoggle 2 raid\ntoggle 3 raid\nquit' | parted /dev/$disk
  partprobe /dev/$disk
done

# make RAID devices
# counter for disk partition number
partno=1

# create raid1 1.0 devices
r1list="boot_efi boot"
for raid in $r1list ; do
  parts=''
  # add partition number to the raid subdevices
  for disk in $dlist ; do
    mdadm --zero-superblock /dev/$disk$partno
    parts="${parts}/dev/$disk$partno "
  done
  echo "y" | mdadm -C /dev/md/$raid -o -N $raid --level=1 --raid-devices=4 --metadata=1.0 --homehost=yttrium.produxi.net ${parts}
  (( partno++ ))
done

# create raid10 devices
r10list="system"
for raid in $r10list ; do
  parts=''
  # add partition number to the raid subdevices
  for disk in $dlist ; do
    mdadm --zero-superblock /dev/$disk$partno
    parts="${parts}/dev/$disk$partno "
  done
  # hack incase the tail end of the disks are missized
  # create raid10 volume read-only as we get to reassemble it a lot.
  echo "y" | mdadm -C /dev/md/$raid -o -N $raid --level=10 --raid-devices=4 --homehost=yttrium.produxi.net ${parts}
  (( partno++ ))
done

# now...go back and break boot_efi + boot
efidisk=$(mdadm -D /dev/md/boot_efi | awk '$7 ~ "dev" { print $7 }' | head -n1)
mdadm /dev/md/boot_efi --fail $efidisk --remove $efidisk
mdadm --zero-superblock $efidisk
mkfs.hfsplus -v boot_efi $efidisk
efidisk=$(basename $efidisk)

bootdisk=$(mdadm -D /dev/md/boot | awk '$7 ~ "dev" { print $7 }' | head -n1)
mdadm /dev/md/boot --fail $bootdisk --remove $bootdisk
mdadm --zero-superblock $bootdisk
bootdisk=$(basename $bootdisk)

bootvol=${efidisk:0:3}

# write boot(_efi) out in a template, because we're not entirely sure what device we got.
rm /tmp/r1-include
printf 'bootloader --append="intel_iommu=on pci-stub.ids=1033:0194" --location=mbr --boot-drive=%s\n' $bootvol >> /tmp/r1-include
printf 'part /boot/efi --fstype=macefi --onpart="%s"\n' $efidisk >> /tmp/r1-include
printf 'part /boot --fstype=ext4 --onpart="%s"\n' $bootdisk >> /tmp/r1-include

# save existing md config
mdadm --detail --scan > /tmp/md-scratch
%end

# System bootloader configuration
# okay, assemble the RAID-y bits
%include /tmp/r1-include
raid pv.1248 --device=system --fstype="lvmpv" --useexisting

# LVM atop RAID10
volgroup yttrium --pesize=4096 pv.1248
logvol / --fstype="ext4" --grow --maxsize=36834 --size=1024 --name=root --vgname=yttrium
logvol swap --fstype="swap" --size=8192 --name=swap --vgname=yttrium
logvol /var/lib/libvirt  --fstype="xfs" --size=18432 --name=var_lib_libvirt --vgname=yttrium

# System services
services --enabled="chronyd"

%packages
@^minimal-environment
grub2-efi-modules
chrony
policycoreutils-python

avahi

screen
dstat
smartmontools
htop

lsscsi
pciutils
usbutils
dmidecode

libvirt
qemu-kvm
virt-install
libguestfs-tools
kernel-devel

xauth

nut

augeas

dnf-plugin-system-upgrade

%end

%addon com_redhat_kdump --disable --reserve-mb='128'

%end

%anaconda
pwpolicy root --minlen=0 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy user --minlen=0 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=0 --minquality=1 --notstrict --nochanges --emptyok
%end

%post --nochroot	# NOTE: needed because we snarf the md config written in %pre
fver=$(. /etc/os-release ;echo $VERSION_ID)
# allow unsafe pci interrupt setup for pci-e passthrough
echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" > /mnt/sysimage/etc/modprobe.d/vfio_iommu_type1.conf

# vfio-pci notes
# 1033:0194 - USB3 controller
echo "softdep vfio-pci post: vfio_iommu_type1" > /mnt/sysimage/etc/modprobe.d/vfio-pci.conf
echo "options vfio-pci ids=1033:0194" >> /mnt/sysimage/etc/modprobe.d/vfio-pci.conf
printf 'add_drivers+="vfio-pci "\n' >> /mnt/sysimage/etc/dracut.conf
printf 'cgroup_device_acl = [ "/dev/null", "/dev/full", "/dev/zero", "/dev/random", "/dev/urandom", "/dev/ptmx", "/dev/kvm", "/dev/kqemu", "/dev/rtc","/dev/hpet", "/dev/vfio/vfio", "/dev/vfio/22", "/dev/vfio/14" ]\n' >> /etc/libvirt/qemu.conf


# put boot(_efi) back together
mdadm --assemble boot -c /tmp/md-scratch
mdadm --assemble boot_efi -c /tmp/md-scratch
grep boot /tmp/md-scratch >> /mnt/sysimage/etc/mdadm.conf
mbootdev=$(df --output=source /mnt/sysimage/boot | tail -n1)
mefidev=$(df --output=source /mnt/sysimage/boot/efi | tail -n1)
mkfs.ext4 /dev/md/boot
#mkfs.vfat -F32 -n EFI_BOOT /dev/md/boot_efi
mkfs.hfsplus -v boot_efi /dev/md/boot_efi
mount /dev/md/boot /mnt/sysimage/mnt
mkdir /mnt/sysimage/mnt/efi
mount /dev/md/boot_efi /mnt/sysimage/mnt/efi
rsync -a /mnt/sysimage/boot/ /mnt/sysimage/mnt/
umount /mnt/sysimage/boot/efi
umount /mnt/sysimage/boot
umount /mnt/sysimage/mnt/efi
umount /mnt/sysimage/mnt
mount /dev/md/boot /mnt/sysimage/boot
mount /dev/md/boot_efi /mnt/sysimage/boot/efi
mdadm -a /dev/md/boot ${mbootdev}
mdadm -a /dev/md/boot_efi ${mefidev}
grep -v system /tmp/md-scratch >> /mnt/sysimage/etc/md.conf
grep -v /boot /mnt/sysimage/etc/fstab > /tmp/fstab.1
printf '/dev/md/boot /boot ext4 defaults 1 2\n' >> /tmp/fstab.1
printf '/dev/md/boot_efi /boot/efi hfsplus defaults 0 2\n' >> /tmp/fstab.1
cp /tmp/fstab.1 /mnt/sysimage/etc/fstab
for kver in $(chroot /mnt/sysimage rpm -q kernel --qf '%{version}-%{release}.%{arch}') ; do
chroot /mnt/sysimage dracut -f --kver ${kver}
done

# mangle the grub config...
printf 'GRUB_DISABLE_OS_PROBER="true"\n' >> /mnt/sysimage/etc/default/grub
sed -i -e 's/rhgb//' $(readlink -f /mnt/sysimage/etc/default/grub)
chroot /mnt/sysimage grub2-mkconfig > /mnt/sysimage/etc/grub2-efi.cfg

# turn dhcp off on br1
sed -i -e 's/BOOTPROTO=dhcp//' /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-br1
printf 'BRIDGING_OPTS=ageing_time=5\n' >> /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-br1

# turn off ipv6 on br1
cat << EOD > /mnt/sysimage/etc/NetworkManager/dispatcher.d/00-axe-ipv6.sh
#!/bin/bash

case "\${1}" in
  br1)
    sysctl "net.ipv6.conf.\${1}.disable_ipv6"=1
    ;;
esac
EOD
( cd /mnt/sysimage/etc/NetworkManager/dispatcher.d/pre-up.d && ln -s ../00-axe-ipv6.sh )
chmod 0755 /mnt/sysimage/etc/NetworkManager/dispatcher.d/00-axe-ipv6.sh
chown root:root /mnt/sysimage/etc/NetworkManager/dispatcher.d/00-axe-ipv6.sh

# create 'home' bridge
cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-Bridge_connection_home
DEVICE=home
STP=no
TYPE=Bridge
BOOTPROTO=none
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=no
IPV6_AUTOCONF=no
IPV6_DEFROUTE=no
IPV6_PEERDNS=no
IPV6_PEERROUTES=no
IPV6_FAILURE_FATAL=no
NAME="Bridge connection home"
ONBOOT=yes
IPADDR=172.16.128.57
PREFIX=24
GATEWAY=172.16.128.254
DNS1=172.16.128.30
DNS2=172.16.128.36
DOMAIN=produxi.net
EOI

# rebind the VLAN interface to it.
enphw=$(ip addr show enp9s0.5|grep ether|awk '{print $2}')
cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-enp9s0.5
PHYSDEV=enp9s0
BRIDGE=home
NAME="VLAN connection enp9s0.5"
VLAN=yes
DEVICE=enp9s0.5
TYPE=Vlan
HWADDR=${enphw}
ONBOOT=yes
VLAN_ID=5
REORDER_HDR=0
EOI

# make some other vlans...
cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-enp9s0.4
PHYSDEV=enp9s0
BRIDGE=admin
NAME="VLAN connection enp9s0.4"
VLAN=yes
DEVICE=enp9s0.4
TYPE=Vlan
HWADDR=${enphw}
ONBOOT=yes
VLAN_ID=4
REORDER_HDR=0
EOI

cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-Bridge_connection_admin
DEVICE=admin
STP=no
TYPE=Bridge
BOOTPROTO=none
DEFROUTE=no
IPV4_FAILURE_FATAL=no
IPV6INIT=no
IPV6_AUTOCONF=no
IPV6_DEFROUTE=no
IPV6_PEERDNS=no
IPV6_PEERROUTES=no
IPV6_FAILURE_FATAL=no
NAME="Bridge connection admin"
ONBOOT=yes
EOI

cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-enp9s0.6
PHYSDEV=enp9s0
BRIDGE=chaos
NAME="VLAN connection enp9s0.6"
VLAN=yes
DEVICE=enp9s0.6
TYPE=Vlan
HWADDR=${enphw}
ONBOOT=yes
VLAN_ID=6
REORDER_HDR=0
EOI

cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-Bridge_connection_chaos
DEVICE=chaos
STP=no
TYPE=Bridge
BOOTPROTO=none
DEFROUTE=no
IPV4_FAILURE_FATAL=no
IPV6INIT=no
IPV6_AUTOCONF=no
IPV6_DEFROUTE=no
IPV6_PEERDNS=no
IPV6_PEERROUTES=no
IPV6_FAILURE_FATAL=no
NAME="Bridge connection chaos"
ONBOOT=yes
EOI

cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-enp9s0.7
PHYSDEV=enp9s0
BRIDGE=guest
NAME="VLAN connection enp9s0.7"
VLAN=yes
DEVICE=enp9s0.7
TYPE=Vlan
HWADDR=${enphw}
ONBOOT=yes
VLAN_ID=7
REORDER_HDR=0
EOI

cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-Bridge_connection_guest
DEVICE=guest
STP=no
TYPE=Bridge
BOOTPROTO=none
DEFROUTE=no
IPV4_FAILURE_FATAL=no
IPV6INIT=no
IPV6_AUTOCONF=no
IPV6_DEFROUTE=no
IPV6_PEERDNS=no
IPV6_PEERROUTES=no
IPV6_FAILURE_FATAL=no
NAME="Bridge connection guest"
ONBOOT=yes
EOI

cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-enp9s0.8
PHYSDEV=enp9s0
BRIDGE=transit
NAME="VLAN connection enp9s0.8"
VLAN=yes
DEVICE=enp9s0.8
TYPE=Vlan
HWADDR=${enphw}
ONBOOT=yes
VLAN_ID=8
REORDER_HDR=0
EOI

cat << EOI > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-Bridge_connection_transit
DEVICE=transit
STP=no
TYPE=Bridge
BOOTPROTO=none
DEFROUTE=no
IPV4_FAILURE_FATAL=no
IPV6INIT=no
IPV6_AUTOCONF=no
IPV6_DEFROUTE=no
IPV6_PEERDNS=no
IPV6_PEERROUTES=no
IPV6_FAILURE_FATAL=no
NAME="Bridge connection transit"
ONBOOT=yes
EOI

# disable passwords for ssh
chroot /mnt/sysimage augtool set /files/etc/ssh/sshd_config/PermitRootLogin without-password
mkdir /mnt/sysimage/root/.ssh
# and install a pubkey
cat << EOE > /mnt/sysimage/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDTRxypN4BeG6XdQPlr72SnNM18MHpM1rXqQNo3GwxVTZA7LXXCmTstWUPctUrk92uRkAOP335OoKN+njX4De022V+jlpPG9rHuDT93KOBTK8vmWwAOSBlvAe/5ebmhKoxuPEMe2M2FximeE99Uqk3uVLSJHDVjM1Q3g0onPx9HW3vzptP+7N9E9WzsaKrhE5Ns0NMgqLEdMiFj2x3OuDySoCS84nCQFC9Q966Ov8CBugX6/4R2yytNzjJ2UJ+mwvesEPZSH7kzQrTVPklyKhdG/i1OeMN0z38/QmGkLiJd174/yUy9TQBQ4NQSdSAffKNe0UZXpLTXUxPuGkcR4vH69wamWyQZMgRUvmVD/UygHMJQfxXMs03Xo4M6FdC7ejFVUxs7wHptSweKdDvI6OIPKHgZcrNuPXjIohXrCUPrx/tHPvZjmBz3gH4eb2z0zoTrGwHTIMXb8ahStRCfTBnbJvfEn+vn3sXHlb6IBtyMJY9kQ8E0YNsLkIVky+aXk/wXWFHKi6yCG62pCCX0+kCzDyTFzd2AS/jom+3NzL1eAhK7chQuaxdAPqJIH8gEfud9tLzZ85lJ0ZkChoAyNitVYkAKRR1ueAKXzPOg2Gt2LOtht2Tqr+MNBXlepfkE+TaltlygtpKLtsDo17TfuMhdfWJgLd6S705G91FOh3893Q== cardno:000500003E35
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3OueMyB4NBGlHBdgN3BjVcq+eTQ3zhjMFUE1Kmn8gPupqwrQdZavSAkzsvuFl9XD2rvaoJxc/WGpsBd9zfkGLt2MrrvKzaGhBs2uOoZoT1/TTrWdv4F3FrEYO6+F49n0tKFX6OHR711H/0AmqLE1pNh37rqDIV9y4QUCpa/dg51KbCcDhtq9mKvRmoVLUYkRNPGgcWK1CTGT3uQ5IZwQSR2Ia5kr+5cYXTlNnRMk+P8ecUET4fpmqrNd8fFQGldFWTr5xJTDn80yfMi1CbvsWHmk5JxbxOzJga1AQeWspzPgz1rPwOMoYOArS6i4WxsHCOeuUQtF1gViAABiCM/D7 cardno:000603634564
EOE
chmod 0600 /mnt/sysimage/root/.ssh/authorized_keys

# http://www.contrib.andrew.cmu.edu/~somlo/OSXKVM
curl https://copr.fedorainfracloud.org/coprs/arrjay/applesmc-osk/repo/fedora-$fver/arrjay-applesmc-osk-fedora-$fver.repo -o /mnt/sysimage/etc/yum.repos.d/applesmc-osk.repo
chroot /mnt/sysimage yum -y install applesmc-osk

# https://fedoraproject.org/wiki/Using_UEFI_with_QEMU
curl https://www.kraxel.org/repos/firmware.repo -o /mnt/sysimage/etc/yum.repos.d/firmware.repo
chroot /mnt/sysimage yum -y install edk2.git-ovmf-x64
printf 'nvram = [\n\t"/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd:/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd",\n]\n' >> /mnt/sysimage/etc/libvirt/qemu.conf

# force /boot and /boot/efi to be synced before restart
bootdev=$(basename $(df --output=source /mnt/sysimage/boot/|tail -n1))
efidev=$(basename $(df --output=source /mnt/sysimage/boot/efi/|tail -n1))
while true ; do
  # walk all md devices and stop them unless it's the one we want
  for md in /sys/block/md* ; do
    dev=$(basename $md)
    case ${dev} in
      ${bootdev}|${efidev})
        # nop
        ;;
      *)
        echo "idle" > $md/md/sync_action
        ;;
    esac
  done
  # if *both* filesystems are quiet you may exit.
  fscounter=2
  for md in /sys/block/md* ; do
    dev=$(basename $md)
    case ${dev} in
      ${bootdev}|${efidev})
        read syncstat < $md/md/sync_completed
        if [ $syncstat == "none" ] ; then
          (( fscounter-- ))
        fi
        ;;
    esac
  done
  if [ $fscounter -eq 0 ] ; then
    break
  fi
  sleep 30
done

%end


# now, we upgrade to f23 after this, because the f23 install kernel
# has issues with SW RAID on this machine (cpu soft locks)
# dnf update --refresh
# dnf system-upgrade download --releasever=23
# dnf system-upgrade reboot

# system auth config
auth --enableshadow --passalgo=sha512

# root password
rootpw --iscrypted $6$ddmoPYtWupIPA/Vn$9EcJ170zv2lnVP6mLK0W9zAWaf7OYmu3yHk9dY0/pl5dPluvkTp/wTLmT4C7BAIE4FAGxPQ0K0zPwftvdvl5/0

# license
eula --agreed

# configure installurl, repos
%include /tmp/repo-include

# use text mode install
text

# keyboard layout, language
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8

# do not configure X
skipx

# reboot when done
reboot

# run the setup agent on first boot
firstboot --enable

# network configuration
network  --bootproto=dhcp --device=eth0 --ipv6=auto --activate
network  --hostname=holmium.burningfire.us

# system services
services --enabled="lldpad,chronyd"

# timezone
timezone America/Los_Angeles --isUtc

# partitioning is calulated in %pre
%include /tmp/part-include

%packages
@^minimal-environment
@core
chrony
kexec-tools
grub2
grub2-efi
grub2-efi-modules
shim
efibootmgr

augeas
avahi
dmidecode
dstat
grub2-efi-modules
htop
libguestfs-tools
libvirt
lldpad
lsscsi
nut
pciutils
policycoreutils-python
qemu-kvm
screen
smartmontools
usbutils
virt-install
xauth

%end

%addon com_redhat_kdump --enable

%end

%anaconda
pwpolicy root --minlen=6 --minquality=50 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=50 --notstrict --nochanges --notempty
pwpolicy luks --minlen=6 --minquality=50 --notstrict --nochanges --notempty
%end

%pre
read cmdline < /proc/cmdline
for ent in $cmdline ; do
  case $ent in
    mirroruri=*)
      mirroruri=${ent#mirroruri=}
      ;;
    instdev=*)
      disk=${ent#instdev=}
      ;;
  esac
done

{
  printf 'url --url="%s/fedora/releases/25/Server/x86_64/os"\n' "${mirroruri}"
  printf 'repo --name=updates --baseurl="%s/fedora/updates/25/x86_64"\n' "${mirroruri}"
  printf 'repo --name=everything --baseurl="%s/fedora/releases/25/Everything/x86_64/os"\n' "${mirroruri}"
} > /tmp/repo-include

wipefs -a /dev/${disk}
#parted /dev/${disk} mklabel gpt
#parted /dev/${disk} mkpart primary 1m 5m
#parted /dev/${disk} mkpart '"EFI System Partition"' 5m 300m
#parted /dev/${disk} mkpart primary 300m 800m
#parted /dev/${disk} mkpart primary 800m 100%
#parted /dev/${disk} set 2 boot on

#mkfs.vfat -F32 /dev/${disk}2

{
  printf 'bootloader --location=mbr --boot-drive=%s --append="quiet pci-stub.ids=1002:6738,1002:aa88,1033:0194,1b4b:9230,1912:0014"\n' "${disk}"
  printf 'clearpart --none --initlabel\n'
  printf 'part biosboot --fstype="biosboot" --ondisk=%s\n' "${disk}"
  printf 'part /boot/efi --fstype="efi" --ondisk=%s --size=200 --fsoptions="umask=0077,shortname=winnt"\n' "${disk}"
  printf 'part pv.721 --fstype="lvmpv" --ondisk=%s --size=32768 --grow --encrypted --passphrase=weaksauce\n' "${disk}"
  printf 'part /boot --fstype="ext4" --ondisk=%s --size=1024\n' "${disk}"
  printf 'volgroup fedora_holmium --pesize=4096 pv.721\n'
  printf 'logvol swap  --fstype="swap" --size=2048 --name=swap --vgname=fedora_holmium\n'
  printf 'logvol /var/lib/libvirt  --fstype="ext4" --size=9216 --name=var_lib_libvirt --vgname=fedora_holmium\n'
  printf 'logvol /  --fstype="ext4" --size=18432 --name=root --vgname=fedora_holmium\n'
} > /tmp/part-include

printf 'export disk="%s"\nexport mirroruri="%s"\n' "${disk}" "${mirroruri}" > /tmp/post-vars

%end

%post --nochroot --log=/mnt/sysimage/root/post.log
. /tmp/post-vars

if [ -d /sys/firmware/efi/efivars ] ; then
  # install i386 grub in efi
  chroot /mnt/sysimage grub2-install --target=i386-pc /dev/${disk}
  chroot /mnt/sysimage grub2-mkconfig | sed 's@linuxefi@linux16@g' | sed 's@initrdefi@initrd16@g' > /mnt/sysimage/boot/grub2/grub.cfg
else
  # install efi grub in i386
  chroot /mnt/sysimage grub2-mkconfig | sed 's@linux16@linuxefi@g' | sed 's@initrd16@initrdefi@g' > /mnt/sysimage/boot/efi/EFI/centos/grub.cfg
fi

# either way, set the disk flags correctly.
#parted /dev/${disk} disk_set pmbr_boot off
#parted /dev/${disk} set 1 boot on

chroot /mnt/sysimage rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-25-fedora

printf '[fedora]\nbaseurl=%s/fedora/releases/$releasever/Everything/$basearch/os\ngpgcheck=1\n' "${mirroruri}" > /mnt/sysimage/etc/yum.repos.d/fedora.repo
printf '[updates]\nbaseurl=%s/fedora/updates/$releasever/$basearch/\ngpgcheck=1\n' "${mirroruri}" >> /mnt/sysimage/etc/yum.repos.d/fedora-updates.repo

# NOTE: this runs outside the chroot against the 'live' nm, then saves over files

# rearrange usb nic
nmcli con add type bridge ifname uplink
nmcli con modify bridge-uplink bridge.stp no
nmcli con del enp6s0u1
nmcli con add type bridge-slave ifname enp6s0u1 master bridge-uplink

# k/v for vlan[nr]=bridge. we don't use vlans less than 3.
vlan[4]=netmgmt
vlan[5]=standard
vlan[7]=guest
vlan[66]=transit
vlan[70]=restricted
# vlan[100]=virthost - manually defined as we give IPs here
vlan[303]=dmz
vlan[606]=chaos
vlan[999]=iot
vlan[2000]=pln
vlan[2002]=wext

# create our vm bridges
for br in "${vlan[@]}" ; do
  nmcli con add type bridge ifname "${br}"
  nmcli con modify bridge-"${br}" bridge.stp no ipv4.method disabled ipv6.method ignore
  sed -i -e '/BOOTPROTO.*/d' /etc/sysconfig/network-scripts/ifcfg-bridge-"${br}"
  echo 'BOOTPROTO=none' >> /etc/sysconfig/network-scripts/ifcfg-bridge-"${br}"
  nmcli con reload
  nmcli con down bridge-"${br}"
  nmcli con up bridge-"${br}"
done

# create the virthosts bridge (which we bind an IP to)

# rearrange onboard nic
nmcli con modify enp7s0 ipv4.method disabled ipv6.method ignore
sed -i -e 's/BOOTPROTO.*//g' /etc/sysconfig/network-scripts/ifcfg-enp7s0
echo 'BOOTPROTO=none' >> /etc/sysconfig/network-scripts/ifcfg-enp7s0
nmcli con reload
nmcli con down enp7s0
nmcli con up enp7s0

# create vlans and glue to bridges - note connection.master is an ifname here
for v in "${!vlan[@]}" ; do
  nmcli con add type vlan con-name vlan-"${vlan[$v]}" dev enp7s0 id "${v}"
  nmcli con modify vlan-"${vlan[$v]}" ipv4.method disabled ipv6.method ignore connection.slave-type bridge connection.master "${vlan[$v]}"
  sed -i -e 's/BOOTPROTO.*//g' /etc/sysconfig/network-scripts/ifcfg-vlan-"${vlan[$v]}"
  echo 'BOOTPROTO=none' >> /etc/sysconfig/network-scripts/ifcfg-vlan-"${vlan[$v]}"
  nmcli con reload
  nmcli con down vlan-"${vlan[$v]}"
  nmcli con up vlan-"${vlan[$v]}"
done

rm -rf /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-*
cp -p /etc/sysconfig/network-scripts/ifcfg-* /mnt/sysimage/etc/sysconfig/network-scripts/

%end

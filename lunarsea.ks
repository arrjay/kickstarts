#version=RHEL7
# System authorization information
auth --enableshadow --passalgo=sha512

# Use network installation
url --url="http://mirrors.kernel.org/centos/7/os/x86_64"
# Use text mode
text
# Dont' run the Setup Agent on first boot
firstboot --disable
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang en_US.UTF-8

# reboot when done
reboot

# partitioning fun - note that the installer stops and asks for a password
ignoredisk --only-use=sda,sdb,sdc,sdd
clearpart --all --initlabel --drives=sda,sdb,sdc,sdd
# sda - 256GB SSD
part raid.4221 --fstype="mdmember" --ondisk=sda --size=512
part raid.5408 --fstype="mdmember" --ondisk=sda --size=24368 --grow
# sdb - 512GB HDD
part raid.5500 --fstype="mdmember" --ondisk=sdb --size=24368 --grow
# sdc - 256GB SSD
part raid.4227 --fstype="mdmember" --ondisk=sdc --size=512
part raid.5414 --fstype="mdmember" --ondisk=sdc --size=24368 --grow
# sdd - 512GB HDD
part raid.5501 --fstype="mdmember" --ondisk=sdd --size=24368 --grow

# raid volume, /boot
raid /boot --device=boot --fstype="ext4" --level=RAID1 raid.4221 raid.4227
# raid volume for ssds
raid pv.4581 --device=pv00 --fstype="lvmpv" --level=RAID1 --encrypted raid.5408 raid.5414 --passphrase="initialsetup"
# raid volume for mags
raid pv.5502 --device=pv01 --fstype="lvmpv" --level=RAID1 --encrypted raid.5500 raid.5501 --passphrase="initialsetup"

# volume groups
volgroup lunarsea --pesize=4096 pv.4581 pv.5502
# volgroup mags --pesize=4096 pv.5502

# LV filesystems
logvol /  --fstype="ext4" --size=36834 --name=root --vgname=lunarsea
logvol swap  --fstype="swap" --size=8192 --name=swap --vgname=lunarsea

logvol /var/lib/libvirt  --fstype="xfs" --size=512 --name=var_lib_libvirt --vgname=lunarsea

# Network information - enp6s0?
network  --bootproto=dhcp --device=br0 --bridgeslaves=eth0  --ipv6=auto --activate --hostname=lunarsea

# Root password
rootpw --iscrypted $6$y9fGm7f8OX3zLVu/$HFmxAs2UgWpv89snjVJt.RewW0a2DMYknbJUJD85TmepIaJ1JLuetOQDEJxT7R.2KN5vq9wg4gxIX.JzTjRPE.

# System timezone
timezone America/New_York --isUtc

# System bootloader configuration
# pci-stub notes
# 8086:3a37 - USB1 controller
# 8086:3a38 - USB1 controller
# 8086:3a39 - USB1 controller
# 8086:3a3c - USB2 controller

# 8086:3a3e - audio controller

# 8086:3a34 - USB1 controller
# 8086:3a35 - USB1 controller
# 8086:3a36 - USB1 controller
# 8086:3a3a - USB2 controller

# 1106:3432 - USB3 controller
# 1033:0194 - USB3 controller
# 1002:6749 - video card
# 1002:aa90 - video hdmi audio
bootloader --append="pci-stub.ids=8086:3a37,8086:3a38,8086:3a39,8086:3a3c,8086:3a34,8086:3a35,8086:3a36,8086:3a3a,8086:3a3e,1106:3432,1033:0194,1002:6749,1002:aa90 crashkernel=auto intel_iommu=on quiet" --location=mbr --boot-drive=sda

# System services
services --enabled="chronyd"

%packages
@core
chrony
kexec-tools
openscap
openscap-scanner
scap-security-guide

avahi

screen
dstat
smartmontools

lsscsi
pciutils
usbutils
dmidecode

libvirt
qemu-kvm
virt-install

%end

%addon org_fedora_oscap
    content-type = scap-security-guide
    profile = common
%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%post
# hook in EPEL
yum -y install epel-release

# strip out rhgb
sed -i -e 's/rhgb//' $(readlink -f /etc/grub2.cfg)

# bridge configuration
nmcli con modify "Bridge connection br0" bridge.stp no
nmcli con modify "Bridge connection br0" bridge.forward-delay 2
nmcli con delete enp6s0

# storage spindle layout
# move root, swap to ssds
# move libvirt to magnetics
# this works via a nasty hack - we assume the magnetics are the larger pv!
mags_pv=$(pvs --noheadings --units m -o pv_name,dev_size| awk '{print $2,$1 }'|sort -n|tail -n1|awk '{print $2}')
ssds_pv=$(pvs --noheadings --units m -o pv_name,dev_size| awk '{print $2,$1 }'|sort -n|head -n1|awk '{print $2}')
# tag ssds as cache
pvchange --addtag cache ${ssds_pv}
# tag magnetics
pvchange --addtag mags ${mags_pv}

# pvmove moves a given lv *off* the specified storage
# root/swap on the ssds
pvmove -n root @mags
pvmove -n swap @mags
# libvirt to the magnetics
pvmove -n var_lib_libvirt @cache

# resize libvirt while we're here...
lvresize -r -L9G /dev/lunarsea/var_lib_libvirt @mags
# create a cache 20% (.2) the main fs size, then attach it.
lvcreate --type cache-pool -L$(lvs lunarsea/var_lib_libvirt -o lv_size --units m --noheadings|awk -F. '{ print $1 * .2 }')m -n cache_var_lib_libvirt --cachemode writeback --cachepolicy smq lunarsea @cache
# and attach it
lvconvert --type cache --cachepool lunarsea/cache_var_lib_libvirt lunarsea/var_lib_libvirt

# https://fedoraproject.org/wiki/Using_UEFI_with_QEMU
curl https://www.kraxel.org/repos/firmware.repo -o /etc/yum.repos.d/firmware.repo
yum -y install edk2.git-ovmf-x64
printf 'nvram = [\n\t"/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd:/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd",\n]\n' >> /etc/libvirt/qemu.conf

# and finally, a hardware bug(?). go be unsafe.
echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" > /etc/modprobe.d/vfio_iommu_type1.conf
%end

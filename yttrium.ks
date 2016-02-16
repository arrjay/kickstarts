#version=RHEL7
# System authorization information
auth --enableshadow --passalgo=sha512

# Use network installation
url --url="http://mirrors.kernel.org/centos/7/os/x86_64"

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
network  --bootproto=dhcp --device=enp10s0 --onboot=off --ipv6=auto
network  --bootproto=dhcp --device=br0 --bridgeslaves=enp9s0 --ipv6=auto --activate
network  --hostname=yttrium.produxi.net

# Root password
rootpw --iscrypted $6$m95xGSDD7uy.OlhR$1fkOb4IJhARxPZtuc7Mx85tHBY0nf9eEmEE7Zw4Xweh1M4n5kUZ/Ny7xPACUHHfbKNz3dFoxbOurCWpD89YPs.
# System timezone
timezone America/New_York --isUtc
# System bootloader configuration
bootloader --append=" crashkernel=auto" --location=mbr --boot-drive=sda
ignoredisk --only-use=sda,sdb,sdc,sdd
# Partition clearing information
clearpart --all --initlabel --drives=sda,sdb,sdc,sdd
# Disk partitioning information
# RAID1 for /boot
part raid.734 --fstype="mdmember" --ondisk=sda --size=501
part raid.740 --fstype="mdmember" --ondisk=sdb --size=501
part raid.746 --fstype="mdmember" --ondisk=sdc --size=501
part raid.752 --fstype="mdmember" --ondisk=sdd --size=501

# RAID1 for /boot/efi
part raid.962 --fstype="mdmember" --ondisk=sda --size=201
part raid.968 --fstype="mdmember" --ondisk=sdb --size=201
part raid.974 --fstype="mdmember" --ondisk=sdc --size=201
part raid.980 --fstype="mdmember" --ondisk=sdd --size=201

# RAID10 for LVM
part raid.1224 --fstype="mdmember" --ondisk=sda --size=38669 --grow
part raid.1230 --fstype="mdmember" --ondisk=sdb --size=38669 --grow
part raid.1236 --fstype="mdmember" --ondisk=sdc --size=38669 --grow
part raid.1242 --fstype="mdmember" --ondisk=sdd --size=38669 --grow

# okay, assemble the RAID-y bits
raid /boot --device=boot --fstype="ext4" --level=RAID1 raid.734 raid.740 raid.746 raid.752
raid /boot/efi --device=boot_efi --fstype="efi" --level=RAID1 --fsoptions="umask=0077,shortname=winnt" raid.962 raid.968 raid.974 raid.980
raid pv.1248 --device=pv00 --fstype="lvmpv" --level=RAID10 raid.1224 raid.1230 raid.1236 raid.1242

# LVM atop RAID10
volgroup yttrium --pesize=4096 pv.1248
logvol / --fstype="ext4" --grow --maxsize=36834 --size=1024 --name=root --vgname=yttrium
logvol swap --fstype="swap" --size=8192 --name=swap --vgname=yttrium
logvol /var/lib/libvirt  --fstype="xfs" --size=18432 --name=var_lib_libvirt --vgname=yttrium

# System services
services --enabled="chronyd"

%packages
@^minimal
@core
kexec-tools
openscap
openscap-scanner
scap-security-guide
chrony

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
# strip out rhgb
sed -i -e 's/rhgb//' $(readlink -f /etc/grub2.cfg)

# bridge configuration
nmcli con modify "Bridge connection br0" bridge.stp no
nmcli con modify "Bridge connection br0" bridge.forward-delay 2
nmcli con delete enp6s0

# https://fedoraproject.org/wiki/Using_UEFI_with_QEMU
curl https://www.kraxel.org/repos/firmware.repo -o /etc/yum.repos.d/firmware.repo
yum -y install edk2.git-ovmf-x64
printf 'nvram = [\n\t"/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd:/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd",\n]\n' >> /etc/libvirt/qemu.conf

# force /boot and /boot/efi to be synced before restart
bootdev=$(basename $(df --output=source /boot/|tail -n1))
efidev=$(basename $(df --output=source /boot/efi/|tail -n1))
while true ; do
  # walk all md devices and stop them unless it's the one we want
  for md in /sys/block/md* ; do
    dev=$(basename $md)
    case ${dev} in
      ${bootdev}|${efidev})
        # nop
        ;;
      *)
        echo "idle" $x/md/sync_action
        ;;
    esac
  done
  # if *both* filesystems are quiet you may exit.
  fscounter=2
  for md in /sys/block/md* ; do
    dev=$(basename $md)
    case ${dev} in
      ${bootdev}|${efidev})
        read syncstat < $x/md/sync_completed
        if [ $syncstat == "none" ] ; then
          $((fscounter--)
        fi
        ;;
    esac
  done
  if [ $fscounter -eq 0 ] ; then
    break
  fi
done

%end

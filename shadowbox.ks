# NOTE: F11 is the BIOS/UEFI Boot Service selection menu.
#       The BIOS is terrible at telling you this.
#version=DEVEL
# System authorization information
auth --enableshadow --passalgo=sha512

# leave this unset for closest-mirror setup
# Use network installation
url --url="http://mirrors.kernel.org/fedora/releases/23/Server/x86_64/os"
repo --name=everything --baseurl="http://mirrors.kernel.org/fedora/releases/23/Everything/x86_64/os"
repo --name=updates --baseurl="http://mirrors.kernel.org/fedora/updates/23/x86_64"

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
network  --bootproto=dhcp --device=br0 --bridgeslaves=enp7s0 --ipv6=auto --activate --bridgeopts=ageing-time=15,stp=no --hostname=shadowbox.burningfire.us

# Root password
rootpw --iscrypted $6$m95xGSDD7uy.OlhR$1fkOb4IJhARxPZtuc7Mx85tHBY0nf9eEmEE7Zw4Xweh1M4n5kUZ/Ny7xPACUHHfbKNz3dFoxbOurCWpD89YPs.
# System timezone
timezone America/New_York --isUtc

# System bootloader configuration - blacklist the second ahci card and usb controller here.
bootloader --location=mbr --boot-drive=sda --append="pci-stub.ids=1b73:1100,1b4b:9230"
# Partition clearing information
clearpart --all --initlabel --drives=sda
# Disk partitioning information
part /boot --fstype="ext4" --ondisk=sda --size=500
part /boot/efi --fstype="efi" --ondisk=sda --size=200 --fsoptions="umask=0077,shortname=winnt"
part pv.303 --fstype="lvmpv" --ondisk=sda --size=75618
volgroup fedora_shadowbox --pesize=4096 pv.303
logvol swap  --fstype="swap" --size=8192 --name=swap --vgname=fedora_shadowbox
logvol /  --fstype="xfs" --size=18432 --name=root --vgname=fedora_shadowbox

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

lsscsi
pciutils
usbutils
dmidecode

libvirt
qemu-kvm
virt-install
kernel-devel

xauth

nut

augeas

dnf-plugin-system-upgrade

bluez

%end

%addon com_redhat_kdump --disable --reserve-mb='128'

%end

%anaconda
pwpolicy root --minlen=0 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy user --minlen=0 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=0 --minquality=1 --notstrict --nochanges --emptyok
%end

%post
# vfio-pci notes
# Group 2 (PCI Bridge 00:02.0)
# 01:00.0 - 1002:6749 (AMD Barts XT)
# 01:00.1 - 1002:aa90 (AMD Barts HDMI Audio)
# Group 3 (PCI Bridge 00:03.0)
# 02:00.0 - 1b73:1100 (Fresco Logic FL1100 USB 3.0 Host Controller)
# Group 4 (PCI Bridge 00:04.0)
# 03:00.0 - 1b4b:9230 (Marvell Technology Group SATA 6GB/s Controller)
echo "softdep vfio-pci post: vfio_iommu_type1" > /etc/modprobe.d/vfio-pci.conf
echo "options vfio-pci ids=1002:6738,1002:aa88,1b73:1100,1b4b:9230" >> /etc/modprobe.d/vfio-pci.conf
echo "softdep radeon pre: vfio-pci" >> /etc/modprobe.d/vfio-pci.conf
echo "softdep snd_hda_intel pre: vfio-pci" >> /etc/modprobe.d/vfio-pci.conf
printf 'install vfio-pci /sbin/modprobe --ignore-install vfio-pci ; /bin/bash -c '\''read c < /proc/cmdline;for a in $c;do case $a in pci-stub.ids=*)i="${a//pci-stub.ids=}";;esac;done;for p in /sys/bus/pci/devices/*;do read v < $p/vendor;v="${v//0x}";read d < $p/device;d="${d//0x}";case $i in *${v}:${d}*)n=${p:21};echo $n > ${p}/driver/unbind;echo $n > /sys/bus/pci/drivers/vfio-pci/bind;;esac;done'\''\n' >> /etc/modprobe.d/vfio-pci.conf
printf 'add_drivers+="vfio-pci "\n' >> /etc/dracut.conf
printf 'cgroup_device_acl = [ "/dev/null", "/dev/full", "/dev/zero", "/dev/random", "/dev/urandom", "/dev/ptmx", "/dev/kvm", "/dev/kqemu", "/dev/rtc","/dev/hpet", "/dev/vfio/vfio", "/dev/vfio/22", "/dev/vfio/14" ]\n' >> /etc/libvirt/qemu.conf

# mangle the grub config...
printf 'GRUB_DISABLE_OS_PROBER="true"\n' >> /etc/default/grub
sed -i -e 's/rhgb//' $(readlink -f /etc/default/grub)
grub2-mkconfig > /etc/grub2-efi.cfg
for kver in $(rpm -q kernel --qf '%{version}-%{release}.%{arch}\n') ; do
  depmod -a ${kver}
  dracut -f --kver ${kver}
done

# disable passwords for ssh
augtool set /files/etc/ssh/sshd_config/PermitRootLogin without-password
mkdir /root/.ssh
# and install a pubkey
cat << EOE > /root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDTRxypN4BeG6XdQPlr72SnNM18MHpM1rXqQNo3GwxVTZA7LXXCmTstWUPctUrk92uRkAOP335OoKN+njX4De022V+jlpPG9rHuDT93KOBTK8vmWwAOSBlvAe/5ebmhKoxuPEMe2M2FximeE99Uqk3uVLSJHDVjM1Q3g0onPx9HW3vzptP+7N9E9WzsaKrhE5Ns0NMgqLEdMiFj2x3OuDySoCS84nCQFC9Q966Ov8CBugX6/4R2yytNzjJ2UJ+mwvesEPZSH7kzQrTVPklyKhdG/i1OeMN0z38/QmGkLiJd174/yUy9TQBQ4NQSdSAffKNe0UZXpLTXUxPuGkcR4vH69wamWyQZMgRUvmVD/UygHMJQfxXMs03Xo4M6FdC7ejFVUxs7wHptSweKdDvI6OIPKHgZcrNuPXjIohXrCUPrx/tHPvZjmBz3gH4eb2z0zoTrGwHTIMXb8ahStRCfTBnbJvfEn+vn3sXHlb6IBtyMJY9kQ8E0YNsLkIVky+aXk/wXWFHKi6yCG62pCCX0+kCzDyTFzd2AS/jom+3NzL1eAhK7chQuaxdAPqJIH8gEfud9tLzZ85lJ0ZkChoAyNitVYkAKRR1ueAKXzPOg2Gt2LOtht2Tqr+MNBXlepfkE+TaltlygtpKLtsDo17TfuMhdfWJgLd6S705G91FOh3893Q== cardno:000500003E35
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3OueMyB4NBGlHBdgN3BjVcq+eTQ3zhjMFUE1Kmn8gPupqwrQdZavSAkzsvuFl9XD2rvaoJxc/WGpsBd9zfkGLt2MrrvKzaGhBs2uOoZoT1/TTrWdv4F3FrEYO6+F49n0tKFX6OHR711H/0AmqLE1pNh37rqDIV9y4QUCpa/dg51KbCcDhtq9mKvRmoVLUYkRNPGgcWK1CTGT3uQ5IZwQSR2Ia5kr+5cYXTlNnRMk+P8ecUET4fpmqrNd8fFQGldFWTr5xJTDn80yfMi1CbvsWHmk5JxbxOzJga1AQeWspzPgz1rPwOMoYOArS6i4WxsHCOeuUQtF1gViAABiCM/D7 cardno:000603634564
EOE
chmod 0600 /root/.ssh/authorized_keys

# https://fedoraproject.org/wiki/Using_UEFI_with_QEMU
curl https://www.kraxel.org/repos/firmware.repo -o /etc/yum.repos.d/firmware.repo
yum -y install edk2.git-ovmf-x64
printf 'nvram = [\n\t"/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd:/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd",\n]\n' >> /etc/libvirt/qemu.conf

%end

# http://stackoverflow.com/questions/589252/how-can-i-automatically-create-and-remove-a-temp-directory-in-a-makefile

ifeq ($(tmpdir),)

location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%:
	@tmpdir=`mktemp --tmpdir -d` ; trap 'rm -rf "$$tmpdir"' EXIT ; \
	$(MAKE) -f $(self) --no-print-directory tmpdir=$$tmpdir $@

else

# bootstrap images

# add 2MB slack space to our images
OVERHEAD = 2048

# mtools programs, env
MMD = env MTOOLS_SKIP_CHECK=1 mmd -i $(DEVICE)
MCOPY = env MTOOLS_SKIP_CHECK=1 mcopy -i $(DEVICE)

# mkfs programs
FAT=32
FSLABEL=KICKSTART
MKFS = mkdosfs -F$(FAT) -n '$(FSLABEL)' $(DEVICE)

# parted
PARTED = parted

# dd (for stapling in syslinux)
DD = dd conv=notrunc bs=440 count=1 if=/usr/share/syslinux/mbr.bin of=$(DEVICE)

# syslinux
SYSLINUX = syslinux $(DEVICE)

# override MMD and MCOPY if this is a real device
RDSK =
# this 1) gets replaced by DEVICE when called directly, 2) gets replaced if a real disk
IDEVICE = $(DEVICE)@@1M
# FIIK why patsubst doesn't work here.
GFISH_DEV = $(shell echo $(DEVICE)|sed 's/@@.*//g')
ISYSLINUX = syslinux $(GFISH_DEV) --offset=1048576
ifneq ("$(wildcard $(DEVICE))","")
ifneq ("$(shell stat --printf %t $(DEVICE))","0")
RDSK := @
MMD := sudo $(MMD)
MCOPY := sudo $(MCOPY)
MKFS := sudo $(MKFS)
PARTED := sudo $(PARTED)
IDEVICE = $(DEVICE)1
SYSLINUX := sudo $(SYSLINUX)
DD := sudo $(DD)
endif
endif

# image size calculation - this requires OS var
SZ = $(shell du -ks --total images/efikit images/$(OS)|tail -n1|cut - -f1)
IZ = $(shell echo $$(( $(SZ) + $(OVERHEAD) )))
# disk size calculation if we make a disk - add 1M to it for offsets
DZ = $(shell echo $$(( $(IZ) + 1024 )))
# disk size calculation for just-EFI image
EZ = $(shell echo $$(( $$(du -ks --total images/efikit|tail -n1|cut - -f1) + $(OVERHEAD) )))

# just report image sizes - requires OS
sizing: images/efikit/.all images/$(OS)/.all
	@printf files:\\t%s\\nimage:\\t%s\\ndisk:\\t%s\\nefi:\\t%s\\n $(SZ) $(IZ) $(DZ) $(EZ)

# subdir expansion rule
%.all: %/Makefile
	$(MAKE) -C $(@D) all

# create a fat32 filesystem - requires DEVICE
mkfs: Makefile
ifeq ("$(findstring @,$(DEVICE)$(RDSK))","")
	$(MKFS)
else
	# we were handed a file + offset - try having guestfish format it.
	guestfish -a $(GFISH_DEV) run : mkfs vfat /dev/sda1
endif

# copy the efikit to a pre-formatted image - requires DEVICE
efikit: images/efikit/.all grub.cfg
	$(MMD) EFI
	$(MMD) EFI/BOOT
	$(MCOPY) images/efikit/grubx64.efi ::EFI/BOOT
	$(MCOPY) images/efikit/MokManager.efi ::EFI/BOOT
	$(MCOPY) images/efikit/BOOTX64.EFI ::EFI/BOOT
	$(MMD) EFI/BOOT/fonts
	$(MCOPY) images/efikit/unicode.pf2 ::EFI/BOOT/fonts
	# grub (EFI) config
	$(MCOPY) grub.cfg ::EFI/BOOT

# make a disk (partition) image - requires DEVICE, OS vars
image: images/$(OS)/.all syslinux.cfg
ifeq ("$(findstring @,$(DEVICE)$(RDSK))","")
	# raw image file case
	$(MAKE) sparsefile SIZE=$(IZ)
	$(MAKE) mkfs DEVICE=$(DEVICE)
	$(SYSLINUX)
else
	$(MAKE) mkfs DEVICE=$(DEVICE)
ifneq ("$(findstring @,$(RDSK))","")
	# oh. a real disk device.
	$(SYSLINUX)
else
	$(ISYSLINUX)
endif
endif
	# we have a device or an offset at this point, hopefully with an FS
	$(MAKE) efikit DEVICE=$(DEVICE)

	# copy OS pieces
	$(MMD) images
	$(MMD) images/pxeboot
	$(MCOPY) images/$(OS)/vmlinuz ::images/pxeboot
	$(MCOPY) images/$(OS)/initrd.img ::images/pxeboot
	$(MCOPY) images/$(OS)/stage2.img ::

	# syslinux (MBR) config
	$(MCOPY) syslinux.cfg ::

# make a disk image and install mbr - requires DEVICE, OS vars
# don't directly rely on image target because we reset device
disk: Makefile images/efikit/.all images/$(OS)/.all
ifeq ("$(findstring @,$(RDSK))","")
	# fake disks get sparsed out
	$(MAKE) sparsefile SIZE=$(DZ)
endif
	# partition whatever we got here
	$(PARTED) -s $(DEVICE) mklabel msdos
	$(PARTED) -s $(DEVICE) mkpart primary fat32 1M 100%
	$(PARTED) -s $(DEVICE) set 1 boot on

	# install bootloader in mbr
	$(DD)

	# stuff the image contents in whatever that was
	$(MAKE) image DEVICE=$(IDEVICE)

sparsefile: Makefile
	# remove and recreate a sparse file of computed size
	-rm $(DEVICE)
	truncate -s $(SIZE)k $(DEVICE)

# make an iso! use the tmpdir now. - requires DEVICE, OS vars
iso: Makefile $(tmpdir) images/efikit/.all grub.cfg
	mkdir -p $(tmpdir)/images/pxeboot
	$(MAKE) sparsefile SIZE=$(EZ) DEVICE=$(tmpdir)/images/efiboot.img
	$(MAKE) mkfs DEVICE=$(tmpdir)/images/efiboot.img FAT=12 FSLABEL=BOOTSTRAP
	$(MAKE) efikit DEVICE=$(tmpdir)/images/efiboot.img
	# copy efikit *again* to tmpdir
	mkdir -p $(tmpdir)/EFI/BOOT/fonts
	cp images/efikit/unicode.pf2 $(tmpdir)/EFI/BOOT/fonts/
	cp images/efikit/BOOTX64.EFI $(tmpdir)/EFI/BOOT/
	cp images/efikit/MokManager.efi $(tmpdir)/EFI/BOOT/
	cp images/efikit/grubx64.efi $(tmpdir)/EFI/BOOT/
	cp grub.cfg $(tmpdir)/EFI/BOOT
	cp images/$(OS)/vmlinuz $(tmpdir)/images/pxeboot/
	cp images/$(OS)/initrd.img $(tmpdir)/images/pxeboot/
	cp images/$(OS)/stage2.img $(tmpdir)/
	mkdir -p $(tmpdir)/isolinux
	cd $(tmpdir)/isolinux ; ln ../images/pxeboot/initrd.img
	cd $(tmpdir)/isolinux ; ln ../images/pxeboot/vmlinuz
	cp /usr/share/syslinux/isolinux.bin $(tmpdir)/isolinux
	cp syslinux.cfg $(tmpdir)/isolinux/isolinux.cfg
	mkisofs -o $(DEVICE) -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efiboot.img -no-emul-boot $(tmpdir)

endif	# tmpdir switch

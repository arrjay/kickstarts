# bootstrap images

# add 2MB slack space to our images
OVERHEAD = 2048

# mtools programs, env
MMD = env MTOOLS_SKIP_CHECK=1 mmd -i $(DEVICE)
MCOPY = env MTOOLS_SKIP_CHECK=1 mcopy -i $(DEVICE)

# mkfs programs
MKFS = mkdosfs -F32 -n 'KICKSTART' $(DEVICE)

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

# subdir expansion rule
%.all: %/Makefile
	$(MAKE) -C $(@D) all

# make a disk (partition) image - requires DEVICE, OS vars
image: images/efikit/.all images/$(OS)/.all syslinux.cfg
ifeq ("$(findstring @,$(DEVICE)$(RDSK))","")
	# raw image file case
	$(MAKE) sparsefile SIZE=$(IZ)
	$(MKFS)
	$(SYSLINUX)
else
ifneq ("$(findstring @,$(RDSK))","")
	# oh. a real disk device.
	$(MKFS)
	$(SYSLINUX)
else
	# we were handed a file + offset - try having guestfish format it.
	guestfish -a $(GFISH_DEV) run : mkfs vfat /dev/sda1
	$(ISYSLINUX)
endif
endif
	# we have a device or an offset at this point, hopefully with an FS

	# make EFI dirs and copy kit
	$(MMD) EFI
	$(MMD) EFI/BOOT
	$(MCOPY) images/efikit/grubx64.efi ::EFI/BOOT
	$(MCOPY) images/efikit/MokManager.efi ::EFI/BOOT
	$(MCOPY) images/efikit/BOOTX64.EFI ::EFI/BOOT
	$(MMD) EFI/BOOT/fonts
	$(MCOPY) images/efikit/unicode.pf2 ::EFI/BOOT/fonts

	# copy OS pieces
	$(MCOPY) images/$(OS)/vmlinuz ::
	$(MCOPY) images/$(OS)/initrd.img ::
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

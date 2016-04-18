source = http://mirrors.kernel.org/fedora/releases/23/Server/x86_64/os/EFI/BOOT

all: unicode.pf2 grubx64.efi MokManager.efi BOOTX64.EFI

unicode.pf2: Makefile
	curl -L -o unicode.pf2 $(source)/fonts/unicode.pf2

grubx64.efi: Makefile
	curl -L -o grubx64.efi $(source)/grubx64.efi

MokManager.efi: Makefile
	curl -L -o MokManager.efi $(source)/MokManager.efi

BOOTX64.EFI: Makefile
	curl -L -o BOOTX64.EFI $(source)/BOOTX64.EFI

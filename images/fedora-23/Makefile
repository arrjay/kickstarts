source = http://mirrors.kernel.org/fedora/releases/23/Server/x86_64/os/

all: vmlinuz initrd.img stage2.img

vmlinuz: Makefile
	curl -L -o vmlinuz $(source)/images/pxeboot/vmlinuz

initrd.img: Makefile
	curl -L -o initrd.img $(source)/images/pxeboot/initrd.img

stage2.img: Makefile
	curl -L -o stage2.img $(source)/images/install.img

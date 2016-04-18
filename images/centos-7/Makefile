source = http://mirrors.kernel.org/centos/7/os/x86_64

all: vmlinuz initrd.img stage2.img

vmlinuz: Makefile
	curl -L -o vmlinuz $(source)/images/pxeboot/vmlinuz

initrd.img: Makefile
	curl -L -o initrd.img $(source)/images/pxeboot/initrd.img

stage2.img: Makefile
	curl -L -o stage2.img $(source)/LiveOS/squashfs.img

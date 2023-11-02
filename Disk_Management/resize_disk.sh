#!/bin/bash

DEVICES=$(ls /sys/class/scsi_disk/)
for device in $DEVICES;do
	echo "1" > /sys/class/scsi_disk/$device/device/rescan
done

#DISK=$(fdisk -l 2>/dev/null |awk '/^Disk \//{print substr($2,0,length($2)-1)}' | grep -v "loop" | grep -v "/dev/mapper/ubuntu--vg-ubuntu--lv")
DISK=$(fdisk -l 2>/dev/null |awk '/^Disk \//{print substr($2,0,length($2)-1)}' | grep -vE "(loop|/dev/mapper/ubuntu--vg-ubuntu--lv)")
cfdisk

echo "Discos disponibles: "
ls $DISK[0-9]*

while true; do
	read -p "Que disco has ampliado (Ej: sda3): " disco
	if [ ! -b /dev/$disco ];then
		echo "La unidad de disco ${disco} no existe."
	else
		break
	fi
done

if [ -b /dev/ubuntu-vg/ubuntu-lv ];then

	#PV Volumen fisico
	pvresize /dev/$disco
	
	lvextend -l+100%FREE /dev/ubuntu-vg/ubuntu-lv
	resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
	lsblk $DISK && df -h $(mount | grep -E /dev/mapper/ubuntu--vg-ubuntu--lv | awk '{print $3}')
else
	resize2fs /dev/$disco
	lsblk $DISK && df -h $(mount | grep -E "/dev/$disco" | awk '{print $3}')
fi

#!/bin/bash

# Function to print error messages
error() {
    echo "ERROR: $1" >&2
}

# Function to print informational messages
info() {
    echo "INFO: $1"
}

# Rescan SCSI devices
info "Rescanning SCSI devices..."
for device in /sys/class/scsi_disk/*; do
    echo "1" > "$device/device/rescan"
done

# Get list of disks, excluding loop devices and LVM
DISKS=$(fdisk -l 2>/dev/null | awk '/^Disk \//{print substr($2, 1, length($2)-1)}' | grep -vE "(loop|/dev/mapper)")

# Run cfdisk for partitioning
cfdisk

# Display available disks
info "Available disks:"
ls ${DISKS}[0-9]* 2>/dev/null || error "No partitions found"

# Get the expanded disk from user input
while true; do
    read -p "Which disk have you expanded? (e.g., sda3): " disk
    if [ -b "/dev/$disk" ]; then
        break
    else
        error "Disk /dev/$disk does not exist."
    fi
done

# Check if using LVM
if [ -b /dev/ubuntu-vg/ubuntu-lv ]; then
    info "LVM detected. Resizing LVM volumes..."
    pvresize "/dev/$disk" || error "Failed to resize physical volume"
    lvextend -l+100%FREE /dev/ubuntu-vg/ubuntu-lv || error "Failed to extend logical volume"
    resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv || error "Failed to resize filesystem"
    
    mount_point=$(mount | grep -E /dev/mapper/ubuntu--vg-ubuntu--lv | awk '{print $3}')
else
    info "Standard partition detected. Resizing filesystem..."
    resize2fs "/dev/$disk" || error "Failed to resize filesystem"
    
    mount_point=$(mount | grep -E "/dev/$disk" | awk '{print $3}')
fi

# Display results
info "Final disk layout:"
lsblk ${DISKS}

if [ -n "$mount_point" ]; then
    info "Filesystem usage:"
    df -h "$mount_point"
else
    error "Mount point not found"
fi

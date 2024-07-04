#!/bin/bash

# Function to print error messages
error() {
    echo "ERROR: $1" >&2
    exit 1
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

# Find the disk to expand (assuming it's the last partition on the last disk)
DISK_TO_EXPAND=$(echo "$DISKS" | tail -n1)
PARTITION_TO_EXPAND=$(lsblk -nlo NAME,TYPE "$DISK_TO_EXPAND" | awk '$2=="part"{name=$1} END{print name}')

if [ -z "$PARTITION_TO_EXPAND" ]; then
    error "No partition found to expand"
fi

FULL_PARTITION_PATH="/dev/$PARTITION_TO_EXPAND"

info "Expanding partition $FULL_PARTITION_PATH"

# Use parted to resize the partition
parted "$DISK_TO_EXPAND" resizepart "${PARTITION_TO_EXPAND: -1}" 100% || error "Failed to resize partition"

# Check if using LVM
if [ -b /dev/ubuntu-vg/ubuntu-lv ]; then
    info "LVM detected. Resizing LVM volumes..."
    pvresize "$FULL_PARTITION_PATH" || error "Failed to resize physical volume"
    lvextend -l+100%FREE /dev/ubuntu-vg/ubuntu-lv || error "Failed to extend logical volume"
    resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv || error "Failed to resize filesystem"
    
    mount_point=$(mount | grep -E /dev/mapper/ubuntu--vg-ubuntu--lv | awk '{print $3}')
else
    info "Standard partition detected. Resizing filesystem..."
    resize2fs "$FULL_PARTITION_PATH" || error "Failed to resize filesystem"
    
    mount_point=$(mount | grep -E "$FULL_PARTITION_PATH" | awk '{print $3}')
fi

# Display results
info "Final disk layout:"
lsblk "$DISK_TO_EXPAND"

if [ -n "$mount_point" ]; then
    info "Filesystem usage:"
    df -h "$mount_point"
else
    error "Mount point not found"
fi

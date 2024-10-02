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

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root."
fi

# Check for required commands
REQUIRED_CMDS=("fdisk" "parted" "lsblk" "awk" "grep" "pvresize" "lvextend" "resize2fs" "findmnt" "blkid")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        error "Required command '$cmd' not found. Please install it before running this script."
    fi
done

# Rescan SCSI devices if any
if ls /sys/class/scsi_disk/* > /dev/null 2>&1; then
    info "Rescanning SCSI devices..."
    for device in /sys/class/scsi_disk/*; do
        echo "1" > "$device/device/rescan"
    done
fi

# Get list of disks, excluding loop devices and LVM
DISKS=$(fdisk -l 2>/dev/null | awk '/^Disk \//{print substr($2, 1, length($2)-1)}' | grep -vE "(loop|/dev/mapper)")

# Ask user to select the disk to expand
echo "Available disks:"
echo "$DISKS"
read -p "Enter the disk you want to expand (e.g., /dev/sda): " DISK_TO_EXPAND

if [ -z "$DISK_TO_EXPAND" ] || [ ! -b "$DISK_TO_EXPAND" ]; then
    error "Invalid disk selected."
fi

# Find the last partition on the disk
PARTITION_TO_EXPAND=$(lsblk -nlo NAME,TYPE "$DISK_TO_EXPAND" | awk '$2=="part"{print $1}' | tail -n1)

if [ -z "$PARTITION_TO_EXPAND" ]; then
    error "No partition found to expand on $DISK_TO_EXPAND."
fi

FULL_PARTITION_PATH="/dev/$PARTITION_TO_EXPAND"

info "Expanding partition $FULL_PARTITION_PATH"

# Extract the partition number
PART_NUM=$(echo "$PARTITION_TO_EXPAND" | sed 's/[^0-9]*//g')

# Use parted to resize the partition
parted "$DISK_TO_EXPAND" resizepart "$PART_NUM" 100% || error "Failed to resize partition"

# Wait for the kernel to recognize the partition change
partprobe "$DISK_TO_EXPAND"

# Detect filesystem type
FS_TYPE=$(blkid -s TYPE -o value "$FULL_PARTITION_PATH")

# Check if using LVM
if lsblk -ln "$FULL_PARTITION_PATH" | grep -q " lvm$"; then
    info "LVM detected. Resizing LVM volumes..."

    pvresize "$FULL_PARTITION_PATH" || error "Failed to resize physical volume"

    VG_NAME=$(vgdisplay --colon | cut -d':' -f1)
    LV_NAME=$(lvdisplay --colon | grep "$VG_NAME" | cut -d':' -f2 | head -n1)
    LV_PATH="/dev/$VG_NAME/$LV_NAME"

    lvextend -l +100%FREE "$LV_PATH" || error "Failed to extend logical volume"

    if [ "$FS_TYPE" = "xfs" ]; then
        xfs_growfs "$LV_PATH" || error "Failed to resize XFS filesystem"
    elif [[ "$FS_TYPE" == ext* ]]; then
        resize2fs "$LV_PATH" || error "Failed to resize ext filesystem"
    else
        error "Unsupported filesystem type: $FS_TYPE"
    fi

    mount_point=$(findmnt -n -o TARGET "$LV_PATH")
else
    info "Standard partition detected. Resizing filesystem..."

    if [ "$FS_TYPE" = "xfs" ]; then
        xfs_growfs "$FULL_PARTITION_PATH" || error "Failed to resize XFS filesystem"
    elif [[ "$FS_TYPE" == ext* ]]; then
        resize2fs "$FULL_PARTITION_PATH" || error "Failed to resize ext filesystem"
    else
        error "Unsupported filesystem type: $FS_TYPE"
    fi

    mount_point=$(findmnt -n -o TARGET "$FULL_PARTITION_PATH")
fi

# Display results
info "Final disk layout:"
lsblk "$DISK_TO_EXPAND"

if [ -n "$mount_point" ]; then
    info "Filesystem usage:"
    df -h "$mount_point"
else
    info "Mount point not found. The filesystem may not be mounted."
fi

info "Operation completed successfully. A system reboot is recommended."

#!/bin/bash

# Disk devices
DISKS=("sda" "sdb" "sdc" "sdd" "nvme0n1" "nvme1n1")

# Disk partitions
EFI_PARTITION="/dev/nvme0n1p1"
ROOT_PARTITION="/dev/nvme0n1p2"
HOME_PARTITION="/dev/nvme1n1p1"
SWAP_PARTITION="/dev/nvme1n1p2"
SLEIPNIR_PARTITION="/dev/sda1"  # Example of BTRFS RAID 0 partition

# Custom UUID prefixes
UUID_PREFIX="66696c657379737465736d"  # Hexadecimal of "filesystem"
EFI_UUID="${UUID_PREFIX}01"
ROOT_UUID="${UUID_PREFIX}02"
HOME_UUID="${UUID_PREFIX}03"
SLEIPNIR_UUID="${UUID_PREFIX}04"
SWAP_UUID="${UUID_PREFIX}00"

# Unmount all filesystems if mounted
umount -a

# Wipe the disks (Only the header and footer) to clear partition tables
echo "Wiping header and footer of disks..."
for disk in "${DISKS[@]}"; do
    # Wipe the first 1 MB (header) and the last 1 MB (footer) of the disk
    sudo dd if=/dev/zero of=/dev/$disk bs=1M count=1 status=progress    # Wipe the header
    sudo dd if=/dev/zero of=/dev/$disk bs=1M seek=$(( $(blockdev --getsize /dev/$disk) / 1048576 - 1)) count=1 status=progress    # Wipe the footer
done

# Remove Superblocks for Various Filesystems

echo "Removing BTRFS, LVM, ZFS, and MDADM superblocks..."

# Remove BTRFS superblocks
for disk in "${DISKS[@]}"; do
    sudo btrfs zero-superblock /dev/$disk
done

# Remove LVM metadata (LVM physical volume headers)
for disk in "${DISKS[@]}"; do
    sudo pvremove /dev/$disk --force
done

# Remove ZFS metadata
for disk in "${DISKS[@]}"; do
    sudo zpool destroy $(zpool list -H -o name)  # Destroy all ZFS pools
    sudo dd if=/dev/zero of=/dev/$disk bs=1M count=1 status=progress  # Zero out the first 1MB to clear ZFS metadata
done

# Remove MDADM superblocks
for disk in "${DISKS[@]}"; do
    sudo mdadm --zero-superblock /dev/$disk
done

# Partition the disks
echo "Partitioning disks..."
# Create partitions on nvme0n1 (EFI and ROOT)
parted /dev/nvme0n1 --script mklabel gpt
parted /dev/nvme0n1 --script mkpart primary fat32 1MiB 512MiB   # EFI partition
parted /dev/nvme0n1 --script mkpart primary btrfs 512MiB 100%   # ROOT partition

# Create partitions on nvme1n1 (HOME and SWAP)
parted /dev/nvme1n1 --script mklabel gpt
parted /dev/nvme1n1 --script mkpart primary btrfs 1MiB 100GB    # HOME partition
parted /dev/nvme1n1 --script mkpart primary linux-swap 100GB 140GB # SWAP partition (40GB)

# Partition the BTRFS RAID 0 disks (sda, sdb, sdc, sdd)
for disk in /dev/sda /dev/sdb /dev/sdc /dev/sdd; do
    parted $disk --script mklabel gpt
    parted $disk --script mkpart primary btrfs 1MiB 100%         # Single BTRFS partition for RAID 0
done

# Format partitions
echo "Formatting partitions with BTRFS..."
# Format the EFI partition
mkfs.fat -F32 /dev/nvme0n1p1

# Create the BTRFS RAID 0 for the data disks (sda, sdb, sdc, sdd)
mkfs.btrfs -f -d raid0 -m raid0 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1

# Format the HOME partition (BTRFS with Zstandard compression)
mkfs.btrfs -f -o compress=zstd /dev/nvme1n1p1

# Format the SWAP partition
mkswap /dev/nvme1n1p2

# Create the SLEIPNIR partition (BTRFS with Zstandard compression)
mkfs.btrfs -f -o compress=zstd /dev/sda2

# Label the filesystems
echo "Labeling filesystems..."

# EFI Partition (FAT32)
sudo fatlabel /dev/nvme0n1p1 Odin

# ROOT Partition (BTRFS)
sudo btrfs filesystem label /dev/nvme0n1p2 Thor

# HOME Partition (BTRFS)
sudo btrfs filesystem label /dev/nvme1n1p1 Freya

# SWAP Partition
sudo swaplabel /dev/nvme1n1p2 Tyr

# SLEIPNIR Partition (BTRFS)
sudo btrfs filesystem label /dev/sda2 Sleipnir

# Assign Custom UUIDs (For BTRFS filesystems, UUIDs are automatically generated)
# To assign UUIDs for filesystems manually:

# Assign the UUID for ROOT, HOME, and SLEIPNIR (these are done manually here)
tune2fs -U $ROOT_UUID /dev/nvme0n1p2
tune2fs -U $HOME_UUID /dev/nvme1n1p1
tune2fs -U $SLEIPNIR_UUID /dev/sda2

# Assign UUID for SWAP partition
mkswap --uuid $SWAP_UUID /dev/nvme1n1p2

# Mount the filesystems
echo "Mounting filesystems..."

# Mount the EFI partition
mkdir -p /mnt/efi
mount /dev/nvme0n1p1 /mnt/efi

# Mount the ROOT partition
mkdir -p /mnt/root
mount /dev/nvme0n1p2 /mnt/root

# Mount the HOME partition
mkdir -p /mnt/home
mount /dev/nvme1n1p1 /mnt/home

# Mount the SLEIPNIR partition
mkdir -p /mnt/sleipnir
mount /dev/sda2 /mnt/sleipnir

# Mount the SWAP partition
swapon /dev/nvme1n1p2

# Final status
echo "Partitioning, formatting, labeling, and mounting completed successfully."

# Display the mount status
lsblk


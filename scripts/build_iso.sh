#!/usr/bin/env bash
# Package the built shell + kernel into a hybrid UEFI-bootable ISO.
#
# The ISO can be flashed to a USB with balenaEtcher / Rufus (DD mode) /
# `dd if=os.iso of=/dev/sdX bs=4M` and the resulting stick will UEFI-boot on
# real x86_64 hardware. It also boots on legacy BIOS as a side effect of
# grub-mkrescue producing a fully hybrid image.
#
# High-level layout inside the ISO:
#   /boot/bzImage                  -- the Linux kernel
#   /boot/initramfs.cpio.gz        -- our shell + its shared libraries
#   /boot/grub/grub.cfg            -- config the bootloader executes
#   /EFI/BOOT/BOOTX64.EFI          -- GRUB EFI application (added by mkrescue)
#
# grub-mkrescue also embeds a small FAT "EFI System Partition" and a hybrid
# MBR/GPT so UEFI firmware finds the EFI app when the ISO is written to a USB.
#
# HOST-ONLY: This script does everything on the host machine (no Docker
# required). All it needs is a working shell binary, kernel image, and a
# handful of common Linux tools -- see the tool check below.
#
# REAL HARDWARE CAVEATS
#   * The kernel must have CONFIG_DRM_SIMPLEDRM=y so /dev/dri/card0 appears
#     from the UEFI framebuffer (build_kernel.sh enables this).
#   * Secure Boot must be disabled in firmware (our GRUB image is unsigned).
#   * Kernel command line uses console=tty0 so output goes to the physical
#     screen instead of a serial port that won't exist.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$PWD}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-linux}"
KERNEL_VERSION="${KERNEL_VERSION:-6.12.38}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$REPO_ROOT/linux-kernel/linux-${KERNEL_VERSION}/arch/x86_64/boot/bzImage}"
INITRAMFS_IMAGE="${INITRAMFS_IMAGE:-$REPO_ROOT/initramfs.cpio.gz}"
ISO_IMAGE="${ISO_IMAGE:-$REPO_ROOT/os.iso}"

# ---- preflight ---------------------------------------------------------------
if [[ ! -x "$BUILD_DIR/os" ]]; then
    echo "Shell binary not found at $BUILD_DIR/os" >&2
    echo "Build it first with: scripts/build_shell.sh" >&2
    exit 1
fi

if [[ ! -f "$KERNEL_IMAGE" ]]; then
    echo "Kernel image not found at $KERNEL_IMAGE" >&2
    echo "Build the kernel first with scripts/build_kernel.sh" >&2
    exit 1
fi

missing=()
for tool in xorriso grub-mkrescue cpio gzip ldd awk find; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if (( ${#missing[@]} > 0 )); then
    echo "Missing host tools: ${missing[*]}" >&2
    echo "Install them with: sudo apt install -y xorriso grub-common grub-efi-amd64-bin cpio" >&2
    exit 1
fi

# ---- 1. Package the initramfs on the host -----------------------------------
# We rebuild it every time so the ISO always reflects the current shell binary.
# The layout inside the cpio archive is a tiny Linux userspace:
#   /init          -- our shell (executed as PID 1 by the kernel)
#   /bin/os        -- same binary, also on PATH
#   /lib/...       -- shared libraries the ELF depends on (glibc, libstdc++...)
#   /dev, /proc, /sys -- empty mount points
echo "Packaging initramfs..."
INITRAMFS_DIR="$(mktemp -d -t os-initramfs-XXXXXX)"
trap 'rm -rf "$INITRAMFS_DIR"' EXIT

mkdir -p "$INITRAMFS_DIR"/{bin,dev,proc,sys}
cp "$BUILD_DIR/os" "$INITRAMFS_DIR/init"
chmod +x "$INITRAMFS_DIR/init"
cp "$BUILD_DIR/os" "$INITRAMFS_DIR/bin/os"
chmod +x "$INITRAMFS_DIR/bin/os"

# Copy every shared library ldd reports the binary needs, plus the dynamic
# linker itself. Two ldd output shapes to handle:
#   "libfoo.so => /path/to/libfoo.so (0x...)"    -- has =>, take field 3
#   "/lib64/ld-linux-x86-64.so.2 (0x...)"        -- no =>, take field 1
ldd "$BUILD_DIR/os" | awk '
    /=>/          { if ($3 ~ /^\//) print $3 }
    !/=>/ && $1 ~ /^\// { print $1 }
' | sort -u | while read -r lib; do
    dest="$INITRAMFS_DIR${lib}"
    mkdir -p "$(dirname "$dest")"
    cp "$lib" "$dest"
done

( cd "$INITRAMFS_DIR" && find . -print0 \
    | cpio --null -o --format=newc 2>/dev/null \
    | gzip -9 > "$INITRAMFS_IMAGE" )

echo "  -> $INITRAMFS_IMAGE ($(du -h "$INITRAMFS_IMAGE" | cut -f1))"

# ---- 2. Stage ISO contents on the host --------------------------------------
STAGE="$(mktemp -d -t os-iso-XXXXXX)"
trap 'rm -rf "$INITRAMFS_DIR" "$STAGE"' EXIT

mkdir -p "$STAGE/boot/grub"
cp "$KERNEL_IMAGE"    "$STAGE/boot/bzImage"
cp "$INITRAMFS_IMAGE" "$STAGE/boot/initramfs.cpio.gz"

# grub.cfg -- what the bootloader executes at boot time.
#   set default=0     -> pick the first menu entry
#   set timeout=1     -> wait 1 second before auto-booting
#   console=tty0      -> kernel + shell I/O go to the physical screen
#   rdinit=/init      -> use our shell as PID 1 from the initramfs
cat > "$STAGE/boot/grub/grub.cfg" <<'GRUBCFG'
set default=0
set timeout=1

insmod all_video

menuentry "Custom OS" {
    linux /boot/bzImage console=tty0 rdinit=/init
    initrd /boot/initramfs.cpio.gz
}
GRUBCFG

# ---- 3. Assemble the hybrid ISO ---------------------------------------------
# grub-mkrescue produces a single .iso that is simultaneously:
#   * a valid ISO 9660 filesystem (mountable, browsable)
#   * a UEFI boot medium (embedded FAT ESP with /EFI/BOOT/BOOTX64.EFI)
#   * a legacy BIOS boot medium (embedded isohdpfx + El Torito catalog)
#   * a hybrid MBR/GPT disk (Etcher/Rufus write it byte-for-byte to a USB and
#     firmware still finds the ESP)
echo "Building ISO with grub-mkrescue..."
grub-mkrescue \
    --compress=xz \
    -o "$ISO_IMAGE" \
    "$STAGE" \
    -- \
    -volid "CUSTOM_OS"

echo
echo "ISO ready at: $ISO_IMAGE"
ls -lh "$ISO_IMAGE"
echo
echo "Flash to a USB stick with balenaEtcher, Rufus (DD mode),"
echo "or: sudo dd if=$ISO_IMAGE of=/dev/sdX bs=4M status=progress conv=fsync"
echo
echo "Boot the USB via your firmware's UEFI boot menu. Disable Secure Boot."

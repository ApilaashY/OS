#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-linux}"
KERNEL_BUILD_DIR="${KERNEL_BUILD_DIR:-$REPO_ROOT/build-kernel-linux-amd64}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$KERNEL_BUILD_DIR/arch/x86_64/boot/bzImage}"
INITRAMFS_DIR="${INITRAMFS_DIR:-$REPO_ROOT/initramfs}"
INITRAMFS_IMAGE="${INITRAMFS_IMAGE:-$REPO_ROOT/initramfs.cpio.gz}"
ISO_ROOT="${ISO_ROOT:-$REPO_ROOT/build/iso-root}"
ISO_OUTPUT="${ISO_OUTPUT:-$REPO_ROOT/build/os-live.iso}"
KERNEL_CMDLINE="${KERNEL_CMDLINE:-console=tty0 console=ttyS0 rdinit=/init loglevel=7}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-linux-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$REPO_ROOT/scripts/linux-toolchain.Dockerfile}"
KEYS_DIR="${KEYS_DIR:-$REPO_ROOT/keys/secureboot}"

ensure_image() {
  local image_platform
  image_platform="$(docker image inspect "$DOCKER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || true)"

  if [[ "$image_platform" != "$DOCKER_PLATFORM" ]]; then
    echo "Building Linux toolchain image..."
    docker buildx build --load --platform "$DOCKER_PLATFORM" -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$REPO_ROOT"
  fi
}

package_initramfs() {
  if [[ ! -x "$BUILD_DIR/os" ]]; then
    echo "Shell binary not found at $BUILD_DIR/os" >&2
    echo "Building it first with scripts/build_shell.sh" >&2
    "$SCRIPT_DIR/build_shell.sh"
  fi

  echo "Packaging initramfs for the bootable ISO..."
  rm -rf "$INITRAMFS_DIR"
  mkdir -p "$INITRAMFS_DIR"

  docker run --rm \
    --platform "$DOCKER_PLATFORM" \
    -v "$REPO_ROOT:/work" \
    -w /work \
    "$DOCKER_IMAGE" \
    bash -lc '
      set -euo pipefail
      rm -rf /work/initramfs
      mkdir -p /work/initramfs/bin /work/initramfs/dev /work/initramfs/proc /work/initramfs/sys
      mknod -m 600 /work/initramfs/dev/console c 5 1 2>/dev/null || true
      mknod -m 666 /work/initramfs/dev/null c 1 3 2>/dev/null || true
      mknod -m 666 /work/initramfs/dev/ttyS0 c 4 64 2>/dev/null || true
      cp /work/build-linux/os /work/initramfs/init
      chmod +x /work/initramfs/init
      ldd /work/build-linux/os | awk "
        /=> \/|\// {
          for (i = 1; i <= NF; i++) {
            if (\$i ~ /^\//) {
              print \$i
            }
          }
        }" | while read -r lib; do
          dest="/work/initramfs${lib}"
          mkdir -p "$(dirname "$dest")"
          cp "$lib" "$dest"
        done
      cp /work/build-linux/os /work/initramfs/bin/os
      chmod +x /work/initramfs/bin/os
      ( cd /work/initramfs && find . -print0 | cpio --null -ov --format=newc | gzip -9 > /work/initramfs.cpio.gz )
    '
}

build_iso() {
  if [[ ! -f "$KERNEL_IMAGE" ]]; then
    echo "Kernel image not found at $KERNEL_IMAGE" >&2
    echo "Building it first with scripts/build_kernel.sh" >&2
    "$SCRIPT_DIR/build_kernel.sh"
  fi

  if [[ ! -f "$INITRAMFS_IMAGE" ]]; then
    package_initramfs
  fi

  rm -rf "$ISO_ROOT"
  mkdir -p "$ISO_ROOT" "$KEYS_DIR" "$(dirname "$ISO_OUTPUT")"

  cat > "$REPO_ROOT/build/grub.cfg" <<EOF
set timeout=5
set default=0
search --no-floppy --set=root --file /boot/vmlinuz

menuentry "os" {
  linux /boot/vmlinuz $KERNEL_CMDLINE
  initrd /boot/initrd.img
}
EOF

  echo "Creating Secure Boot bootable ISO at $ISO_OUTPUT"
  docker run --rm \
    --platform "$DOCKER_PLATFORM" \
    -v "$REPO_ROOT:/work" \
    -w /work \
    "$DOCKER_IMAGE" \
    bash -lc '
      set -euo pipefail

      KEY=/work/keys/secureboot/MOK.key
      CRT=/work/keys/secureboot/MOK.crt
      DER=/work/keys/secureboot/MOK.der

      if [[ ! -f "$KEY" || ! -f "$CRT" ]]; then
        echo "Generating persistent Secure Boot signing key/certificate..."
        openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CRT" \
          -nodes -days 3650 -subj "/CN=os-live Secure Boot Signing/"
        chmod 600 "$KEY"
      fi
      openssl x509 -in "$CRT" -outform DER -out "$DER"

      rm -rf /work/build/esp
      mkdir -p /work/build/esp/EFI/BOOT /work/build/esp/boot/grub /work/build/esp/boot

      # shim is trusted by standard UEFI Secure Boot databases and launches
      # Canonical-signed GRUB, which validates the MOK-signed kernel.
      cp /usr/lib/shim/shimx64.efi.signed.latest /work/build/esp/EFI/BOOT/BOOTX64.EFI
      cp /usr/lib/shim/mmx64.efi /work/build/esp/EFI/BOOT/mmx64.efi
      cp /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed /work/build/esp/EFI/BOOT/grubx64.efi
      cp /work/build/grub.cfg /work/build/esp/boot/grub/grub.cfg
      sbsign --key "$KEY" --cert "$CRT" \
        --output /work/build/esp/boot/vmlinuz /work/build-kernel-linux-amd64/arch/x86_64/boot/bzImage
      cp /work/initramfs.cpio.gz /work/build/esp/boot/initrd.img
      cp "$DER" /work/build/esp/MOK.der

      content_kb=$(du -sk /work/build/esp | cut -f1)
      img_kb=$((content_kb + 8192))
      rm -f /work/build/efiboot.img
      dd if=/dev/zero of=/work/build/efiboot.img bs=1024 count="$img_kb" status=none
      mkfs.vfat -n OS_ESP /work/build/efiboot.img >/dev/null

      mmd -i /work/build/efiboot.img ::EFI ::EFI/BOOT ::boot ::boot/grub
      mcopy -i /work/build/efiboot.img /work/build/esp/EFI/BOOT/BOOTX64.EFI ::EFI/BOOT/BOOTX64.EFI
      mcopy -i /work/build/efiboot.img /work/build/esp/EFI/BOOT/mmx64.efi ::EFI/BOOT/mmx64.efi
      mcopy -i /work/build/efiboot.img /work/build/esp/EFI/BOOT/grubx64.efi ::EFI/BOOT/grubx64.efi
      mcopy -i /work/build/efiboot.img /work/build/esp/boot/grub/grub.cfg ::boot/grub/grub.cfg
      mcopy -i /work/build/efiboot.img /work/build/esp/boot/vmlinuz ::boot/vmlinuz
      mcopy -i /work/build/efiboot.img /work/build/esp/boot/initrd.img ::boot/initrd.img
      mcopy -i /work/build/efiboot.img /work/build/esp/MOK.der ::MOK.der

      cp "$DER" /work/build/iso-root/MOK.der
      xorriso -as mkisofs \
        -V OS_LIVE \
        -o /work/build/os-live.iso \
        -partition_offset 16 \
        -c boot.catalog \
        -append_partition 2 0xef /work/build/efiboot.img \
        -no-emul-boot \
        -e --interval:appended_partition_2:all:: \
        /work/build/iso-root
    '

  if [[ -f "$ISO_OUTPUT" ]]; then
    echo "ISO image ready: $ISO_OUTPUT"
    echo "Enroll once without BIOS: $SCRIPT_DIR/enroll_secureboot_key.sh"
  else
    echo "ISO image was not produced at $ISO_OUTPUT" >&2
    exit 1
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to build the ISO image from this host setup." >&2
  exit 1
fi

ensure_image
build_iso

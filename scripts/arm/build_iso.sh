#!/usr/bin/env bash
set -euo pipefail

# arm64 has no legacy BIOS boot path, so this ISO is EFI-only (the toolchain
# image installs grub-efi-arm64-bin instead of grub-pc-bin/grub-efi-amd64-bin).
# Booting it in QEMU requires arm64 UEFI firmware (e.g. AAVMF/edk2-aarch64),
# passed via `-bios`/`-pflash`; boot_qemu.sh instead boots the kernel Image
# directly and doesn't need this ISO.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-arm64}"
KERNEL_BUILD_DIR="${KERNEL_BUILD_DIR:-$REPO_ROOT/build-kernel-linux-arm64}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$KERNEL_BUILD_DIR/arch/arm64/boot/Image}"
INITRAMFS_DIR="${INITRAMFS_DIR:-$REPO_ROOT/initramfs-arm64}"
INITRAMFS_IMAGE="${INITRAMFS_IMAGE:-$REPO_ROOT/initramfs-arm64.cpio.gz}"
ISO_ROOT="${ISO_ROOT:-$REPO_ROOT/build/iso-root-arm64}"
ISO_OUTPUT="${ISO_OUTPUT:-$REPO_ROOT/build/os-live-arm64.iso}"
KERNEL_CMDLINE="${KERNEL_CMDLINE:-console=ttyAMA0 rdinit=/init loglevel=7}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/arm64}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-arm64-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$SCRIPT_DIR/linux-toolchain.Dockerfile}"

ensure_image() {
  local image_platform
  image_platform="$(docker image inspect "$DOCKER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || true)"

  if [[ "$image_platform" != "$DOCKER_PLATFORM" ]]; then
    echo "Building arm64 Linux toolchain image..."
    docker buildx build --load --platform "$DOCKER_PLATFORM" -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$REPO_ROOT"
  fi
}

package_initramfs() {
  if [[ ! -x "$BUILD_DIR/os" ]]; then
    echo "Shell binary not found at $BUILD_DIR/os" >&2
    echo "Building it first with scripts/arm/build_shell.sh" >&2
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
      rm -rf /work/initramfs-arm64
      mkdir -p /work/initramfs-arm64/bin /work/initramfs-arm64/dev /work/initramfs-arm64/proc /work/initramfs-arm64/sys
      mknod -m 600 /work/initramfs-arm64/dev/console c 5 1 2>/dev/null || true
      mknod -m 666 /work/initramfs-arm64/dev/null c 1 3 2>/dev/null || true
      mknod -m 666 /work/initramfs-arm64/dev/ttyAMA0 c 204 64 2>/dev/null || true
      cp /work/build-arm64/os /work/initramfs-arm64/init
      chmod +x /work/initramfs-arm64/init
      ldd /work/build-arm64/os | awk "
        /=> \/|\// {
          for (i = 1; i <= NF; i++) {
            if (\$i ~ /^\//) {
              print \$i
            }
          }
        }" | while read -r lib; do
          dest="/work/initramfs-arm64${lib}"
          mkdir -p "$(dirname "$dest")"
          cp "$lib" "$dest"
        done
      cp /work/build-arm64/os /work/initramfs-arm64/bin/os
      chmod +x /work/initramfs-arm64/bin/os
      ( cd /work/initramfs-arm64 && find . -print0 | cpio --null -ov --format=newc | gzip -9 > /work/initramfs-arm64.cpio.gz )
    '
}

build_iso() {
  if [[ ! -f "$KERNEL_IMAGE" ]]; then
    echo "Kernel image not found at $KERNEL_IMAGE" >&2
    echo "Building it first with scripts/arm/build_kernel.sh" >&2
    "$SCRIPT_DIR/build_kernel.sh"
  fi

  if [[ ! -f "$INITRAMFS_IMAGE" ]]; then
    package_initramfs
  fi

  rm -rf "$ISO_ROOT"
  mkdir -p "$ISO_ROOT/boot/grub"
  mkdir -p "$(dirname "$ISO_OUTPUT")"

  cp "$KERNEL_IMAGE" "$ISO_ROOT/boot/vmlinuz"
  cp "$INITRAMFS_IMAGE" "$ISO_ROOT/boot/initrd.img"

  cat > "$ISO_ROOT/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0

menuentry "os" {
  linux /boot/vmlinuz $KERNEL_CMDLINE
  initrd /boot/initrd.img
}
EOF

  echo "Creating bootable arm64 EFI ISO at $ISO_OUTPUT"
  docker run --rm \
    --platform "$DOCKER_PLATFORM" \
    -v "$REPO_ROOT:/work" \
    -w /work \
    "$DOCKER_IMAGE" \
    bash -lc "set -euo pipefail; grub-mkrescue -o /work/build/os-live-arm64.iso /work/build/iso-root-arm64"

  if [[ -f "$ISO_OUTPUT" ]]; then
    echo "ISO image ready: $ISO_OUTPUT"
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

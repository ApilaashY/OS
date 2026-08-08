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

  echo "Creating bootable ISO at $ISO_OUTPUT"
  docker run --rm \
    --platform "$DOCKER_PLATFORM" \
    -v "$REPO_ROOT:/work" \
    -w /work \
    "$DOCKER_IMAGE" \
    bash -lc "set -euo pipefail; grub-mkrescue -o /work/build/os-live.iso /work/build/iso-root"

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

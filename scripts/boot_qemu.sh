#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$PWD}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-linux}"
KERNEL_VERSION="${KERNEL_VERSION:-6.12.38}"
WORKDIR="${WORKDIR:-$REPO_ROOT/linux-kernel}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$WORKDIR/linux-${KERNEL_VERSION}/arch/x86_64/boot/bzImage}"
INITRAMFS_DIR="${INITRAMFS_DIR:-$REPO_ROOT/initramfs}"
INITRAMFS_IMAGE="${INITRAMFS_IMAGE:-$REPO_ROOT/initramfs.cpio.gz}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-linux-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$REPO_ROOT/scripts/linux-toolchain.Dockerfile}"

ensure_image() {
  if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    echo "Building Linux toolchain image..."
    docker build -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$REPO_ROOT"
  fi
}

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

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to package the initramfs from this host setup." >&2
  exit 1
fi

ensure_image

rm -rf "$INITRAMFS_DIR"
mkdir -p "$INITRAMFS_DIR"

echo "Packaging initramfs inside Linux container..."
docker run --rm \
  -v "$REPO_ROOT:/work" \
  -w /work \
  "$DOCKER_IMAGE" \
  bash -lc '
    set -euo pipefail
    rm -rf /work/initramfs
    mkdir -p /work/initramfs/bin /work/initramfs/dev /work/initramfs/proc /work/initramfs/sys
    cp /work/build-linux/os /work/initramfs/init
    chmod +x /work/initramfs/init
    ldd /work/build-linux/os | awk "
      /=> \\/|\\// {
        for (i = 1; i <= NF; i++) {
          if (\$i ~ /^\\//) {
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

echo "Booting QEMU..."
exec "$QEMU_BIN" \
  -m 512M \
  -nographic \
  -kernel "$KERNEL_IMAGE" \
  -initrd "$INITRAMFS_IMAGE" \
  -append "console=ttyS0 rdinit=/init"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-arm64}"
KERNEL_BUILD_DIR="${KERNEL_BUILD_DIR:-$REPO_ROOT/build-kernel-linux-arm64}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$KERNEL_BUILD_DIR/arch/arm64/boot/Image}"
INITRAMFS_DIR="${INITRAMFS_DIR:-$REPO_ROOT/initramfs-arm64}"
INITRAMFS_IMAGE="${INITRAMFS_IMAGE:-$REPO_ROOT/initramfs-arm64.cpio.gz}"
QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"
QEMU_MACHINE="${QEMU_MACHINE:-virt}"
QEMU_CPU="${QEMU_CPU:-max}"
KERNEL_CMDLINE="${KERNEL_CMDLINE:-console=ttyAMA0 rdinit=/init loglevel=7}"
QEMU_HEADLESS="${QEMU_HEADLESS:-0}"
QEMU_DAEMONIZE="${QEMU_DAEMONIZE:-0}"
QEMU_MOUSE_DEVICE="${QEMU_MOUSE_DEVICE:-virtio-mouse-pci}"
QEMU_DISPLAY_RES="${QEMU_DISPLAY_RES:-1920x1080}"
QEMU_SERIAL_LOG="${QEMU_SERIAL_LOG:-$REPO_ROOT/qemu-serial-arm64.log}"
QEMU_PIDFILE="${QEMU_PIDFILE:-$REPO_ROOT/qemu-arm64.pid}"
KILL_STALE_QEMU="${KILL_STALE_QEMU:-1}"
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

if [[ ! -x "$BUILD_DIR/os" ]]; then
  echo "Shell binary not found at $BUILD_DIR/os" >&2
  echo "Build it first with: scripts/arm/build_shell.sh" >&2
  exit 1
fi

if [[ ! -f "$KERNEL_IMAGE" ]]; then
  echo "Kernel image not found at $KERNEL_IMAGE" >&2
  echo "Build the kernel first with scripts/arm/build_kernel.sh" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to package the initramfs from this host setup." >&2
  exit 1
fi

ensure_image

if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  echo "QEMU binary not found: $QEMU_BIN" >&2
  echo "Install it with: brew install qemu" >&2
  exit 1
fi

if [[ "$KILL_STALE_QEMU" == "1" ]]; then
  # Kill only the QEMU instance this script previously started. A broad
  # `pkill -f qemu-system-aarch64` could match other unrelated VMs.
  if [[ -f "$QEMU_PIDFILE" ]]; then
    stale_pid="$(cat "$QEMU_PIDFILE" 2>/dev/null || true)"
    if [[ -n "${stale_pid:-}" ]] && kill -0 "$stale_pid" 2>/dev/null; then
      if grep -q "$KERNEL_IMAGE" "/proc/$stale_pid/cmdline" 2>/dev/null; then
        kill "$stale_pid" 2>/dev/null || true
      fi
    fi
    rm -f "$QEMU_PIDFILE"
  fi
fi

rm -rf "$INITRAMFS_DIR"
mkdir -p "$INITRAMFS_DIR"

echo "Packaging initramfs inside arm64 Linux container..."
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
      /=> \\/|\\// {
        for (i = 1; i <= NF; i++) {
          if (\$i ~ /^\\//) {
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

echo "Booting QEMU (aarch64/$QEMU_MACHINE)..."
# QEMU's `virt` board has no built-in GPU/GIC-attached display, so the
# virtio-gpu-pci device is added unconditionally (even headless) so
# /dev/dri/card0 exists for the Graphics class to open. `-kernel` boots the
# arm64 Image directly; no firmware/EFI is needed on the `virt` machine.
if [[ "$QEMU_DAEMONIZE" == "1" ]]; then
  rm -f "$QEMU_SERIAL_LOG" "$QEMU_PIDFILE"
  "$QEMU_BIN" \
    -M "$QEMU_MACHINE" \
    -cpu "$QEMU_CPU" \
    -m 512M \
    -display none \
    -monitor none \
    -device "virtio-gpu-pci,xres=${QEMU_DISPLAY_RES%x*},yres=${QEMU_DISPLAY_RES#*x}" \
    -device "$QEMU_MOUSE_DEVICE" \
    -serial "file:$QEMU_SERIAL_LOG" \
    -pidfile "$QEMU_PIDFILE" \
    -daemonize \
    -kernel "$KERNEL_IMAGE" \
    -initrd "$INITRAMFS_IMAGE" \
    -append "$KERNEL_CMDLINE"
  echo "QEMU started in daemon mode"
  echo "PID file: $QEMU_PIDFILE"
  echo "Serial log: $QEMU_SERIAL_LOG"
  exit 0
elif [[ "$QEMU_HEADLESS" == "1" ]]; then
  exec "$QEMU_BIN" \
    -M "$QEMU_MACHINE" \
    -cpu "$QEMU_CPU" \
    -m 512M \
    -nographic \
    -monitor none \
    -device "virtio-gpu-pci,xres=${QEMU_DISPLAY_RES%x*},yres=${QEMU_DISPLAY_RES#*x}" \
    -device "$QEMU_MOUSE_DEVICE" \
    -serial stdio \
    -kernel "$KERNEL_IMAGE" \
    -initrd "$INITRAMFS_IMAGE" \
    -append "$KERNEL_CMDLINE"
else
  exec "$QEMU_BIN" \
    -M "$QEMU_MACHINE" \
    -cpu "$QEMU_CPU" \
    -m 512M \
    -device "virtio-gpu-pci,xres=${QEMU_DISPLAY_RES%x*},yres=${QEMU_DISPLAY_RES#*x}" \
    -device "$QEMU_MOUSE_DEVICE" \
    -serial mon:stdio \
    -kernel "$KERNEL_IMAGE" \
    -initrd "$INITRAMFS_IMAGE" \
    -append "$KERNEL_CMDLINE"
fi

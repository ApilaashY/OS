#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-linux}"
KERNEL_VERSION="${KERNEL_VERSION:-6.12.38}"
WORKDIR="${WORKDIR:-$REPO_ROOT/linux-kernel}"
KERNEL_BUILD_DIR="${KERNEL_BUILD_DIR:-$REPO_ROOT/build-kernel-linux-amd64}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$KERNEL_BUILD_DIR/arch/x86_64/boot/bzImage}"
INITRAMFS_DIR="${INITRAMFS_DIR:-$REPO_ROOT/initramfs}"
INITRAMFS_IMAGE="${INITRAMFS_IMAGE:-$REPO_ROOT/initramfs.cpio.gz}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
KERNEL_CMDLINE="${KERNEL_CMDLINE:-console=tty0 console=ttyS0 rdinit=/init loglevel=7}"
QEMU_HEADLESS="${QEMU_HEADLESS:-0}"
QEMU_DAEMONIZE="${QEMU_DAEMONIZE:-0}"
QEMU_MOUSE_DEVICE="${QEMU_MOUSE_DEVICE:-usb-tablet}"
QEMU_SERIAL_LOG="${QEMU_SERIAL_LOG:-$REPO_ROOT/qemu-serial.log}"
QEMU_PIDFILE="${QEMU_PIDFILE:-$REPO_ROOT/qemu.pid}"
KILL_STALE_QEMU="${KILL_STALE_QEMU:-1}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-linux-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$REPO_ROOT/scripts/linux-toolchain.Dockerfile}"

proxy_build_args() {
  # Forward proxy env vars into the build only when set on the host.
  local http_val="${http_proxy:-${HTTP_PROXY:-}}"
  local https_val="${https_proxy:-${HTTPS_PROXY:-$http_val}}"
  local no_val="${no_proxy:-${NO_PROXY:-}}"
  local args=()
  [[ -n "$http_val" ]]  && args+=(--build-arg "http_proxy=$http_val")
  [[ -n "$https_val" ]] && args+=(--build-arg "https_proxy=$https_val")
  [[ -n "$no_val" ]]    && args+=(--build-arg "no_proxy=$no_val")
  printf '%s\n' "${args[@]}"
}

ensure_image() {
  local image_platform
  image_platform="$(docker image inspect "$DOCKER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || true)"

  if [[ "$image_platform" != "$DOCKER_PLATFORM" ]]; then
    echo "Building Linux toolchain image..."
    local build_args=()
    mapfile -t build_args < <(proxy_build_args)
    if (( ${#build_args[@]} )); then
      echo "Forwarding host proxy settings into image build."
    fi
    docker buildx build --load --platform "$DOCKER_PLATFORM" "${build_args[@]}" -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$REPO_ROOT"
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

if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  echo "QEMU binary not found: $QEMU_BIN" >&2
  exit 1
fi

if [[ "$KILL_STALE_QEMU" == "1" ]]; then
  # Kill only the QEMU instance this script previously started. A broad
  # `pkill -f qemu-system-x86_64` also matches Docker Desktop's own VM process
  # and takes the Docker daemon down with it.
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

echo "Packaging initramfs inside Linux container..."
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
if [[ "$QEMU_DAEMONIZE" == "1" ]]; then
  rm -f "$QEMU_SERIAL_LOG" "$QEMU_PIDFILE"
  "$QEMU_BIN" \
    -m 512M \
    -display none \
    -monitor none \
    -serial "file:$QEMU_SERIAL_LOG" \
    -pidfile "$QEMU_PIDFILE" \
    -daemonize \
    -usb \
    -device "$QEMU_MOUSE_DEVICE" \
    -kernel "$KERNEL_IMAGE" \
    -initrd "$INITRAMFS_IMAGE" \
    -append "$KERNEL_CMDLINE"
  echo "QEMU started in daemon mode"
  echo "PID file: $QEMU_PIDFILE"
  echo "Serial log: $QEMU_SERIAL_LOG"
  exit 0
elif [[ "$QEMU_HEADLESS" == "1" ]]; then
  exec "$QEMU_BIN" \
    -m 512M \
    -nographic \
    -monitor none \
    -serial stdio \
    -usb \
    -device "$QEMU_MOUSE_DEVICE" \
    -kernel "$KERNEL_IMAGE" \
    -initrd "$INITRAMFS_IMAGE" \
    -append "$KERNEL_CMDLINE"
else
  exec "$QEMU_BIN" \
    -m 512M \
    -vga std \
    -serial mon:stdio \
    -usb \
    -device "$QEMU_MOUSE_DEVICE" \
    -kernel "$KERNEL_IMAGE" \
    -initrd "$INITRAMFS_IMAGE" \
    -append "$KERNEL_CMDLINE"
fi

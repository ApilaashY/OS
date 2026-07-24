#!/usr/bin/env bash
set -euo pipefail

KERNEL_VERSION="${KERNEL_VERSION:-6.12.38}"
WORKDIR="${WORKDIR:-$PWD/linux-kernel}"
KERNEL_DIR="${KERNEL_DIR:-$WORKDIR/linux-${KERNEL_VERSION}}"
ARCH="${ARCH:-x86_64}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-linux-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$PWD/scripts/linux-toolchain.Dockerfile}"

ensure_image() {
  if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    echo "Building Linux toolchain image..."
    docker build -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$PWD"
  fi
}

if [[ ! -d "$KERNEL_DIR" ]]; then
  echo "Kernel source directory not found: $KERNEL_DIR" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to build the Linux kernel from this host setup." >&2
  exit 1
fi

ensure_image

echo "Configuring and building kernel inside Linux container..."
echo "Using x86_64 platform for full kernel compilation compatibility."

# Build with x86_64 platform emulation
docker run --rm \
  --platform linux/amd64 \
  -e ARCH="$ARCH" \
  -e JOBS="$JOBS" \
  -e KERNEL_VERSION="$KERNEL_VERSION" \
  -v "$PWD:/work" \
  -w "/work/linux-kernel/linux-${KERNEL_VERSION}" \
  "$DOCKER_IMAGE" \
  bash -lc '
    if [[ ! -f .config ]]; then
      make ARCH="$ARCH" LLVM=1 LLVM_IAS=1 defconfig
    fi
    # Options needed to boot both under QEMU (bochs) AND on real UEFI hardware
    # (simpledrm for the firmware framebuffer, USB HID for keyboards, and
    # devtmpfs so /dev/dri/card0 appears without udev).
    ./scripts/config \
        -e DRM -e DRM_BOCHS -e DRM_SIMPLEDRM \
        -e DEVTMPFS -e DEVTMPFS_MOUNT \
        -e USB -e USB_XHCI_HCD -e USB_EHCI_HCD -e USB_OHCI_HCD \
        -e USB_HID -e HID_GENERIC \
        -e INPUT -e INPUT_KEYBOARD -e KEYBOARD_ATKBD \
        -e EFI -e EFI_STUB
    make ARCH="$ARCH" LLVM=1 LLVM_IAS=1 olddefconfig
    echo "Kernel configuration complete. Building bzImage..."
    echo "Building with full x86_64 platform support."
    make ARCH="$ARCH" LLVM=1 LLVM_IAS=1 -j"$JOBS" bzImage
  '

echo "Kernel image ready at: arch/${ARCH}/boot/bzImage"
echo "Note: Kernel built successfully using x86_64 platform emulation."

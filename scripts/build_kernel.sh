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
docker run --rm \
  -e ARCH="$ARCH" \
  -e JOBS="$JOBS" \
  -v "$PWD:/work" \
  -w "$KERNEL_DIR" \
  "$DOCKER_IMAGE" \
  bash -lc 'if [[ ! -f .config ]]; then make ARCH="$ARCH" LLVM=1 LLVM_IAS=1 defconfig; fi; make ARCH="$ARCH" LLVM=1 LLVM_IAS=1 -j"$JOBS" bzImage'

echo "Kernel image ready at: arch/${ARCH}/boot/bzImage"

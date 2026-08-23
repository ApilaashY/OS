#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

KERNEL_VERSION="${KERNEL_VERSION:-6.12.38}"
WORKDIR="${WORKDIR:-$REPO_ROOT/linux-kernel}"
KERNEL_DIR="${KERNEL_DIR:-$WORKDIR/linux-${KERNEL_VERSION}}"
KERNEL_BUILD_DIR="${KERNEL_BUILD_DIR:-$REPO_ROOT/build-kernel-linux-arm64}"
ARCH="${ARCH:-arm64}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
CLEAN_BUILD="${CLEAN_BUILD:-1}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/arm64}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-arm64-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$SCRIPT_DIR/linux-toolchain.Dockerfile}"

proxy_build_args() {
  # Forward proxy env vars into the build only when set on the host.
  local http_val="${http_proxy:-${HTTP_PROXY:-}}"
  local https_val="${https_proxy:-${HTTPS_PROXY:-$http_val}}"
  local no_val="${no_proxy:-${NO_PROXY:-}}"
  build_args=()
  [[ -n "$http_val" ]]  && build_args+=(--build-arg "http_proxy=$http_val")
  [[ -n "$https_val" ]] && build_args+=(--build-arg "https_proxy=$https_val")
  [[ -n "$no_val" ]]    && build_args+=(--build-arg "no_proxy=$no_val")
  return 0
}

ensure_image() {
  local image_platform
  image_platform="$(docker image inspect "$DOCKER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || true)"

  if [[ "$image_platform" != "$DOCKER_PLATFORM" ]]; then
    echo "Building arm64 Linux toolchain image..."
    local build_args
    proxy_build_args
    docker buildx build --load --platform "$DOCKER_PLATFORM" ${build_args[@]+"${build_args[@]}"} -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$REPO_ROOT"

    image_platform="$(docker image inspect "$DOCKER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || true)"
    if [[ "$image_platform" != "$DOCKER_PLATFORM" ]]; then
      echo "Failed to make Docker image available locally as $DOCKER_PLATFORM: $DOCKER_IMAGE" >&2
      echo "Current image platform: ${image_platform:-missing}" >&2
      exit 1
    fi
  else
    echo "Using existing Docker image $DOCKER_IMAGE ($image_platform)."
  fi
}

if [[ ! -d "$KERNEL_DIR" ]]; then
  echo "Kernel source directory not found: $KERNEL_DIR" >&2
  echo "Fetch it first with: scripts/arm/fetch_kernel.sh" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to build the Linux kernel from this host setup." >&2
  exit 1
fi

ensure_image

if [[ "$CLEAN_BUILD" == "1" ]]; then
  echo "Performing clean out-of-tree kernel build in: $KERNEL_BUILD_DIR"
  rm -rf "$KERNEL_BUILD_DIR"
fi
mkdir -p "$KERNEL_BUILD_DIR"

echo "Configuring and building kernel inside arm64 Linux container..."
echo "Running natively under linux/arm64 (via QEMU user-mode emulation if the host isn't arm64)."

docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -e ARCH="$ARCH" \
  -e JOBS="$JOBS" \
  -e KERNEL_VERSION="$KERNEL_VERSION" \
  -v "$REPO_ROOT:/work" \
  -w "/work/linux-kernel/linux-${KERNEL_VERSION}" \
  "$DOCKER_IMAGE" \
  bash -lc '
    set -euo pipefail

    repair_objtool_tree_if_needed() {
      local src_root="/work/scripts/linux-kernel/linux-${KERNEL_VERSION}/tools/objtool"
      local dst_root="/work/linux-kernel/linux-${KERNEL_VERSION}/tools/objtool"

      # If the working kernel tree lost objtool sources, restore them from
      # the backup kernel tree shipped in this repository.
      if [[ -f "$dst_root/Makefile" && ! -f "$dst_root/objtool.c" ]]; then
        if [[ ! -f "$src_root/objtool.c" ]]; then
          echo "objtool sources missing and no backup found at: $src_root" >&2
          exit 1
        fi
        echo "Restoring missing objtool sources from backup kernel tree..."
        rm -rf "$dst_root"
        mkdir -p "$(dirname "$dst_root")"
        cp -a "$src_root" "$dst_root"
      fi
    }

    repair_objtool_tree_if_needed

    # Some host filesystems are case-insensitive and may preserve the wrong
    # filename casing from prior edits/checkouts. Kbuild resolves sources by
    # exact case (e.g. xt_TCPMSS.c), so normalize known mismatches first.
    fix_case_path() {
      local rel_dir="$1"
      local expected="$2"
      local dir_path="/work/linux-kernel/linux-""$KERNEL_VERSION""/${rel_dir}"
      local actual

      if ls "$dir_path" | grep -Fxq "$expected"; then
        return 0
      fi

      actual="$(ls "$dir_path" | awk -v expected_name="$expected" '"'"'tolower($0) == tolower(expected_name) { print; exit }'"'"')"
      if [[ -n "$actual" && "$actual" != "$expected" ]]; then
        echo "Normalizing source filename case: ${rel_dir}/${actual} -> ${rel_dir}/${expected}"
        mv "$dir_path/$actual" "$dir_path/.casefix.$$.$expected.tmp"
        mv "$dir_path/.casefix.$$.$expected.tmp" "$dir_path/$expected"
      fi
    }

    fix_case_path net/netfilter xt_TCPMSS.c

    rm -rf \
      /work/linux-kernel/linux-"$KERNEL_VERSION"/.config \
      /work/linux-kernel/linux-"$KERNEL_VERSION"/arch/arm64/include/generated \
      /work/linux-kernel/linux-"$KERNEL_VERSION"/include/config \
      /work/linux-kernel/linux-"$KERNEL_VERSION"/include/generated

    AR=ar NM=nm OBJCOPY=objcopy READELF=readelf STRIP=strip OBJDUMP=objdump \
      CC=clang-18 LD=ld.lld HOSTCC=clang-18 HOSTLD=ld.lld LLVM_IAS=1 \
      make O=/work/build-kernel-linux-arm64 ARCH="$ARCH" defconfig
    # Options needed to boot under QEMU'"'"'s `virt` machine: a generic PCI
    # host bridge + virtio-pci for the GPU/mouse/console devices we pass on
    # the command line, PL011 for the early serial console, and devtmpfs so
    # /dev/dri/card0 appears without udev.
    ./scripts/config --file /work/build-kernel-linux-arm64/.config \
        -e PCI -e PCI_HOST_GENERIC -e PCI_HOST_COMMON \
        -e VIRTIO -e VIRTIO_PCI -e VIRTIO_MMIO -e VIRTIO_INPUT \
        -e DRM -e DRM_VIRTIO_GPU \
        -e SERIAL_AMBA_PL011 -e SERIAL_AMBA_PL011_CONSOLE \
        -e VGA_CONSOLE -e FRAMEBUFFER_CONSOLE \
        -e DEVTMPFS -e DEVTMPFS_MOUNT \
        -e USB -e USB_XHCI_HCD -e USB_XHCI_PCI \
        -e USB_HID -e HID_GENERIC \
        -e INPUT -e INPUT_KEYBOARD -e INPUT_MOUSEDEV \
      -e EFI -e EFI_STUB
    AR=ar NM=nm OBJCOPY=objcopy READELF=readelf STRIP=strip OBJDUMP=objdump \
      CC=clang-18 LD=ld.lld HOSTCC=clang-18 HOSTLD=ld.lld LLVM_IAS=1 \
      make O=/work/build-kernel-linux-arm64 ARCH="$ARCH" olddefconfig

    required_cfg=(
      CONFIG_PCI=y
      CONFIG_VIRTIO_PCI=y
      CONFIG_DRM=y
      CONFIG_DRM_VIRTIO_GPU=y
      CONFIG_DEVTMPFS=y
      CONFIG_DEVTMPFS_MOUNT=y
    )
    for cfg in "${required_cfg[@]}"; do
      if ! grep -q "^${cfg}$" /work/build-kernel-linux-arm64/.config; then
        echo "Missing required kernel option after olddefconfig: ${cfg}" >&2
        exit 1
      fi
    done

    echo "Kernel configuration complete. Building Image..."
    AR=ar NM=nm OBJCOPY=objcopy READELF=readelf STRIP=strip OBJDUMP=objdump \
      CC=clang-18 LD=ld.lld HOSTCC=clang-18 HOSTLD=ld.lld LLVM_IAS=1 \
      make O=/work/build-kernel-linux-arm64 ARCH="$ARCH" -j"$JOBS" Image
  '

echo "Kernel image ready at: $KERNEL_BUILD_DIR/arch/arm64/boot/Image"

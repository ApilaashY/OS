#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

KERNEL_VERSION="${KERNEL_VERSION:-6.12.38}"
WORKDIR="${WORKDIR:-$REPO_ROOT/linux-kernel}"
KERNEL_DIR="${KERNEL_DIR:-$WORKDIR/linux-${KERNEL_VERSION}}"
KERNEL_BUILD_DIR="${KERNEL_BUILD_DIR:-$REPO_ROOT/build-kernel-linux-amd64}"
ARCH="${ARCH:-x86_64}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
CLEAN_BUILD="${CLEAN_BUILD:-1}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-linux-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$REPO_ROOT/scripts/linux-toolchain.Dockerfile}"

ensure_image() {
  local image_platform
  image_platform="$(docker image inspect "$DOCKER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || true)"

  if [[ "$image_platform" != "$DOCKER_PLATFORM" ]]; then
    echo "Building Linux toolchain image..."
    docker buildx build --load --platform "$DOCKER_PLATFORM" -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$REPO_ROOT"

    image_platform="$(docker image inspect "$DOCKER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || true)"
    if [[ "$image_platform" != "$DOCKER_PLATFORM" ]]; then
      echo "Failed to make Docker image available locally as $DOCKER_PLATFORM: $DOCKER_IMAGE" >&2
      echo "Current image platform: ${image_platform:-missing}" >&2
      exit 1
    fi
  else
    echo "Using existing Docker image $DOCKER_IMAGE ($image_platform)."
  fi

  if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    echo "Failed to make Docker image available locally: $DOCKER_IMAGE" >&2
    exit 1
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

if [[ "$CLEAN_BUILD" == "1" ]]; then
  echo "Performing clean out-of-tree kernel build in: $KERNEL_BUILD_DIR"
  rm -rf "$KERNEL_BUILD_DIR"
fi
mkdir -p "$KERNEL_BUILD_DIR"

echo "Configuring and building kernel inside Linux container..."
echo "Using x86_64 platform for full kernel compilation compatibility."

# Build with x86_64 platform emulation
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
      /work/linux-kernel/linux-"$KERNEL_VERSION"/arch/x86/include/generated \
      /work/linux-kernel/linux-"$KERNEL_VERSION"/include/config \
      /work/linux-kernel/linux-"$KERNEL_VERSION"/include/generated

    AR=ar NM=nm OBJCOPY=objcopy READELF=readelf STRIP=strip OBJDUMP=objdump \
      CC=clang-18 LD=ld.lld HOSTCC=clang-18 HOSTLD=ld.lld LLVM_IAS=1 \
      make O=/work/build-kernel-linux-amd64 ARCH="$ARCH" defconfig
    # Options needed to boot both under QEMU (bochs) AND on real UEFI hardware
    # (simpledrm for the firmware framebuffer, USB HID for keyboards, and
    # devtmpfs so /dev/dri/card0 appears without udev).
    ./scripts/config --file /work/build-kernel-linux-amd64/.config \
        -e PCI -e PCI_MSI \
        -e DRM -e DRM_BOCHS -e DRM_SIMPLEDRM \
        -e VGA_CONSOLE -e FRAMEBUFFER_CONSOLE \
        -e DEVTMPFS -e DEVTMPFS_MOUNT \
        -e USB -e USB_XHCI_HCD -e USB_EHCI_HCD -e USB_OHCI_HCD \
        -e USB_HID -e HID_GENERIC \
        -e INPUT -e INPUT_KEYBOARD -e KEYBOARD_ATKBD \
      -e EFI -e EFI_STUB \
      -d DRM_I915 -d DRM_AMDGPU -d DRM_RADEON -d DRM_NOUVEAU
    AR=ar NM=nm OBJCOPY=objcopy READELF=readelf STRIP=strip OBJDUMP=objdump \
      CC=clang-18 LD=ld.lld HOSTCC=clang-18 HOSTLD=ld.lld LLVM_IAS=1 \
      make O=/work/build-kernel-linux-amd64 ARCH="$ARCH" olddefconfig

    required_cfg=(
      CONFIG_PCI=y
      CONFIG_DRM=y
      CONFIG_DRM_BOCHS=y
      CONFIG_DRM_SIMPLEDRM=y
      "CONFIG_DRM_I915 is not set"
      CONFIG_DEVTMPFS=y
      CONFIG_DEVTMPFS_MOUNT=y
    )
    for cfg in "${required_cfg[@]}"; do
      if [[ "$cfg" == *" is not set" ]]; then
        if ! grep -q "^# ${cfg}$" /work/build-kernel-linux-amd64/.config; then
          echo "Missing required kernel option after olddefconfig: # ${cfg}" >&2
          exit 1
        fi
      elif ! grep -q "^${cfg}$" /work/build-kernel-linux-amd64/.config; then
        echo "Missing required kernel option after olddefconfig: ${cfg}" >&2
        exit 1
      fi
    done

    echo "Kernel configuration complete. Building bzImage..."
    echo "Building with full x86_64 platform support."
    AR=ar NM=nm OBJCOPY=objcopy READELF=readelf STRIP=strip OBJDUMP=objdump \
      CC=clang-18 LD=ld.lld HOSTCC=clang-18 HOSTLD=ld.lld LLVM_IAS=1 \
      make O=/work/build-kernel-linux-amd64 ARCH="$ARCH" -j"$JOBS" bzImage
  '

echo "Kernel image ready at: $KERNEL_BUILD_DIR/arch/${ARCH}/boot/bzImage"
echo "Note: Kernel built successfully using x86_64 platform emulation."

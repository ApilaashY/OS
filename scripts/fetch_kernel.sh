#!/usr/bin/env bash
set -euo pipefail

KERNEL_VERSION="${KERNEL_VERSION:-6.12.38}"
KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_TARBALL}"
WORKDIR="${WORKDIR:-$PWD/linux-kernel}"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [[ ! -d "linux-${KERNEL_VERSION}" ]]; then
  if [[ ! -f "$KERNEL_TARBALL" ]]; then
    echo "Downloading Linux kernel ${KERNEL_VERSION}..."
    curl -LO "$KERNEL_URL"
  fi
  echo "Extracting kernel source..."
  tar -xf "$KERNEL_TARBALL"
fi

echo "Kernel source ready at: $WORKDIR/linux-${KERNEL_VERSION}"
echo "Next: run scripts/build_kernel.sh from inside that source tree."

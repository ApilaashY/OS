#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
KERNEL_VERSION="${KERNEL_VERSION:-6.12.38}"
KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_TARBALL}"
WORKDIR="${WORKDIR:-$REPO_ROOT/linux-kernel}"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [[ ! -d "linux-${KERNEL_VERSION}" ]]; then
  if [[ ! -f "$KERNEL_TARBALL" ]]; then
    echo "Downloading Linux kernel ${KERNEL_VERSION}..."
    curl -fL --retry 3 -o "$KERNEL_TARBALL" "$KERNEL_URL"
  fi
  echo "Extracting kernel source..."
  tar -xf "$KERNEL_TARBALL"
fi

echo "Kernel source ready at: $WORKDIR/linux-${KERNEL_VERSION}"
echo "Next: run scripts/build_kernel.sh from inside that source tree."

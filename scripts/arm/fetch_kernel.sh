#!/usr/bin/env bash
set -euo pipefail

# Kernel source is architecture-independent (same tarball builds x86_64 or
# arm64 depending on ARCH passed to `make`), so this just delegates to the
# shared fetch script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../fetch_kernel.sh" "$@"

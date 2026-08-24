#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CERTIFICATE="${CERTIFICATE:-$REPO_ROOT/keys/secureboot/MOK.der}"

if [[ ! -f "$CERTIFICATE" ]]; then
  echo "Certificate not found: $CERTIFICATE" >&2
  echo "Create it first with scripts/build_iso.sh." >&2
  exit 1
fi

if ! command -v mokutil >/dev/null 2>&1; then
  echo "mokutil is required. On Ubuntu/Debian: sudo apt install mokutil" >&2
  exit 1
fi

echo "Enter a temporary one-time password for MokManager."
sudo mokutil --import "$CERTIFICATE"
echo "Reboot from the USB, select Enroll MOK in MokManager, and enter that password."
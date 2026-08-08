#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-linux}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-linux-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$REPO_ROOT/scripts/linux-toolchain.Dockerfile}"

ensure_image() {
  local image_platform
  image_platform="$(docker image inspect "$DOCKER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || true)"

  if [[ "$image_platform" != "$DOCKER_PLATFORM" ]]; then
    echo "Building Linux toolchain image..."
    docker buildx build --load --platform "$DOCKER_PLATFORM" -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$REPO_ROOT"
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to build a Linux shell binary on this host." >&2
  exit 1
fi

ensure_image

mkdir -p "$BUILD_DIR"

echo "Building shell inside Linux container..."
docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -v "$REPO_ROOT:/work" \
  -w /work \
  "$DOCKER_IMAGE" \
  bash -lc 'cmake -S /work -B /work/build-linux -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_CXX_STANDARD=23 && cmake --build /work/build-linux'

echo "Linux shell binary ready at: $BUILD_DIR/os"
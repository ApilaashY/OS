#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$PWD}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-linux}"
DOCKER_IMAGE="${DOCKER_IMAGE:-os-linux-toolchain:24.04}"
DOCKERFILE="${DOCKERFILE:-$REPO_ROOT/scripts/linux-toolchain.Dockerfile}"

ensure_image() {
  if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    echo "Building Linux toolchain image..."
    docker build -t "$DOCKER_IMAGE" -f "$DOCKERFILE" "$REPO_ROOT"
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
  -v "$REPO_ROOT:/work" \
  -w /work \
  "$DOCKER_IMAGE" \
  bash -lc 'cmake -S /work -B /work/build-linux -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_CXX_STANDARD=23 && cmake --build /work/build-linux'

echo "Linux shell binary ready at: $BUILD_DIR/os"
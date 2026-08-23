#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-arm64}"
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
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to build an arm64 shell binary on this host." >&2
  exit 1
fi

ensure_image

mkdir -p "$BUILD_DIR"

echo "Building shell inside arm64 Linux container..."
docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -v "$REPO_ROOT:/work" \
  -w /work \
  "$DOCKER_IMAGE" \
  bash -lc "cmake -S /work -B /work/$(basename "$BUILD_DIR") -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_CXX_STANDARD=23 && cmake --build /work/$(basename "$BUILD_DIR")"

echo "arm64 shell binary ready at: $BUILD_DIR/os"

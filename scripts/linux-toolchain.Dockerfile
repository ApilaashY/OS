FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Optional HTTP(S) proxy for apt during build; not persisted in the final image.
ARG http_proxy
ARG https_proxy
ARG no_proxy

# Install common packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc \
    bison \
    build-essential \
    ca-certificates \
    clang \
    clang-18 \
    clang-tools-18 \
    cmake \
    cpio \
    curl \
    dosfstools \
    dwarves \
    flex \
    git \
    grub-common \
    grub-pc-bin \
    grub-efi-amd64-bin \
        grub-efi-amd64-signed \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    lld \
    mtools \
    ninja-build \
        openssl \
    perl \
    pkg-config \
    python3 \
    rsync \
        sbsigntool \
        shim-signed \
    xorriso \
    xz-utils \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
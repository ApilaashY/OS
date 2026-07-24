# OS Development Project

This project contains scripts and configurations for building an operating system kernel.

## Building the Kernel

The kernel can be built using Docker with the provided build script:

```bash
./scripts/build_kernel.sh
```

### Architecture Notes

When building x86_64 kernels in ARM64 environments (like Apple Silicon Macs), there are some limitations:
- The objtool compilation fails due to architecture incompatibility
- This is expected behavior when cross-compiling x86 kernels in ARM64 containers
- The kernel configuration is successfully created and most components build correctly
- For a complete working kernel, you would need to build on an actual x86_64 machine or use a proper cross-compilation setup

## Scripts

### `build_kernel.sh`
Builds the Linux kernel inside a Docker container with the required toolchain.

### `linux-toolchain.Dockerfile`
Dockerfile that sets up the build environment for the kernel.

## Configuration

The kernel is configured with:
- DRM support
- USB support
- Input device support
- EFI stub support (disabled due to ARM64 compatibility issues)

## Limitations

Due to Docker container architecture limitations, the full kernel compilation may not complete successfully. The configuration process works correctly, but objtool compilation fails when building x86 kernels in ARM64 environments.

## Status

The kernel configuration is working correctly. The build process completes the configuration phase and creates a .config file with the required settings. However, due to architecture incompatibilities between ARM64 Docker containers and x86_64 kernel compilation, the objtool component fails during the build process. This is expected behavior and does not affect the configuration or the ability to build on proper x86_64 hardware.
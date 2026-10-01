# os

**A tiny graphical operating-system experiment, built in C++ and booted as the first userspace process.**

`os` is a Linux userspace desktop prototype that takes the display from kernel boot and draws directly to it. It brings up a DRM/KMS framebuffer, paints a desktop, opens a window, and listens to Linux input events for pointer movement and dragging. The result is a compact, hands-on place to explore the boundary between a Linux kernel and a graphical userspace.

This is not a new kernel or a finished general-purpose desktop. The project builds a regular Linux executable and boots it as `/init` inside a small initramfs, with a separately built Linux kernel providing hardware drivers, scheduling, and the DRM and input interfaces.

## Why This Project

Most desktop applications begin inside an existing window system. This project starts lower: its process opens the Linux Direct Rendering Manager device itself, chooses a connected display mode, maps scanout buffers, and asks the kernel to flip frames. There is no X11 or Wayland session between the program and the display.

That small scope makes the code useful as an approachable systems project: the visible result is immediate, while the path from kernel device interfaces to pixels and pointer events stays inspectable in C++.

## What It Does Today

- Boots a Linux kernel and launches the project as the initramfs `/init` process.
- Finds a connected DRM display and uses its preferred mode.
- Allocates two CPU-mapped DRM dumb buffers and presents updates using page-flip events.
- Draws a desktop background, a window, its title bar, and a mouse pointer.
- Reads relative and absolute pointer events from Linux evdev devices under `/dev/input/event*`.
- Routes clicks to the topmost window and drags that start in a window's title bar to move it.
- Builds Linux x86_64 and ARM64 artifacts, with QEMU boot scripts for both targets.
- Produces an x86_64 UEFI ISO with a Secure Boot enrollment flow, and an ARM64 EFI ISO for testing with suitable firmware.

The current scene is deliberately small: one window with a basic white application surface and a colored title bar. Clicks are dispatched, but there are not yet interactive controls, applications, keyboard navigation, window close/minimize controls, storage, networking, or a command shell. This is a working foundation and bootable demo, not a daily-use operating system.

## How It Fits Together

```text
UEFI or QEMU
    -> Linux kernel (DRM, display, and input drivers)
        -> initramfs: /init (this project's C++ executable)
            -> Graphics: DRM/KMS modesetting, mapped buffers, page flips
            -> Desktop: windows, redraws, and pointer-event routing
                -> Window -> Application -> Screen
            -> Mouse: Linux evdev input events
```

The executable uses Linux userspace APIs and the C++ standard library. The Linux kernel remains a separate, unmodified upstream kernel configured by the build scripts; this repository does not compile its C++ sources into the kernel.

### Main Modules

| Module                                                                      | Role                                                                                                      |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| [`main.cpp`](main.cpp)                                                      | Starts graphics, creates the desktop and initial window, then enters the mouse-event loop.                |
| [`graphics/`](graphics/)                                                    | Selects a DRM connector and mode, creates double buffers, draws primitives, and presents frames.          |
| [`desktop/`](desktop/)                                                      | Owns the desktop's window list and redraws windows and the pointer.                                       |
| [`window/`](window/)                                                        | Renders a title bar and application surface; supports dragging from the title-bar region.                 |
| [`application/`](application/) and [`component/screen/`](component/screen/) | Provide the current application/screen rendering layer.                                                   |
| [`mouse/`](mouse/)                                                          | Probes evdev nodes, reads relative/absolute movement and button events, and forwards them to the desktop. |
| [`component/`](component/) and [`point/`](point/)                           | Shared component event types, points, and rectangular hit-testing helpers.                                |
| [`scripts/`](scripts/)                                                      | Docker-based Linux builds, kernel configuration, initramfs packaging, QEMU boot, and ISO creation.        |

## Run It in QEMU

The fastest route on a macOS or Linux development machine is to build the Linux guest executable with Docker, build the matching kernel, and boot both in QEMU. The scripts create the initramfs and attach a virtual pointer device.

### x86_64

Prerequisites: Docker with Buildx, `qemu-system-x86_64`, and enough disk space for a Linux kernel source tree and build output. On macOS, install QEMU with `brew install qemu`. Docker Desktop works as the Linux build environment; the x86_64 container/kernel toolchain may use emulation on Apple Silicon.

From the repository root:

```bash
./scripts/build_shell.sh
./scripts/fetch_kernel.sh
./scripts/build_kernel.sh
./scripts/boot_qemu.sh
```

The first script builds the C++23 Linux executable at `build-linux/os`. Kernel source defaults to Linux `6.12.38` under `linux-kernel/`; the out-of-tree x86_64 kernel build is placed in `build-kernel-linux-amd64/`. `boot_qemu.sh` packages the executable and its shared libraries into `initramfs.cpio.gz` and launches a 512 MiB x86_64 VM with a virtual USB tablet and display.

The scripts build their Ubuntu 24.04 Docker toolchain image on first use. Kernel compilation can take a while and uses `JOBS` workers (default: 2). For example:

```bash
JOBS=6 ./scripts/build_kernel.sh
QEMU_DISPLAY_RES=1600x900 ./scripts/boot_qemu.sh
QEMU_HEADLESS=1 ./scripts/boot_qemu.sh
```

The headless option sends the guest serial console to the terminal; it is useful for boot diagnostics, not for viewing the graphical desktop. `QEMU_DAEMONIZE=1` starts the VM in the background and writes its serial output to `qemu-serial.log` by default.

### ARM64

The ARM64 scripts build a separate guest executable, kernel, and initramfs. QEMU uses its `virt` machine with VirtIO graphics and input devices. Install `qemu-system-aarch64` (on macOS, `brew install qemu`), then run:

```bash
./scripts/arm/build_shell.sh
./scripts/arm/fetch_kernel.sh
./scripts/arm/build_kernel.sh
./scripts/arm/boot_qemu.sh
```

Artifacts are kept separate from x86_64: the executable is `build-arm64/os`, the kernel build is `build-kernel-linux-arm64/`, and the initramfs is `initramfs-arm64.cpio.gz`. The ARM64 container uses the `linux/arm64` platform; on a non-ARM64 host Docker may need CPU emulation. ARM64 QEMU defaults to the `virt` machine and a `virtio-mouse-pci` pointer.

## Build the Executable

The project requires CMake 3.28 or newer, a C++23-capable compiler, Ninja, and Linux DRM UAPI headers. On a Linux development system with those dependencies installed, use the included preset:

```bash
cmake --preset default
cmake --build --preset default
```

This creates `build/os`. The preset uses Ninja and a Debug configuration. The executable depends on Linux interfaces such as DRM/KMS and evdev, so a native macOS build is not a way to run the desktop; use `scripts/build_shell.sh` to produce the Linux guest binary from macOS.

## Create Bootable ISOs

### x86_64 UEFI ISO

Build the shell and fetch the kernel source first, then run:

```bash
./scripts/build_shell.sh
./scripts/fetch_kernel.sh
./scripts/build_iso.sh
```

`build_iso.sh` builds the kernel and packages the initramfs when those expected artifacts are missing. The resulting image is `build/os-live.iso`; it contains GRUB, the Linux kernel, and the initramfs. Write the ISO to removable media with an imaging tool appropriate for your system. Booting real hardware depends on that hardware's firmware and graphics/input drivers; QEMU is the reference path for the configured virtual devices.

#### Secure Boot

The x86_64 ISO uses a Microsoft-trusted shim and Canonical-signed GRUB. The project kernel is signed with a project-local Machine Owner Key (MOK), which must be enrolled in the target machine's UEFI trust database before Secure Boot will accept it. Secure Boot remains enabled; this is not a promise that the ISO boots without an enrollment step.

1. Build the ISO. The signing key and certificate are created under `keys/secureboot/`.
2. Keep `keys/secureboot/MOK.key` private. It is the signing key for future kernels built with this setup; do not share it or commit it.
3. On the Linux installation that will enroll the key, install `mokutil` if needed and run `./scripts/enroll_secureboot_key.sh`.
4. Choose a temporary enrollment password when prompted, then reboot. In MokManager, select **Enroll MOK**, confirm, and enter that password.
5. Reboot and select the USB/ISO again. Future kernels signed by the same key can use the enrolled certificate.

The enrollment helper requires `mokutil` and `sudo` on Linux. Creating the ISO inside Docker does not perform enrollment on the target computer.

### ARM64 EFI ISO

After building the ARM64 shell and fetching the kernel source, run:

```bash
./scripts/arm/build_shell.sh
./scripts/arm/fetch_kernel.sh
./scripts/arm/build_iso.sh
```

The output is `build/os-live-arm64.iso`. This is an EFI ISO, not the x86_64 Secure Boot image. Booting it in QEMU requires ARM64 UEFI firmware such as AAVMF/EDK2; for the simplest QEMU run, `scripts/arm/boot_qemu.sh` boots the ARM64 kernel image directly and does not need firmware.

## Build and Output Reference

| Script                        | Purpose                                                                     | Default output                                      |
| ----------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------- |
| `scripts/build_shell.sh`      | Build the Linux x86_64 C++ executable in the Ubuntu Docker toolchain.       | `build-linux/os`                                    |
| `scripts/fetch_kernel.sh`     | Download and extract the configured upstream Linux kernel source.           | `linux-kernel/linux-6.12.38/`                       |
| `scripts/build_kernel.sh`     | Configure and compile the x86_64 kernel with virtual display/input support. | `build-kernel-linux-amd64/arch/x86_64/boot/bzImage` |
| `scripts/boot_qemu.sh`        | Package x86_64 initramfs and boot the guest.                                | `initramfs.cpio.gz`                                 |
| `scripts/build_iso.sh`        | Assemble the x86_64 Secure Boot-capable UEFI ISO.                           | `build/os-live.iso`                                 |
| `scripts/arm/build_shell.sh`  | Build the ARM64 Linux C++ executable.                                       | `build-arm64/os`                                    |
| `scripts/arm/build_kernel.sh` | Configure and compile the ARM64 kernel for QEMU VirtIO devices.             | `build-kernel-linux-arm64/arch/arm64/boot/Image`    |
| `scripts/arm/boot_qemu.sh`    | Package ARM64 initramfs and boot the guest.                                 | `initramfs-arm64.cpio.gz`                           |
| `scripts/arm/build_iso.sh`    | Assemble an ARM64 EFI ISO.                                                  | `build/os-live-arm64.iso`                           |

The kernel fetch and build scripts accept `KERNEL_VERSION`, `WORKDIR`, and `JOBS` overrides. The QEMU scripts accept `QEMU_BIN`, `QEMU_DISPLAY_RES`, `QEMU_HEADLESS`, and `QEMU_DAEMONIZE`; the build scripts also expose paths and Docker image/platform settings through environment variables. See the script defaults near the top of each file for the complete list.

## Project Status and Boundaries

- **Operating-system model:** Linux kernel plus this project as a first userspace process. Kernel internals are not reimplemented here.
- **Display:** Direct DRM/KMS modesetting and double-buffered drawing; currently targets the first usable display path exposed by the configured guest.
- **Input:** Linux evdev mouse/tablet events. The implementation probes a finite set of `/dev/input/event*` nodes.
- **User interface:** A desktop surface, one basic window, pointer rendering, click dispatch, and title-bar dragging. Window stacking exists for drawing/hit-testing; full focus and window-management interactions do not.
- **Applications:** A minimal `Application`/`Screen` rendering structure, not a launcher or a suite of usable apps.
- **Testing:** No automated test suite is currently configured in CMake. QEMU booting is the practical end-to-end check.
- **Hardware:** The supplied kernels are configured for QEMU's Bochs/VirtIO graphics and input paths, plus firmware framebuffer support on x86_64. Broader physical-hardware compatibility is not guaranteed.

## Contributing

Keep changes focused on the current Linux userspace architecture. For rendering or input changes, build the target executable and, when available, boot the corresponding QEMU guest to check the visible behavior. The x86_64 and ARM64 toolchains and generated artifacts are intentionally separated; use the matching script family for each target.

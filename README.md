# os

A small C++ shell project intended to run as a Linux userspace program.
It is not a Linux kernel component. If you want to use it with QEMU, boot a
Linux kernel and run this shell from an initramfs or as a normal userspace
binary.

## What works in this setup

The current code uses normal Linux userspace APIs such as `fork`, `execvp`,
`waitpid`, `chdir`, `std::string`, and standard I/O. Those are fine for a
Linux userspace shell.

What does not apply here is compiling the project _into_ the Linux kernel.
That would require a full kernel rewrite with Linux kernel APIs and no libc.

## Build

Use Docker to build Linux artifacts for the QEMU guest.

```bash
./scripts/build_shell.sh
./scripts/build_kernel.sh
```

## QEMU usage

Typical flow:

1. Build the shell for Linux userspace.
2. Create an initramfs containing the binary as `/init`.
3. Boot a Linux kernel in QEMU and point it at that initramfs.

The shell can then be the first userspace process.

## Bootable ISO usage

To create a bootable ISO image that can be flashed to a USB drive with tools such as Rufus, run:

```bash
./scripts/build_iso.sh
```

This produces an ISO at `build/os-live.iso` that boots the kernel and initramfs with GRUB.

### Secure Boot enrollment

The ISO uses Microsoft-signed shim and Canonical-signed GRUB, so it works with
standard UEFI Secure Boot and does not require changing BIOS settings. The
project's kernel is signed with a local Machine Owner Key (MOK), which needs a
single enrollment from the Linux system you build on:

1. Build the ISO with `./scripts/build_iso.sh`. This generates the persistent
    key and certificate under `keys/secureboot/`; do not delete or share
    `MOK.key`.
2. Run `./scripts/enroll_secureboot_key.sh` on the machine where you will boot
    the USB. It asks for a temporary enrollment password.
3. Reboot directly from the USB. MokManager appears before the OS starts.
    Choose **Enroll MOK**, then **Continue**, **Yes**, and enter the temporary
    password. It reboots automatically.
4. Boot the USB again. The MOK is now stored in the machine's Secure Boot
    database, so all future ISOs built with this same key boot normally.

This one-time enrollment is required by Secure Boot; it is the authorization
that lets the firmware trust your own kernel without disabling Secure Boot.

### Helper scripts

- `scripts/fetch_kernel.sh` downloads and extracts a Linux kernel source tree.
- `scripts/build_shell.sh` builds a Linux ELF version of the shell inside Docker.
- `scripts/build_kernel.sh` builds a `bzImage` from that source tree.
- `scripts/boot_qemu.sh` packages the shell into an initramfs and boots QEMU.
- `scripts/build_iso.sh` packages the shell into an initramfs and creates a bootable ISO image.

These scripts assume Docker and an x86_64 QEMU guest.

## Libraries and code to keep/remove

Keep:

- `<iostream>`
- `<unistd.h>`
- `<sys/wait.h>`

Remove only if you rewrite the project as kernel code:

- `fork`
- `execvp`
- `waitpid`
- `chdir`
- all standard C++ I/O and STL usage

## Project structure

```
os/
├── CMakeLists.txt
├── CMakePresets.json
├── main.cpp
└── string_helpers/
    ├── string_helpers.cppm
    └── string_helpers.cpp
```

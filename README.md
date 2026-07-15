# os

A simple shell/OS project written in C++23, using C++ modules.

## Requirements

| Tool | Minimum Version | Notes |
|------|----------------|-------|
| CMake | 3.28+ | Required for `FILE_SET CXX_MODULES` support |
| Ninja | any | Used as the build generator |
| Clang | 17+ **or** GCC 14+ | Needed for C++23 module support |

### macOS — install dependencies via Homebrew

```bash
brew install cmake ninja llvm
```

> After installing LLVM via Homebrew, make sure `clang++` from Homebrew is on your `PATH`:
> ```bash
> export PATH="$(brew --prefix llvm)/bin:$PATH"
> ```
> Add this to your `~/.zshrc` to make it permanent.

---

## Building

### 1. Configure

```bash
cmake --preset default
```

This creates a `build/` directory, selects the Ninja generator, and sets the build type to `Debug`. It also generates `build/compile_commands.json` for IntelliSense / clangd.

### 2. Compile

```bash
cmake --build --preset default
```

The compiled binary will be at `build/os`.

### One-liner

```bash
cmake --preset default && cmake --build --preset default
```

---

## Running

```bash
./build/os
```

The shell reads lines from stdin and splits them into arguments. Type your input and press Enter.

---

## IntelliSense / clangd setup

After a successful configure step, `build/compile_commands.json` is generated automatically. Most editors pick this up without extra configuration:

- **VS Code** (clangd extension): add to `.vscode/settings.json`:
  ```json
  {
    "clangd.arguments": ["--compile-commands-dir=${workspaceFolder}/build"]
  }
  ```
- **CLion**: automatically detects `compile_commands.json` from the CMake build directory.
- **Neovim** (clangd via LSP): points to the `build/` folder by default when using `cmake-tools`.

---

## Project Structure

```
os/
├── CMakeLists.txt              # Build definition (C++23 + modules)
├── CMakePresets.json           # Build presets (Ninja, Debug, compile_commands)
├── main.cpp                    # Entry point
└── string_helpers/
    ├── string_helpers.cppm     # Module interface unit (export module)
    └── string_helpers.cpp      # Module implementation unit
```

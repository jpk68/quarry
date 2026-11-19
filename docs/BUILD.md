# Build instructions

> [!WARNING]
> This software is largely a work-in-progress; builds may fail at this time.

## Prerequisites

Building requires [Zig](https://ziglang.org/download/) 0.17 or newer and `libzmq`.

Follow [these instructions](https://ziglang.org/learn/getting-started/) to download Zig, and use the appropriate command below to install the needed libraries for your platform.

### Debian/Ubuntu

```bash
sudo apt install libzmq3-dev
```

### Arch/Artix

```bash
sudo pacman -S zeromq --needed
```

### macOS (Homebrew)

```bash
brew install zig zeromq
```

Homebrew's `zig` package can be used in place of the download linked above.

## Build steps

```bash
git clone https://github.com/jpk68/quarry
cd quarry
zig build
```

The above instructions will compile for the `debug` release mode. See [this page](https://zig.guide/build-system/build-modes/) for more information.

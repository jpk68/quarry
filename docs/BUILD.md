# Build instructions

> [!WARNING]
> This software is largely a work-in-progress; builds may fail at this time.

## Prerequisites

Building requires the latest release of [Zig master](https://ziglang.org/download/) and `libzmq`.

Follow [these instructions](https://ziglang.org/learn/getting-started/) to download Zig, and use the appropriate command below to install the needed libraries for your platform.

### Debian/Ubuntu
```bash
sudo apt install libzmq3-dev
```

### Arch
```bash
sudo pacman -S zeromq --needed
```

## Build steps

```bash
git clone https://codeberg.org/jpk68/quarry
cd quarry
make
```

The above instructions will compile for the `debug` release mode. See [this page](https://zig.guide/build-system/build-modes/) for more information.

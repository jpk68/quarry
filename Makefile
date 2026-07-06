.PHONY: all debug run test release fmt clean

all: debug

debug:
	zig build --summary all

run:
	zig build run

test:
	zig build test --summary all

release:
	zig build --release=safe -Duse-llvm=true -Dfmt-check=true --summary all

fmt:
	zig fmt .

clean:
	rm -rf .zig-cache/ zig-out/
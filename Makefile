all: debug

debug:
	zig build

release:
	zig build --release=fast

run:
	zig build run

test:
	zig build test

fmt:
	zig build fmt

clean:
	rm -rf .zig-cache .zig-pkg zig-out

all: debug

debug:
	zig build

release:
	zig build --release=fast

fmt:
	zig build fmt

clean:
	rm -rf .zig-cache .zig-pkg zig-out

run: debug
	./zig-out/bin/quarry

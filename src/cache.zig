//! Logic for managing the sidechain's block cache.

const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const block_size: u64 = 96 * 1024;
const block_count: u64 = 4608;
const cache_size: u64 = block_size * block_count;

const cache_file_name = "p2pool_cache.bin";

pub const BlockCache = struct {
    allocator: Allocator,
    io: Io,

    file: Io.File,
    map: Io.File.MemoryMap,

    pub fn init(allocator: Allocator, io: Io, dir: Io.Dir) !*BlockCache {
        const self = try allocator.create(BlockCache);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.io = io;

        self.file = dir.openFile(self.io, cache_file_name, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => try dir.createFile(self.io, cache_file_name, .{ .read = true }),
            else => return err,
        };
        errdefer self.file.close(self.io);

        self.map = try self.file.createMemoryMap(self.io, .{ .len = cache_size });
        errdefer self.map.destroy(self.io);

        return self;
    }

    pub fn deinit(self: *BlockCache) void {
        defer self.allocator.destroy(self);

        // Destroy the file's memory map before the file itself
        self.map.destroy(self.io);
        self.file.close(self.io);
    }
};

test "create and destroy cache" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const cwd = Io.Dir.cwd();

    const cache = try BlockCache.init(allocator, io, cwd);
    defer cache.deinit();
}

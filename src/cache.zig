const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const block_size: u64 = 96 * 1024;
const block_count: u64 = 4608;
const cache_size: u64 = block_size * block_count;

const cache_file_name: []const u8 = "p2pool_cache.bin";

pub const BlockCache = struct {
    allocator: Allocator,
    io: Io,

    file: Io.File,
    map: Io.File.MemoryMap,

    pub fn init(allocator: Allocator, io: Io, dir: Io.Dir) !BlockCache {
        const self = try allocator.create(BlockCache);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.io = io;

        self.file = try dir.openFile(self.io, cache_file_name, .{ .mode = .read_write }) catch |err| switch (err) {
            .FileNotFound => try dir.createFile(self.io, cache_file_name, .{ .read = true }),
            else => return err,
        };
        errdefer self.file.close(self.io);

        self.map = try self.file.createMemoryMap(self.io, .{ .len = cache_size });
        errdefer self.map.close(self.io);
    }

    pub fn deinit(self: *BlockCache) void {
        defer self.allocator.destroy(self);

        self.map.close(self.io);
        self.file.close(self.io);
    }
};

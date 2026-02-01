const std = @import("std");
const Io = std.Io;

pub const BlockCache = struct {
    io: Io,
    path: Io.Dir,

    pub fn init(io: Io, path: Io.Dir) BlockCache {
        return .{
            .io = io,
            .path = path,
        };
    }

    pub fn saveData(self: *BlockCache, data: []const u8) !void {
        const file = try self.path.createFile(self.io, "p2pool_cache", .{});
        defer file.close(self.io);

        try file.writeAll(self.io, data);
        std.log.debug("Finished writing data to cache file", .{});
    }
};

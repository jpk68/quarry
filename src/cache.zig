const std = @import("std");
const Io = std.Io;

pub const BlockCache = struct {
    io: Io,
    file: ?Io.File,
    file_size: ?usize,

    pub fn init(io: Io, dir: Io.Dir) !BlockCache {
        return .{
            .io = io,
            .file = null,
            .file_size = null,
        };
    }

    pub fn saveData(self: *BlockCache, data: []const u8) !void {
        try self.file.writeAll(self.io, data);
        std.log.debug("Finished writing data to cache file", .{});
    }
};

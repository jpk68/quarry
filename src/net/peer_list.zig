const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const max_file_size: usize = 4096;
const file_name = "p2pool_peers.txt";

pub const PeerList = struct {
    peers: std.ArrayList([]const u8) = .empty,

    pub fn init(io: Io, allocator: Allocator, dir: Io.Dir) !PeerList {
        var file = dir.openFile(io, file_name, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => try dir.createFile(io, file_name, .{ .read = true }),
            else => return err,
        };
        defer file.close(io);

        var buf: [max_file_size]u8 = undefined;

        var reader = file.reader(io, &.{});
        const bytes_read = reader.interface.readSliceShort(&buf) catch |err| switch (err) {
            error.ReadFailed => return reader.err.?,
        };
        const contents = buf[0..bytes_read];

        var list: std.ArrayList([]const u8) = .empty;

        var tok = std.mem.tokenizeSequence(u8, contents, "\n");
        while (tok.next()) |line| {
            const slice = try allocator.dupe(u8, line);
            try list.append(allocator, slice);
        }

        return .{ .peers = list };
    }

    pub fn deinit(self: *PeerList, allocator: Allocator) void {
        for (self.peers.items) |item| allocator.free(item);
        self.peers.deinit(allocator);
    }
};

test "load peer list" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const dir = Io.Dir.cwd();

    var list = try PeerList.init(io, alloc, dir);
    defer list.deinit(alloc);

    std.debug.print("{any}\n", .{list});
}

const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const PeerList = std.ArrayList([]const u8);

const max_file_size: usize = 4096;
const file_name = "p2pool_peers.txt";

pub fn loadPeerListFile(io: Io, allocator: Allocator, dir: Io.Dir) !PeerList {
    var buf: [max_file_size]u8 = undefined;
    const contents = try Io.Dir.readFile(dir, io, file_name, &buf);

    var list: PeerList = .empty;

    var tok = std.mem.tokenizeSequence(u8, contents, "\n");
    while (tok.next()) |line| {
        try list.append(allocator, line);
    }

    return list;
}

test "load peer list" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const dir = Io.Dir.cwd();

    const list = try loadPeerListFile(io, alloc, dir);

    std.debug.print("{any}\n", .{list});
}

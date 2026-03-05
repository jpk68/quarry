const std = @import("std");

const common = @import("../common.zig");
const Client = @import("Client.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;
const log = std.log.scoped(.server);

const peer_ban_time = 600;
const peer_request_delay = 60;

const seed_nodes_clearnet = [][]const u8{
    "seeds.p2pool.io",
    "main.p2poolpeers.net",
};

// TODO
// Version info
// Ban list entries
// Make tests for everything
// Proxy support
// Use a less stupid allocation strategy
// Get rid of 'orelse panic' stuff

const Server = @This();

allocator: Allocator,
io: Io,
info: ServerInfo,

client_list: std.DoublyLinkedList(*Client) = .{},
client_lock: std.Mutex = .init,

peer_list: std.ArrayList(Peer),
peer_lock: std.Mutex = .init,

const ServerInfo = struct {
    /// This server's clearnet peer ID.
    peer_id: u64 = undefined,
    max_peers_outgoing: u32,
    max_peers_incoming: u32,
    /// The P2Pool sidechain being used.
    sidechain_type: common.SidechainType,
    /// Directory for storing cache files.
    data_dir: Io.Dir,
};

pub const Peer = struct {
    addr: []const u8,
    port: u16,
    failed_connections: u32,
    last_seen_timestamp: u64,
};

pub fn run(self: *Server) !void {
    // Initialize PRNG and obtain its interface. Uses Xoshiro256 by default.
    const rand_inst: std.Random.IoSource = .{ .io = self.io };
    const rand: std.Random = rand_inst.interface();

    // Set peer_id to a random u64
    self.info.peer_id = rand.int(u64);

    log.debug("Set random server ID: {d}", .{self.info.peer_id});

    const port = @as(u16, switch (self.info.sidechain_type) {
        .main => 37889,
        .mini => 37888,
        .nano => 37890,
    });
    const host = try net.IpAddress.parse("127.0.0.1", port);

    var tcp = try net.IpAddress.listen(host, self.io, .{});
    defer tcp.deinit(self.io);

    log.info("Listening on port {d}", .{port});

    var client_group: Io.Group = .init;
    defer client_group.cancel(self.io);

    while (true) {
        const stream = try tcp.accept(self.io);
        errdefer stream.close(self.io);

        log.debug("Accepted connection", .{});

        try client_group.concurrent(self.io, handleClient, .{ self.io, stream });
    }
}

fn registerPeer(self: *Server, peer: Peer) !void {
    try self.peer_lock.lock(self.io);
    defer self.peer_lock.unlock(self.io);
    try self.peer_list.append(self.allocator, peer);
}

fn loadSavedPeers(self: *Server) !void {
    // Saved peer lists are stored in separate files, depending on the P2Pool sidechain.
    const file_name = "p2pool_peers_" ++ @tagName(self.info.sidechain_type) ++ ".txt";

    // Dynamically-sized array to hold IP/port slices.
    var list: std.ArrayList([]const u8) = .empty;

    // Open the peer list file in read-only mode.
    const file = try self.info.data_dir.openFile(self.io, file_name, .{ .mode = .read_only });
    defer file.close(self.io);

    const read_buf = try self.allocator.alloc(u8, 4096);
    defer self.allocator.free(read_buf);

    var reader_inst = file.reader(self.io, read_buf);
    const reader = &reader_inst.interface;

    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(self.allocator);

    // Read file to the end; handle EOF and newline characters.
    // Each line is appended to the list of IP/port combinations.
    while (true) {
        var byte: [1]u8 = undefined;
        const n = try reader.readSliceShort(&byte);

        if (n == 0) {
            if (line_buf.items.len > 0) {
                const trimmed = std.mem.trim(u8, line_buf.items, " \r\n\t");
                if (trimmed.len > 0) {
                    const copy = try self.allocator.dupe(u8, trimmed);
                    try list.append(copy);
                }
            }
            break;
        }

        if (byte[0] == '\n') {
            const trimmed = std.mem.trim(u8, line_buf.items, " \r\n\t");
            if (trimmed.len > 0) {
                const copy = try self.allocator.dupe(u8, trimmed);
                try list.append(copy);
            }
            line_buf.clearRetainingCapacity();
        } else {
            try line_buf.append(byte[0]);
        }
    }

    return list;
}

fn handleConnection(self: *Server, stream: net.Stream) !void {
    defer stream.close(self.io);

    const clock: Io.Clock = .real;
    const buf_size: usize = 1024;

    var writer_buf: [buf_size]u8 = undefined;
    var writer_inst = stream.writer(self.io, &writer_buf);
    const writer = &writer_inst.interface;

    var reader_buf: [buf_size]u8 = undefined;
    var reader_inst = stream.reader(self.io, &reader_buf);
    const reader = &reader_inst.interface;

    var queue_buf: [buf_size]u8 = undefined;
    var recv_queue: Io.Queue(u8) = .init(&queue_buf);
    defer recv_queue.close(self.io);

    var client = Client.init();
    defer client.deinit();
    defer self.removeClient(self.io);

    _ = try writer.write("TEST");
    _ = reader;
    _ = clock;
}

const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

const common = @import("../common.zig");
const Client = @import("Client.zig");
const Server = @This();

const peer_ban_time: u64 = 600;
const peer_request_delay: u64 = 60;

const seed_nodes_clearnet = [_][]const u8{
    "seeds.p2pool.io",
    "main.p2poolpeers.net",
};

// TODO
// Version info
// Ban list entries

allocator: Allocator,
io: Io,
info: ServerInfo,
peer_list: std.SinglyLinkedList = .{},

pub const PeerInfo = struct {
    host: net.IpAddress,
    failed_connections: u32,
    last_seen_timestamp: u64,
};

const ServerInfo = struct {
    /// This server's clearnet peer ID.
    peer_id: u64,
    /// Maximum number of incoming/outgoing peers.
    /// Defaults are specified in the config file.
    max_peers_outgoing: u32,
    max_peers_incoming: u32,
    sidechain_type: common.SidechainType,
    data_dir_path: ?[]const u8,
};

pub fn start(self: *Server) !void {
    const rand_io: std.Random.IoSource = .{ .io = self.io };
    const rand: std.Random = rand_io.interface();
    self.info.peer_id = rand.int(u64);

    std.log.debug("Set random server ID: {d}", .{self.info.peer_id});

    const port = @as(u16, switch (self.info.sidechain_type) {
        .main => 37889,
        .mini => 37888,
        .nano => 37890,
    });
    const addr = try net.IpAddress.parse("127.0.0.1", port);

    var tcp = try net.IpAddress.listen(addr, self.io, .{});
    defer tcp.deinit(self.io);

    var client_group: Io.Group = .init;
    defer client_group.cancel(self.io);

    std.log.debug("Server listening on port {d}", .{port});

    while (true) {
        std.log.debug("Attempting to accept client", .{});
        const stream = try tcp.accept(self.io);
        std.log.debug("Accepted connection", .{});

        var future = client_group.concurrent(self.io, handleConnection, .{
            self.io,
            stream,
        }) catch {
            std.log.err("Failed to start concurrent handler for connection", .{});
            stream.close(self.io);
        };
    }
}

fn loadPeersFromFile(self: *Server) !void {
    const file_name = "p2pool_peers_" ++ @tagName(self.info.sidechain_type) ++ ".txt";

    const file = try Io.Dir.cwd().createFile(self.io, file_name, .{ .read = true });
    defer file.close(self.io);

    var buf: [1024]u8 = undefined;
    var w = file.writer(self.io, buf);
    const writer = &w.interface;

    var i: usize = 0;

    for (peers) |peer| {
        try self.peer_list.append(self.allocator, peer);
    }
}

fn handleConnection(self: *Server, stream: net.Stream) !void {
    defer stream.close(self.io);

    const clock: Io.Clock = .real;
    const buf_size: usize = 1024;

    var write_buf: [buf_size]u8 = undefined;
    var writer = stream.writer(self.io, write_buf);
    const out = &writer.interface;

    var read_buf: [buf_size]u8 = undefined;
    var reader = stream.reader(self.io, read_buf);
    const in = &reader.interface;

    var queue_buf: [buf_size]u8 = undefined;
    var recv_queue: Io.Queue(u8) = .init(queue_buf);
    defer recv_queue.close(self.io);

    var client = Client.init();
    defer client.deinit();
    defer self.removeClient(self.io);

    _ = try out.write("TEST");
}

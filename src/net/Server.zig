const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

const Client = @import("Client.zig");
const Server = @This();

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
};

pub fn run(self: *Server) !void {
    const rand_io: std.Random.IoSource = .{ .io = self.io };
    const rand: std.Random = rand_io.interface();
    self.info.peer_id = rand.int(u64);

    std.log.debug("Set random server ID: {d}", .{self.info.peer_id});

    const port = @as(u16, switch (self.config.sidechain_type) {
        .main => 37889,
        .mini => 37888,
        .nano => 37890,
    });

    const addr = try net.IpAddress.parse("127.0.0.1", port);
    var tcp = try net.IpAddress.listen(addr, self.io, .{});

    var client_group: Io.Group = .init;
    defer client_group.cancel(self.io);

    std.log.debug("Server listening on port {d}", .{port});

    while (true) {
        std.log.debug("Attempting to accept client", .{});
        const stream = try tcp.accept(self.io);
        std.log.debug("Accepted connection", .{});

        _ = client_group.async(self.io, handleConnection, .{ self.io, stream });
    }
}

pub fn handleConnection(self: *Server, stream: *net.Stream) !void {
    defer stream.close(self.io);

    const clock: Io.Clock = .real;

    // TODO
    const write_buf: []u8 = undefined;

    //var client = Client.init(null, &recv_queue, in, out);

    var client_task = try self.io.concurrent();
}

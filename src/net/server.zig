const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = std.Io.net;

const log = std.log.scoped(.server);

const PeerInfo = struct {
    host: net.IpAddress,
    failed_connection_count: usize,
    last_seen_timestamp: u64,
};

const BanInfo = struct {
    expiration_timestamp: u64,
};

fn handlePeer(self: *Server, stream: net.Stream) void {
    log.info("Accepted connection from {}", .{stream.socket.address});

    const entry = PeerInfo{
        .host = stream.socket.address,
        .failed_connection_count = 0,
        .last_seen_timestamp = 0,
    };

    self.peer_list.append(self.allocator, entry) catch {};

    log.debug("Current peer list: {}", .{self.peer_list});
}

pub const Server = struct {
    allocator: Allocator,
    io: Io,

    peer_id: u64,
    num_connections: usize,
    peer_list: std.ArrayList(PeerInfo) = .empty,
    ban_list: std.ArrayList(BanInfo) = .empty,

    pub fn init(allocator: Allocator, io: Io) !*Server {
        const self = try allocator.create(Server);

        self.* = .{
            .allocator = allocator,
            .io = io,
            .peer_id = 1337,
            .num_connections = 0,
        };
        return self;
    }

    pub fn deinit(self: *Server) void {
        self.allocator.destroy(self);
    }

    pub fn start(self: *Server) !void {
        // Initialize PRNG and obtain its interface. Uses Xoshiro256 by default.
        const rand_inst: std.Random.IoSource = .{ .io = self.io };
        const rand: std.Random = rand_inst.interface();

        // Set peer_id to a random u64
        self.peer_id = rand.int(u64);

        log.debug("Set random peer ID: {x}", .{self.peer_id});

        // TODO determine based on sidechain type
        const port: u16 = 7777;
        const host = try net.IpAddress.parse("127.0.0.1", port);

        var tcp = try net.IpAddress.listen(&host, self.io, .{});
        defer tcp.deinit(self.io);

        log.info("Listening on port {}", .{port});

        var group: Io.Group = .init;
        defer group.cancel(self.io);

        while (true) {
            const stream = try tcp.accept(self.io);
            errdefer stream.close(self.io);

            log.info("Accepted connection", .{});

            try group.concurrent(self.io, handlePeer, .{ self, stream });
        }
    }
};

test "make server" {
    const alloc = std.heap.page_allocator;
    const io = std.testing.io;

    const serv = try Server.init(alloc, io);
    defer serv.deinit();

    try serv.start();
}

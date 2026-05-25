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

pub const Server = struct {
    allocator: Allocator,
    io: Io,

    peer_id: u64,
    num_connections: usize,

    peer_list: std.ArrayList(PeerInfo) = .empty,
    peers_lock: Io.Mutex = .init,

    ban_list: std.ArrayList(BanInfo) = .empty,
    bans_lock: Io.Mutex = .init,

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

    fn isBanned(self: *Server, addr: net.IpAddress) bool {
        self.bans_lock.lockUncancelable(self.io);
        defer self.bans_lock.unlock(self.io);

        const now = std.time.timestamp();

        for (self.ban_list.items) |b| {
            if (std.meta.eql(b.host, addr) and @as(u64, @intCast(now)) < b.expiration_timestamp) {
                return true;
            }
        }

        return false;
    }

    fn removePeer(self: *Server, addr: net.IpAddress) void {
        self.peers_lock.lockUncancelable(self.io);
        defer self.peers_lock.unlock(self.io);

        const len = self.peer_list.items.len;

        for (0..len) |from_end| {
            const i = len - from_end - 1;

            if (std.meta.eql(self.peer_list.items[i].host, addr)) {
                _ = self.peer_list.swapRemove(i);
            }
        }

        if (self.num_connections > 0) {
            self.num_connections -= 1;
        }
    }

    fn handlePeer(self: *Server, stream: net.Stream) !void {
        defer stream.close(self.io);
        defer self.removePeer(stream.socket.address);

        log.info("Accepted peer {}", .{stream.socket.address});

        const entry = PeerInfo{
            .host = stream.socket.address,
            .failed_connection_count = 0,
            .last_seen_timestamp = 0,
        };

        self.peer_list.append(self.allocator, entry) catch {};

        log.debug("Current peer list: {}", .{self.peer_list});
    }

    pub fn start(self: *Server) !void {
        // Initialize PRNG and obtain its interface. Uses Xoshiro256 by default.
        const rand_io: std.Random.IoSource = .{ .io = self.io };
        const rand: std.Random = rand_io.interface();

        // Set peer_id to a random u64
        self.peer_id = rand.int(u64);

        log.debug("Set random local peer ID: {x}", .{self.peer_id});

        // TODO determine based on sidechain type
        const port: u16 = 7777;
        const addr = try net.IpAddress.parse("127.0.0.1", port);

        var tcp = try net.IpAddress.listen(&addr, self.io, .{});
        defer tcp.deinit(self.io);

        log.info("Listening on {}", .{addr});

        var group: Io.Group = .init;
        defer group.cancel(self.io);

        while (true) {
            const stream = try tcp.accept(self.io);

            _ = group.concurrent(self.io, handlePeer, .{ self, stream }) catch |err| {
                log.err("Failed to create peer handler: {}", .{err});

                stream.close(self.io);
            };
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

const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = std.Io.net;

const log = std.log.scoped(.server);

const PeerInfo = struct {
    host: Io.net.IpAddress,
    failed_connection_count: usize,
    last_seen_timestamp: u64,
};

fn dummyTask() void {
    log.info("Processing dummy task", .{});

    var ts = std.posix.timespec{ .sec = 0, .nsec = 500_000_000 };
    _ = std.posix.system.nanosleep(&ts, &ts);
}

pub const Server = struct {
    allocator: Allocator,
    io: Io,

    peer_id: u64,
    num_connections: usize,

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

        var tcp = try net.IpAddress.listen(host, self.io, .{});
        defer tcp.deinit(self.io);

        log.info("Listening on port {}", .{port});

        var group: Io.Group = .init;
        defer group.cancel(self.io);

        while (true) {
            const stream = try tcp.accept(self.io);
            errdefer stream.close(self.io);

            log.info("Accepted connection", .{});

            try group.concurrent(self.io, dummyTask, .{});
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

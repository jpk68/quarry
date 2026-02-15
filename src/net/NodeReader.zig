const std = @import("std");
const c = @cImport(@cInclude("zmq.h"));

const Allocator = std.mem.Allocator;
const Io = std.Io;

// TODO
// zmq_setsockopt()
// set proxy/sub to monerod stream
// create monitor thread

allocator: Allocator,
io: Io,
zmq_ctx: *anyopaque,
zmq_sock_sub: *anyopaque,
zmq_sock_pub: *anyopaque,
zmq_port_pub: ?u16,

const NodeReader = @This();

pub fn init(allocator: Allocator, io: Io) !NodeReader {
    const ctx = c.zmq_ctx_new() orelse return error.CreateContextFailed;
    errdefer _ = c.zmq_ctx_destroy(ctx);

    const sock_sub = c.zmq_socket(ctx, c.ZMQ_SUB) orelse return error.CreateSocketFailed;
    errdefer _ = c.zmq_close(sock_sub);

    const sock_pub = c.zmq_socket(ctx, c.ZMQ_PUB) orelse return error.CreateSocketFailed;
    errdefer _ = c.zmq_close(sock_pub);

    return .{
        .allocator = allocator,
        .io = io,
        .zmq_ctx = ctx,
        .zmq_sock_sub = sock_sub,
        .zmq_sock_pub = sock_pub,
        .zmq_port_pub = null,
    };
}

pub fn deinit(self: *NodeReader) void {
    _ = c.zmq_close(self.zmq_sock_sub);
    _ = c.zmq_close(self.zmq_sock_pub);
    _ = c.zmq_ctx_destroy(self.zmq_ctx);
}

pub fn run(self: *NodeReader) !void {
    // Initialize PRNG and obtain its interface. Uses Xoshiro256 by default.
    const rand_io: std.Random.IoSource = .{ .io = self.io };
    const rand: std.Random = rand_io.interface();

    // Attempts to bind publisher socket to randomly generated port number.
    var i: u8 = 0;
    while (i < 100) : (i += 1) {
        var buf: [32]u8 = undefined;
        const port = rand.int(u16);

        // Formatted as a null-terminated string for C interop.
        const host = try std.fmt.bufPrintZ(&buf, "tcp://127.0.0.1:{}", .{port});

        if (c.zmq_bind(self.zmq_socket_pub, host) == 0) {
            self.zmq_port_pub = port;
        } else {
            std.log.err("Failed to bind ZMQ socket to port {d}", .{port});
            self.io.sleep(.fromSeconds(1), .awake) catch {};
        }
    }

    if (!self.zmq_port_pub) {
        @panic("Too many failed attempts to bind port!");
    }

    std.log.info("Listening on port {d}", .{self.zmq_port_pub});

    const timeout_ms: c_int = 1000;
    if (c.zmq_setsockopt(
        self.zmq_sock_sub,
        c.ZMQ_CONNECT_TIMEOUT,
        &timeout_ms,
        @sizeOf(@TypeOf(timeout_ms)),
    ) != 0) {
        return error.SetSockOptionsFailed;
    }
}

pub const ChainInfo = struct {
    minor_version: u8,
    block_height: u64,
};

test "create and destroy context/sockets" {
    var threaded: Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var node = try NodeReader.init(io);
    defer node.deinit();
}

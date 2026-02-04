const std = @import("std");
const Io = std.Io;

const c = @cImport(@cInclude("zmq.h"));

zmq_context: *anyopaque,
zmq_sock_sub: *anyopaque,
zmq_sock_pub: *anyopaque,

const NodeReader = @This();

pub fn init() !NodeReader {
    const context = c.zmq_ctx_new() orelse return error.CreateContextFailed;
    errdefer _ = c.zmq_ctx_destroy(context);

    const sock_sub = c.zmq_socket(context, c.ZMQ_SUB) orelse return error.CreateSocketFailed;
    errdefer _ = c.zmq_close(sock_sub);

    const sock_pub = c.zmq_socket(context, c.ZMQ_PUB) orelse return error.CreateSocketFailed;
    errdefer _ = c.zmq_close(sock_pub);

    return .{
        .zmq_context = context,
        .zmq_sock_sub = sock_sub,
        .zmq_sock_pub = sock_pub,
    };
}

pub fn deinit(self: *NodeReader) void {
    _ = c.zmq_close(self.zmq_sock_sub);
    _ = c.zmq_close(self.zmq_sock_pub);
    _ = c.zmq_ctx_destroy(self.zmq_context);
}

pub fn connect(self: *NodeReader) !void {
    // This should be a random u16
    const port: u16 = 3333;
    var buf: [30]u8 = undefined;

    const fmt = try std.fmt.bufPrint(&buf, "tcp://127.0.0.1:{}", .{port});

    std.debug.print("Result: {s}\n", .{fmt});

    _ = self;
}

test "create and destroy context/sockets" {
    var node = try NodeReader.init();
    defer node.deinit();
}

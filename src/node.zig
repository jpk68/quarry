const std = @import("std");
const Io = std.Io;

const c = @cImport({
    @cInclude("zmq.h");
});

pub const NodeReader = struct {
    context: *anyopaque,

    sub_socket: *anyopaque,
    sub_port: u16,

    pub_socket: *anyopaque,
    pub_port: u16,

    pub fn init() !NodeReader {
        const context = c.zmq_ctx_new() orelse return error.CreateContextFailed;
        errdefer _ = c.zmq_ctx_destroy(context);

        const sub_socket = c.zmq_socket(context, c.ZMQ_SUB) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(sub_socket);

        const pub_socket = c.zmq_socket(context, c.ZMQ_PUB) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(pub_socket);

        return .{
            .context = context,
            .sub_socket = sub_socket,
            .pub_socket = pub_socket,
        };
    }

    pub fn deinit(self: *NodeReader) void {
        _ = c.zmq_close(self.sub_socket);
        _ = c.zmq_close(self.pub_socket);
        _ = c.zmq_ctx_destroy(self.context);
    }

    pub fn connect(self: *NodeReader) !void {
        var addr_buf: [24]u8 = undefined;
        var writer = Io.Writer.fixed(&addr_buf);

        // This should be randomly generated
        const port: u16 = 3333;

        try writer.print("tcp://127.0.0.1:{}", .{port});
        try writer.writeByte(0);

        c.zmq_bind(self.pub_socket, addr_buf) orelse {
            std.log.err("Failed to bind publisher socket to port {d}", .{port});
            return error.BindSocketFailed;
        };
        self.pub_port = port;

        std.log.info("Listening on port {d}", .{self.pub_port});

        // https://libzmq.readthedocs.io/en/latest/zmq_setsockopt.html
        c.zmq_setsockopt(self.context, c.ZMQ_CONNECT_TIMEOUT, 1000, 4);

        // TODO set socks proxy/sockopts/subscribe to json from monerod
    }
};

test "create and destroy socket" {
    var reader = try NodeReader.init();
    defer reader.deinit();
}

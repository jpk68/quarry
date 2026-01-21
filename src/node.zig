const c = @cImport(@cInclude("zmq.h"));

pub const NodeReader = struct {
    context: *anyopaque,
    socket_sub: *anyopaque,
    socket_pub: *anyopaque,

    pub fn init() !NodeReader {
        const context = c.zmq_ctx_new() orelse return error.CreateContextFailed;
        errdefer _ = c.zmq_ctx_destroy(context);

        const socket_sub = c.zmq_socket(context, c.ZMQ_SUB) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(socket_sub);

        const socket_pub = c.zmq_socket(context, c.ZMQ_PUB) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(socket_pub);

        return .{
            .context = context,
            .socket_sub = socket_sub,
            .socket_pub = socket_pub,
        };
    }

    pub fn deinit(self: *NodeReader) void {
        _ = c.zmq_close(self.socket_sub);
        _ = c.zmq_close(self.socket_pub);
        _ = c.zmq_ctx_destroy(self.context);
    }
};

test "create and destroy socket" {
    var reader = try NodeReader.init();
    defer reader.deinit();
}

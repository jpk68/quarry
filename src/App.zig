const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const log = std.log.scoped(.app);

const Config = @import("Config.zig");
const Server = @import("net/server.zig").Server;
const NodeConn = @import("net/node.zig").NodeConn;

const App = @This();

allocator: Allocator,
io: Io,
config: *Config,
server: *Server,
node: NodeConn,

pub fn init(allocator: Allocator, io: Io, config: *Config) !*App {
    const self = try allocator.create(App);
    errdefer allocator.destroy(self);

    // Pass the config's sidechain type to the server, so it knows which port to listen on
    const server = try Server.init(allocator, io, config.sidechain_type);
    errdefer server.deinit();

    const node = try NodeConn.init(allocator, io, config.node_addr, config.node_zmq_port);

    self.* = .{
        .allocator = allocator,
        .io = io,
        .config = config,
        .server = server,
        .node = node,
    };
    return self;
}

pub fn deinit(self: *App) void {
    self.server.deinit();
    self.node.deinit();
    self.allocator.destroy(self);
}

pub fn run(self: *App) !void {
    switch (self.config.network_type) {
        .testnet, .stagenet => |t| {
            log.warn("Running on {s}, coins aren't worth anything!", .{@tagName(t)});
        },
        else => {},
    }

    var group: Io.Group = .init;
    defer group.cancel(self.io);

    _ = try group.concurrent(self.io, runNode, .{self});

    try self.server.start();
}

fn runNode(self: *App) !void {
    self.node.connect() catch |err| {
        log.err("Failed to connect to node: {t}", .{err});
        return;
    };

    while (true) {
        const data = self.node.receive() catch |err| {
            log.err("Failed to receive miner data: {t}", .{err});
            continue;
        };
        defer data.deinit(self.allocator);

        log.info("Received miner data at block height {d}", .{data.height});
        log.debug("{any}", .{data});
    }
}

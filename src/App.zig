const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Config = @import("Config.zig");
const Server = @import("net/Server.zig");
const NodeReader = @import("net/NodeReader.zig");

const App = @This();

// TODO
// Cache, mempool, sidechain, wallet, miner

allocator: Allocator,
io: Io,
server: Server,
node_reader: NodeReader,

pub fn init(allocator: Allocator, io: Io, config: *Config) !*App {
    const self = try allocator.create(App);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.io = io;

    self.server = Server{
        .allocator = allocator,
        .io = io,
        .info = .{
            .max_peers_outgoing = config.max_peers_outgoing,
            .max_peers_incoming = config.max_peers_incoming,
            .sidechain_type = config.sidechain_type,
            .data_dir = config.data_dir,
        },
    };

    self.node_reader = try NodeReader.init(config.node_ip, config.node_zmq_port);

    return self;
}

pub fn run(self: *App) !void {
    defer self.server.deinit();
    defer self.node_reader.deinit();

    try self.server.run();
    try self.node_reader.run();
}

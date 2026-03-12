const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const log = std.log.scoped(.app);

const Config = @import("Config.zig");
const Server = @import("net/server.zig").Server;

const App = @This();

allocator: Allocator,
io: Io,

config: *Config,
server: *Server,

pub fn init(allocator: Allocator, io: Io, config: *Config) !*App {
    const self = try allocator.create(App);
    errdefer allocator.destroy(self);

    self.* = .{
        .allocator = allocator,
        .io = io,
        .config = config,
        .server = try Server.init(allocator, io),
    };
    return self;
}

pub fn deinit(self: *App) void {
    self.allocator.destroy(self);
}

pub fn run(self: *App) !void {
    switch (self.config.network_type) {
        .testnet, .stagenet => |t| {
            log.warn("Running on {s}, coins aren't worth anything!", .{@tagName(t)});
        },
        else => {},
    }

    try self.server.start();
}

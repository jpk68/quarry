const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const log = std.log.scoped(.app);

const build = @import("build.zig.zon");
const common = @import("common.zig");
const Config = @import("Config.zig");
const Miner = @import("Miner.zig");
const Server = @import("net/server.zig").Server;
const NodeConn = @import("net/node.zig").NodeConn;
const StratumClient = @import("stratum/Client.zig");
const protocol = @import("stratum/protocol.zig");

const App = @This();

const agent = "Quarry/" ++ build.version;

/// Seconds between keepalives to the stratum server, and between hashrate reports.
const keepalive_interval = 60;
const report_interval = 30;
/// Seconds to wait before reconnecting to the stratum server.
const reconnect_delay = 5;

allocator: Allocator,
io: Io,
config: *Config,
server: ?*Server = null,
node: ?NodeConn = null,

/// Stratum mining state (only with `--pool`).
miner: ?*Miner = null,
client: ?*StratumClient = null,
/// Guards `client` against being closed while a worker submits a share.
client_lock: Io.Mutex = .init,

pub fn init(allocator: Allocator, io: Io, config: *Config) !*App {
    const self = try allocator.create(App);
    errdefer allocator.destroy(self);
    self.* = .{ .allocator = allocator, .io = io, .config = config };

    // Mining on a P2Pool node doesn't need our own P2P server or a Monero node.
    if (config.pool != null) return self;

    // Pass the config's sidechain type to the server, so it knows which port to listen on
    const server = try Server.init(allocator, io, config.sidechain_type);
    errdefer server.deinit();

    self.server = server;
    self.node = try NodeConn.init(allocator, io, config.node_addr, config.node_zmq_port);
    return self;
}

pub fn deinit(self: *App) void {
    if (self.miner) |m| m.destroy();
    if (self.client) |c| c.close();
    if (self.server) |s| s.deinit();
    if (self.node) |*n| n.deinit();
    self.allocator.destroy(self);
}

pub fn run(self: *App) !void {
    switch (self.config.network_type) {
        .testnet, .stagenet => |t| {
            log.warn("Running on {s}, coins aren't worth anything!", .{@tagName(t)});
        },
        else => {},
    }

    if (self.config.pool) |pool| return self.runMiner(pool);

    var group: Io.Group = .init;
    defer group.cancel(self.io);

    _ = try group.concurrent(self.io, runNode, .{self});

    try self.server.?.start();
}

fn runMiner(self: *App, pool: Config.Pool) !void {
    const threads = if (self.config.threads != 0) self.config.threads else Miner.defaultThreadCount(self.io);
    log.info("Starting {d} mining thread{s} in {s} mode", .{ threads, if (threads == 1) "" else "s", if (self.config.light) "light" else "fast" });
    self.miner = try Miner.create(self.allocator, self.io, .{
        .threads = threads,
        .mode = if (self.config.light) .light else .fast,
    }, onShare, self);

    var group: Io.Group = .init;
    defer group.cancel(self.io);
    _ = try group.concurrent(self.io, reportHashrate, .{self});

    while (true) {
        self.mineOnPool(pool) catch |err| {
            log.err("Stratum connection to {s}:{d} failed: {t}", .{ pool.host, pool.port, err });
        };
        Io.sleep(self.io, .fromSeconds(reconnect_delay), .awake) catch |err| switch (err) {
            error.Canceled => return,
        };
        log.info("Reconnecting to {s}:{d}", .{ pool.host, pool.port });
    }
}

/// Mines on one stratum connection until it fails.
fn mineOnPool(self: *App, pool: Config.Pool) !void {
    log.info("Connecting to stratum server {s}:{d}", .{ pool.host, pool.port });
    const client, const first_job = try StratumClient.connect(self.allocator, self.io, pool.host, pool.port, self.config.user, agent);
    self.setClient(client);
    defer self.setClient(null);
    // Don't keep mining a job the pool will no longer accept.
    defer self.miner.?.pause();

    log.info("Logged in as {s}", .{self.config.user});
    try self.startJob(&first_job);

    var keepalive: Io.Group = .init;
    defer keepalive.cancel(self.io);
    _ = try keepalive.concurrent(self.io, sendKeepalives, .{client});

    while (true) switch (try client.next()) {
        .job => |job| try self.startJob(&job),
        .response => |r| if (r.err) |e| {
            log.warn("Share rejected: {s}", .{e.slice()});
        } else {
            log.info("Share accepted", .{});
        },
        .login => return error.UnexpectedLogin,
    };
}

fn startJob(self: *App, job: *const protocol.Job) !void {
    log.info("New job {s}: height {d}, difficulty {d}, {s}", .{ job.id.slice(), job.height, job.difficulty(), job.algo.name() });
    try self.miner.?.setJob(job);
}

fn setClient(self: *App, client: ?*StratumClient) void {
    self.client_lock.lockUncancelable(self.io);
    defer self.client_lock.unlock(self.io);
    if (self.client) |old| old.close();
    self.client = client;
}

/// Called from miner threads.
fn onShare(ctx: ?*anyopaque, job: *const protocol.Job, nonce: u32, hash: *const common.Hash) void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    self.client_lock.lockUncancelable(self.io);
    defer self.client_lock.unlock(self.io);

    const client = self.client orelse return;
    log.info("Found share for job {s} (nonce {x:0>8})", .{ job.id.slice(), nonce });
    _ = client.submit(job.id.slice(), nonce, hash) catch |err| {
        log.err("Failed to submit share: {t}", .{err});
    };
}

fn sendKeepalives(client: *StratumClient) !void {
    while (true) {
        try Io.sleep(client.io, .fromSeconds(keepalive_interval), .awake);
        client.keepalive() catch |err| log.warn("Failed to send keepalive: {t}", .{err});
    }
}

fn reportHashrate(self: *App) !void {
    var last = self.miner.?.hashCount();
    while (true) {
        try Io.sleep(self.io, .fromSeconds(report_interval), .awake);
        const now = self.miner.?.hashCount();
        const rate = @as(f64, @floatFromInt(now - last)) / report_interval;
        log.info("Hashrate: {d:.1} H/s", .{rate});
        last = now;
    }
}

fn runNode(self: *App) !void {
    const node = &self.node.?;
    node.connect() catch |err| {
        log.err("Failed to connect to node: {t}", .{err});
        return;
    };

    while (true) {
        const data = node.receive() catch |err| {
            if (err == error.Stopped) return;
            log.err("Failed to receive miner data: {t}", .{err});
            continue;
        };
        defer data.deinit(self.allocator);

        log.info("Received miner data at block height {d}", .{data.height});
        log.debug("{any}", .{data});
    }
}

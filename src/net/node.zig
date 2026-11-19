const std = @import("std");
const c = @import("zmq");

const common = @import("../common.zig");
const Mempool = @import("../Mempool.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const log = std.log.scoped(.node);

/// Main subscribed topic for the ZMQ interface.
const miner_data_topic = "json-full-miner_data";

/// Maximum number of `tx_backlog` entries for a single `miner_data` message.
const max_tx_backlog_len = std.math.maxInt(u16);

/// Connection to the ZMQ interface of a Monero node.
pub const NodeConn = struct {
    allocator: Allocator,
    io: Io,

    addr: Io.net.IpAddress,
    zmq_port: u16,

    zmq_ctx: *anyopaque,
    zmq_sock_sub: *anyopaque,
    zmq_sock_pub: *anyopaque,
    zmq_port_pub: ?u16,

    monitor: NodeMonitor,
    monitor_group: Io.Group,

    stopped: std.atomic.Value(bool),

    const Self = @This();

    pub fn init(allocator: Allocator, io: Io, addr: Io.net.IpAddress, zmq_port: u16) NodeError!Self {
        const ctx = c.zmq_ctx_new() orelse return error.CreateContextFailed;
        errdefer _ = c.zmq_ctx_destroy(ctx);

        const sock_sub = c.zmq_socket(ctx, c.ZMQ_SUB) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(sock_sub);

        const sock_pub = c.zmq_socket(ctx, c.ZMQ_PUB) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(sock_pub);

        // ZMQ sockets will only accept IPv4 peers, unless IPv6 support is explicitly enabled.
        if (std.meta.activeTag(addr) == .ip6) {
            const one: c_int = 1;
            if (c.zmq_setsockopt(sock_sub, c.ZMQ_IPV6, &one, @sizeOf(c_int)) != 0) return error.SetSockOptionsFailed;
            if (c.zmq_setsockopt(sock_pub, c.ZMQ_IPV6, &one, @sizeOf(c_int)) != 0) return error.SetSockOptionsFailed;
        }

        var monitor = try NodeMonitor.init(ctx, sock_sub);
        errdefer monitor.deinit();

        return .{
            .allocator = allocator,
            .io = io,

            .addr = addr,
            .zmq_port = zmq_port,

            .zmq_ctx = ctx,
            .zmq_sock_sub = sock_sub,
            .zmq_sock_pub = sock_pub,
            .zmq_port_pub = null,

            .monitor = monitor,
            .monitor_group = .init,

            .stopped = .init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.monitor_group.cancel(self.io);
        self.monitor.deinit();
        _ = c.zmq_close(self.zmq_sock_sub);
        _ = c.zmq_close(self.zmq_sock_pub);
        _ = c.zmq_ctx_destroy(self.zmq_ctx);
    }

    /// Unblocks in-progress or future `receive`/monitor calls, so that the connection can safely be
    /// torn down. Idempotent.
    pub fn stop(self: *Self) void {
        if (self.stopped.swap(true, .acq_rel)) return;

        _ = c.zmq_socket_monitor(self.zmq_sock_sub, null, 0);

        const dummy = miner_data_topic ++ ":";
        var msg: c.zmq_msg_t = undefined;
        if (c.zmq_msg_init_size(&msg, dummy.len) != 0) return;
        @memcpy(@as([*]u8, @ptrCast(c.zmq_msg_data(&msg)))[0..dummy.len], dummy);
        _ = c.zmq_msg_send(&msg, self.zmq_sock_pub, 0);
    }

    pub fn connect(self: *Self) NodeError!void {
        const rand_inst: std.Random.IoSource = .{ .io = self.io };
        const rand: std.Random = rand_inst.interface();

        // Attempts to bind the publisher socket to randomly generated port number.
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            var buf: [32]u8 = undefined;
            const port: u16 = 49152 + rand.uintLessThan(u16, 16384);

            // Node address, formatted as a null-terminated string for C interop.
            const host = std.mem.printSentinel(&buf, "tcp://127.0.0.1:{d}", .{port}, 0) catch continue;

            if (c.zmq_bind(self.zmq_sock_pub, host) == 0) {
                self.zmq_port_pub = port;
                break;
            }

            log.warn("Failed to bind ZMQ publisher socket to port {d}", .{port});
            Io.sleep(self.io, .fromMilliseconds(100), .awake) catch {};
        }

        if (self.zmq_port_pub == null) {
            log.err("Too many failed attempts to bind ZMQ publisher port", .{});
            return error.TooManyFailedAttempts;
        }

        log.debug("ZMQ publisher bound to port {d}", .{self.zmq_port_pub.?});

        const connect_timeout_ms: c_int = 1000;
        if (c.zmq_setsockopt(
            self.zmq_sock_sub,
            c.ZMQ_CONNECT_TIMEOUT,
            &connect_timeout_ms,
            @sizeOf(@TypeOf(connect_timeout_ms)),
        ) != 0) {
            return error.SetSockOptionsFailed;
        }

        const handshake_ivl_ms: c_int = 1000;
        if (c.zmq_setsockopt(
            self.zmq_sock_sub,
            c.ZMQ_HANDSHAKE_IVL,
            &handshake_ivl_ms,
            @sizeOf(@TypeOf(handshake_ivl_ms)),
        ) != 0) {
            return error.SetSockOptionsFailed;
        }

        const max_msg_size: i64 = 32 * 1024 * 1024;
        if (c.zmq_setsockopt(
            self.zmq_sock_sub,
            c.ZMQ_MAXMSGSIZE,
            &max_msg_size,
            @sizeOf(@TypeOf(max_msg_size)),
        ) != 0) {
            return error.SetSockOptionsFailed;
        }

        if (c.zmq_setsockopt(self.zmq_sock_sub, c.ZMQ_SUBSCRIBE, miner_data_topic, miner_data_topic.len) != 0) {
            return error.SubscribeFailed;
        }

        var local_buf: [32]u8 = undefined;
        const local_addr = std.mem.printSentinel(&local_buf, "tcp://127.0.0.1:{d}", .{self.zmq_port_pub.?}, 0) catch
            return error.AddressTooLong;

        if (c.zmq_connect(self.zmq_sock_sub, local_addr) != 0) {
            log.err("Failed to connect ZMQ subscriber to internal publisher", .{});
            return error.ConnectFailed;
        }

        try self.waitForConnect(local_addr);

        var target_addr = self.addr;
        switch (target_addr) {
            .ip4 => |*a| a.port = self.zmq_port,
            .ip6 => |*a| a.port = self.zmq_port,
        }

        var addr_buf: [128]u8 = undefined;
        const addr = std.mem.printSentinel(&addr_buf, "tcp://{f}", .{target_addr}, 0) catch
            return error.AddressTooLong;

        if (c.zmq_connect(self.zmq_sock_sub, addr) != 0) {
            log.err("Failed to connect ZMQ subscriber to {s}", .{addr});
            return error.ConnectFailed;
        }

        log.info("Connecting to node ZMQ interface at {s}", .{addr});

        try self.waitForConnect(addr);

        self.monitor_group.concurrent(self.io, monitorLoop, .{self}) catch return error.MonitorFailed;
    }

    fn waitForConnect(self: *Self, target_endpoint: []const u8) NodeError!void {
        const clock: Io.Clock = .awake;
        const start = clock.now(self.io);

        while (start.durationTo(clock.now(self.io)).toMilliseconds() < 1000) {
            const event = self.monitor.nextEvent() catch |err| switch (err) {
                error.Timeout => continue,
                error.RecvFailed => return error.ConnectFailed,
            };

            if (event.kind == .connected and std.mem.eql(u8, event.endpointSlice(), target_endpoint)) {
                return;
            }
        }

        log.warn("Timed out waiting to connect to {s}", .{target_endpoint});
        return error.ConnectTimeout;
    }

    fn monitorLoop(self: *Self) void {
        while (!self.stopped.load(.acquire)) {
            const event = self.monitor.nextEvent() catch |err| switch (err) {
                error.Timeout => continue,
                error.RecvFailed => {
                    if (self.stopped.load(.acquire)) break;
                    log.err("Failed to receive ZMQ monitor event: {t}", .{err});
                    continue;
                },
            };

            switch (event.kind) {
                .connected => log.info("Connected to node ZMQ interface", .{}),
                .disconnected => log.warn("Disconnected from node ZMQ interface", .{}),
                .other => {},
            }
        }
    }

    pub fn receive(self: *Self) NodeError!MinerData {
        var msg: c.zmq_msg_t = undefined;
        if (c.zmq_msg_init(&msg) != 0) return error.RecvFailed;
        defer _ = c.zmq_msg_close(&msg);

        if (c.zmq_msg_recv(&msg, self.zmq_sock_sub, 0) < 0) return error.RecvFailed;

        if (self.stopped.load(.acquire)) return error.Stopped;

        const frame: [*]const u8 = @ptrCast(c.zmq_msg_data(&msg));
        const frame_len = c.zmq_msg_size(&msg);

        const colon = std.mem.indexOfScalar(u8, frame[0..frame_len], ':') orelse return error.InvalidMessage;
        const topic = frame[0..colon];
        const json_data = frame[colon + 1 .. frame_len];

        if (!std.mem.eql(u8, topic, miner_data_topic)) {
            log.debug("Ignoring message with unexpected topic: {s}", .{topic});
            return error.UnknownTopic;
        }

        return parseMinerData(self.allocator, json_data) catch |err| {
            log.debug("Failed to parse miner data: {}", .{err});
            return error.ParseFailed;
        };
    }
};

pub const MinerData = struct {
    major_version: u8,
    height: u64,
    prev_id: common.Hash,
    seed_hash: common.Hash,
    difficulty: common.Difficulty,
    median_weight: u64,
    already_generated_coins: u64,
    median_timestamp: u64,
    tx_backlog: []Mempool.Entry,

    pub fn deinit(self: MinerData, allocator: Allocator) void {
        allocator.free(self.tx_backlog);
    }
};

const MinerDataRaw = struct {
    major_version: u8,
    height: u64,
    prev_id: []const u8,
    seed_hash: []const u8,
    difficulty: []const u8,
    median_weight: u64,
    already_generated_coins: u64,
    median_timestamp: u64 = 0,
    tx_backlog: []const TxEntryRaw = &.{},
};

const TxEntryRaw = struct {
    id: []const u8,
    blob_size: u64,
    weight: u64,
    fee: u64,
};

fn parseHash(input: []const u8) !common.Hash {
    if (input.len != common.hash_size * 2) return error.InvalidHashLength;
    var hash: common.Hash = undefined;
    _ = try std.fmt.hexToBytes(&hash, input);
    return hash;
}

fn parseMinerData(allocator: Allocator, json_data: []const u8) !MinerData {
    const parsed = try std.json.parseFromSlice(MinerDataRaw, allocator, json_data, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const prev_id = try parseHash(parsed.value.prev_id);
    const seed_hash = try parseHash(parsed.value.seed_hash);

    const difficulty = try std.fmt.parseInt(common.Difficulty, parsed.value.difficulty, 0);

    if (parsed.value.tx_backlog.len > max_tx_backlog_len) return error.TxBacklogTooLarge;

    const tx_backlog = try allocator.alloc(Mempool.Entry, parsed.value.tx_backlog.len);
    errdefer allocator.free(tx_backlog);

    for (parsed.value.tx_backlog, tx_backlog) |raw, *entry| {
        entry.* = .{
            .id = try parseHash(raw.id),
            .blob_size = @intCast(raw.blob_size),
            .weight = raw.weight,
            .fee = raw.fee,
            .time_received = 0,
        };
    }

    std.mem.sortUnstable(Mempool.Entry, tx_backlog, {}, Mempool.Entry.lessThan);

    return .{
        .major_version = parsed.value.major_version,
        .height = parsed.value.height,
        .prev_id = prev_id,
        .seed_hash = seed_hash,
        .difficulty = difficulty,
        .median_weight = parsed.value.median_weight,
        .already_generated_coins = parsed.value.already_generated_coins,
        .median_timestamp = parsed.value.median_timestamp,
        .tx_backlog = tx_backlog,
    };
}

const NodeMonitor = struct {
    zmq_sock: *anyopaque,

    const Self = @This();
    const endpoint = "inproc://node-monitor";

    fn init(ctx: *anyopaque, sub_socket: *anyopaque) !Self {
        if (c.zmq_socket_monitor(sub_socket, endpoint, c.ZMQ_EVENT_CONNECTED | c.ZMQ_EVENT_DISCONNECTED) != 0) {
            return error.MonitorFailed;
        }

        const sock = c.zmq_socket(ctx, c.ZMQ_PAIR) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(sock);

        const recv_timeout_ms: c_int = 1000;
        if (c.zmq_setsockopt(sock, c.ZMQ_RCVTIMEO, &recv_timeout_ms, @sizeOf(c_int)) != 0) {
            return error.SetSockOptionsFailed;
        }

        if (c.zmq_connect(sock, endpoint) != 0) {
            return error.ConnectFailed;
        }

        return .{ .zmq_sock = sock };
    }

    fn deinit(self: *Self) void {
        _ = c.zmq_close(self.zmq_sock);
    }

    const EventType = enum {
        connected,
        disconnected,
        other,
    };

    const MonitorEvent = struct {
        kind: EventType,
        endpoint_buf: [128]u8 = undefined,
        endpoint_len: usize = 0,

        fn endpointSlice(self: *const @This()) []const u8 {
            return self.endpoint_buf[0..self.endpoint_len];
        }
    };

    const MonitorError = error{ RecvFailed, Timeout };

    fn nextEvent(self: *Self) MonitorError!MonitorEvent {
        var event_msg: c.zmq_msg_t = undefined;
        if (c.zmq_msg_init(&event_msg) != 0) return error.RecvFailed;
        defer _ = c.zmq_msg_close(&event_msg);

        if (c.zmq_msg_recv(&event_msg, self.zmq_sock, 0) < 0) {
            if (c.zmq_errno() == c.EAGAIN) return error.Timeout;
            return error.RecvFailed;
        }

        const event_data: [*]const u8 = @ptrCast(c.zmq_msg_data(&event_msg));
        const event_id = std.mem.bytesToValue(u16, event_data[0..2]);

        var endpoint_msg: c.zmq_msg_t = undefined;
        if (c.zmq_msg_init(&endpoint_msg) != 0) return error.RecvFailed;
        defer _ = c.zmq_msg_close(&endpoint_msg);
        _ = c.zmq_msg_recv(&endpoint_msg, self.zmq_sock, 0);

        var result: MonitorEvent = .{ .kind = switch (event_id) {
            c.ZMQ_EVENT_CONNECTED => .connected,
            c.ZMQ_EVENT_DISCONNECTED => .disconnected,
            else => .other,
        } };

        const ep_data: [*]const u8 = @ptrCast(c.zmq_msg_data(&endpoint_msg));
        const ep_len = @min(c.zmq_msg_size(&endpoint_msg), result.endpoint_buf.len);
        @memcpy(result.endpoint_buf[0..ep_len], ep_data[0..ep_len]);
        result.endpoint_len = ep_len;

        return result;
    }
};

const NodeError = error{
    CreateContextFailed,
    CreateSocketFailed,
    SetSockOptionsFailed,
    TooManyFailedAttempts,
    AddressTooLong,
    ConnectFailed,
    ConnectTimeout,
    SubscribeFailed,
    RecvFailed,
    InvalidMessage,
    UnknownTopic,
    ParseFailed,
    MonitorFailed,
    Stopped,
};

test "init and deinit" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var node = try NodeConn.init(allocator, io, Io.net.IpAddress.parseLiteral("127.0.0.1") catch unreachable, 18083);
    defer node.deinit();
}

test "connect times out when node is unreachable" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Port assumed to have nothing listening on it.
    var node = try NodeConn.init(allocator, io, Io.net.IpAddress.parseLiteral("127.0.0.1") catch unreachable, 18189);
    defer node.deinit();

    try std.testing.expectError(error.ConnectTimeout, node.connect());
}

fn receiveUntilStopped(node: *NodeConn) void {
    _ = node.receive() catch |err| {
        std.debug.assert(err == error.Stopped);
    };
}

test "stop unblocks a receive call blocked on the node's ZMQ interface" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // The remote connection times out since nothing is listening, but the internal
    // publisher/subscriber loopback used by `stop` is confirmed connected regardless.
    var node = try NodeConn.init(allocator, io, Io.net.IpAddress.parseLiteral("127.0.0.1") catch unreachable, 18189);
    defer node.deinit();

    try std.testing.expectError(error.ConnectTimeout, node.connect());

    var group: Io.Group = .init;
    try group.concurrent(io, receiveUntilStopped, .{&node});

    node.stop();

    // Hangs (and the test times out) if `stop` fails to unblock `receive`.
    try group.await(io);
}

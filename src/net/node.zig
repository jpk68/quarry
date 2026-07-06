const std = @import("std");
const c = @cImport(@cInclude("zmq.h"));

const common = @import("../common.zig");
const Mempool = @import("../Mempool.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const log = std.log.scoped(.node);

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

    const Self = @This();

    pub fn init(allocator: Allocator, io: Io, addr: Io.net.IpAddress, zmq_port: u16) NodeError!Self {
        const ctx = c.zmq_ctx_new() orelse return error.CreateContextFailed;
        errdefer _ = c.zmq_ctx_destroy(ctx);

        const sock_sub = c.zmq_socket(ctx, c.ZMQ_SUB) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(sock_sub);

        const sock_pub = c.zmq_socket(ctx, c.ZMQ_PUB) orelse return error.CreateSocketFailed;
        errdefer _ = c.zmq_close(sock_pub);

        return .{
            .allocator = allocator,
            .io = io,

            .addr = addr,
            .zmq_port = zmq_port,

            .zmq_ctx = ctx,
            .zmq_sock_sub = sock_sub,
            .zmq_sock_pub = sock_pub,
            .zmq_port_pub = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = c.zmq_close(self.zmq_sock_sub);
        _ = c.zmq_close(self.zmq_sock_pub);
        _ = c.zmq_ctx_destroy(self.zmq_ctx);
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
            const host = std.fmt.bufPrintZ(&buf, "tcp://127.0.0.1:{d}", .{port}) catch continue;

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

        var target_addr = self.addr;
        switch (target_addr) {
            .ip4 => |*a| a.port = self.zmq_port,
            .ip6 => |*a| a.port = self.zmq_port,
        }

        var addr_buf: [128]u8 = undefined;
        const addr = std.fmt.bufPrintZ(&addr_buf, "tcp://{f}", .{target_addr}) catch
            return error.AddressTooLong;

        if (c.zmq_connect(self.zmq_sock_sub, addr) != 0) {
            log.err("Failed to connect ZMQ subscriber to {s}", .{addr});
            return error.ConnectFailed;
        }

        log.info("Connecting to node ZMQ interface at {s}", .{addr});

        const topic = "json-full-miner_data";
        if (c.zmq_setsockopt(self.zmq_sock_sub, c.ZMQ_SUBSCRIBE, topic, topic.len) != 0) {
            return error.SubscribeFailed;
        }
    }

    pub fn receive(self: *Self) NodeError!MinerData {
        var msg: c.zmq_msg_t = undefined;
        if (c.zmq_msg_init(&msg) != 0) return error.RecvFailed;
        defer _ = c.zmq_msg_close(&msg);

        if (c.zmq_msg_recv(&msg, self.zmq_sock_sub, 0) < 0) return error.RecvFailed;

        const frame: [*]const u8 = @ptrCast(c.zmq_msg_data(&msg));
        const frame_len = c.zmq_msg_size(&msg);

        const colon = std.mem.indexOfScalar(u8, frame[0..frame_len], ':') orelse return error.InvalidMessage;
        const json_data = frame[colon + 1 .. frame_len];

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

fn parseMinerData(allocator: Allocator, json_data: []const u8) !MinerData {
    const parsed = try std.json.parseFromSlice(MinerDataRaw, allocator, json_data, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var prev_id: common.Hash = undefined;
    _ = try std.fmt.hexToBytes(&prev_id, parsed.value.prev_id);

    var seed_hash: common.Hash = undefined;
    _ = try std.fmt.hexToBytes(&seed_hash, parsed.value.seed_hash);

    const difficulty = try std.fmt.parseInt(common.Difficulty, parsed.value.difficulty, 0);

    const tx_backlog = try allocator.alloc(Mempool.Entry, parsed.value.tx_backlog.len);
    errdefer allocator.free(tx_backlog);

    for (parsed.value.tx_backlog, tx_backlog) |raw, *entry| {
        var txid: common.Hash = undefined;
        _ = try std.fmt.hexToBytes(&txid, raw.id);
        entry.* = .{
            .id = txid,
            .blob_size = @intCast(raw.blob_size),
            .weight = raw.weight,
            .fee = raw.fee,
            .time_received = 0,
        };
    }

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

const NodeError = error{
    CreateContextFailed,
    CreateSocketFailed,
    SetSockOptionsFailed,
    TooManyFailedAttempts,
    AddressTooLong,
    ConnectFailed,
    SubscribeFailed,
    RecvFailed,
    InvalidMessage,
    ParseFailed,
};

test "init and deinit" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var node = try NodeConn.init(allocator, io, Io.net.IpAddress.parseLiteral("127.0.0.1") catch unreachable, 18083);
    defer node.deinit();
}

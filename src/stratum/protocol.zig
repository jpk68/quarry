//! Stratum messages exchanged with P2Pool's stratum server (stratum_server.cpp).
//!
//! The protocol is newline-delimited JSON-RPC over TCP, in the dialect used by XMRig:
//! - the miner sends `login` and receives its first job in the response,
//! - the server pushes later jobs with the `job` method,
//! - the miner sends `submit` for each share and `keepalived` to stay connected.

const std = @import("std");
const common = @import("../common.zig");

const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

/// Offset of the 4-byte nonce in a Monero block hashing blob.
pub const nonce_offset = 39;

/// Largest hashing blob accepted from the pool, in bytes.
pub const max_blob_size = 512;

/// Proof-of-work algorithm of a job.
pub const Algo = enum {
    /// RandomX v1, used by Monero until the RandomX v2 hard fork.
    rx0,
    /// RandomX v2.
    rx2,

    pub fn name(self: Algo) []const u8 {
        return switch (self) {
            .rx0 => "rx/0",
            .rx2 => "rx/2",
        };
    }

    pub fn parse(text: []const u8) ?Algo {
        if (std.mem.eql(u8, text, "rx/0")) return .rx0;
        if (std.mem.eql(u8, text, "rx/2")) return .rx2;
        return null;
    }
};

/// Algorithms advertised at login, so the pool can switch to RandomX v2 after the hard fork.
pub const supported_algos = [_][]const u8{ Algo.rx0.name(), Algo.rx2.name() };

/// Short string identifier (job ID or session ID) copied out of a message.
pub const Id = struct {
    buf: [64]u8 = undefined,
    len: u8 = 0,

    pub fn init(text: []const u8) !Id {
        if (text.len > 64) return error.IdTooLong;
        var id: Id = .{ .len = @intCast(text.len) };
        @memcpy(id.buf[0..text.len], text);
        return id;
    }

    pub fn slice(self: *const Id) []const u8 {
        return self.buf[0..self.len];
    }
};

/// A mining job: hash `blob` with varying nonces until the result meets `target`.
pub const Job = struct {
    id: Id,
    blob_buf: [max_blob_size]u8,
    blob_len: u16,
    /// 64-bit target; a hash meets it when its last 8 bytes, read little-endian, are below it.
    target: u64,
    height: u64,
    seed_hash: common.Hash,
    algo: Algo,

    pub fn blob(self: *const Job) []const u8 {
        return self.blob_buf[0..self.blob_len];
    }

    /// Share difficulty that `target` corresponds to.
    pub fn difficulty(self: *const Job) u64 {
        return std.math.maxInt(u64) / @max(self.target, 1);
    }
};

/// Parses a hex target: 4 bytes (compact, scaled the way XMRig and P2Pool do) or 8 bytes.
pub fn parseTarget(hex: []const u8) !u64 {
    switch (hex.len) {
        8 => {
            var bytes: [4]u8 = undefined;
            _ = try std.fmt.hexToBytes(&bytes, hex);
            const t32 = std.mem.readInt(u32, &bytes, .little);
            if (t32 == 0) return error.InvalidTarget;
            return std.math.maxInt(u64) / @as(u64, std.math.maxInt(u32) / t32);
        },
        16 => {
            var bytes: [8]u8 = undefined;
            _ = try std.fmt.hexToBytes(&bytes, hex);
            const t64 = std.mem.readInt(u64, &bytes, .little);
            if (t64 == 0) return error.InvalidTarget;
            return t64;
        },
        else => return error.InvalidTarget,
    }
}

/// Whether a RandomX result hash meets a 64-bit target.
pub fn meetsTarget(hash: *const common.Hash, target: u64) bool {
    return std.mem.readInt(u64, hash[24..32], .little) < target;
}

/// A message received from the pool.
pub const Message = union(enum) {
    /// Successful login response, carrying the session ID and the first job.
    login: struct { request_id: u64, session_id: Id, job: Job },
    /// New job pushed by the pool.
    job: Job,
    /// Response to a request (`submit`, `keepalived`), or a failed login.
    response: struct { request_id: u64, err: ?ErrorMessage },
};

/// Error text from a pool response, truncated to fit.
pub const ErrorMessage = struct {
    buf: [128]u8 = undefined,
    len: u8 = 0,

    fn init(text: []const u8) ErrorMessage {
        const n = @min(text.len, 128);
        var e: ErrorMessage = .{ .len = @intCast(n) };
        @memcpy(e.buf[0..n], text[0..n]);
        return e;
    }

    pub fn slice(self: *const ErrorMessage) []const u8 {
        return self.buf[0..self.len];
    }
};

const RawJob = struct {
    blob: []const u8,
    job_id: []const u8,
    target: []const u8,
    height: u64 = 0,
    seed_hash: []const u8,
    algo: ?[]const u8 = null,
};

const RawMessage = struct {
    id: ?u64 = null,
    method: ?[]const u8 = null,
    params: ?std.json.Value = null,
    result: ?std.json.Value = null,
    @"error": ?struct { message: []const u8 = "" } = null,
};

/// Parses one line received from the pool.
pub fn parseMessage(gpa: Allocator, line: []const u8) !Message {
    const parsed = try std.json.parseFromSlice(RawMessage, gpa, line, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const msg = parsed.value;
    const arena = parsed.arena.allocator();

    if (msg.method) |method| {
        if (!std.mem.eql(u8, method, "job")) return error.UnknownMethod;
        const params = msg.params orelse return error.MissingParams;
        return .{ .job = try jobFromValue(arena, params) };
    }

    const request_id = msg.id orelse return error.MissingId;
    if (msg.@"error") |err| return .{ .response = .{ .request_id = request_id, .err = .init(err.message) } };

    // A login response carries a session ID and a job; other responses only a status.
    if (msg.result) |result| if (result == .object) {
        if (result.object.get("job")) |job_value| {
            const session = result.object.get("id") orelse return error.MissingSessionId;
            if (session != .string) return error.MissingSessionId;
            return .{ .login = .{
                .request_id = request_id,
                .session_id = try .init(session.string),
                .job = try jobFromValue(arena, job_value),
            } };
        }
    };
    return .{ .response = .{ .request_id = request_id, .err = null } };
}

fn jobFromValue(arena: Allocator, value: std.json.Value) !Job {
    const raw = try std.json.parseFromValueLeaky(RawJob, arena, value, .{ .ignore_unknown_fields = true });

    if (raw.blob.len % 2 != 0 or raw.blob.len / 2 > max_blob_size) return error.InvalidBlob;
    if (raw.blob.len / 2 < nonce_offset + 4) return error.InvalidBlob;
    if (raw.seed_hash.len != common.hash_size * 2) return error.InvalidSeedHash;

    var job: Job = .{
        .id = try .init(raw.job_id),
        .blob_buf = undefined,
        .blob_len = @intCast(raw.blob.len / 2),
        .target = try parseTarget(raw.target),
        .height = raw.height,
        .seed_hash = undefined,
        .algo = if (raw.algo) |a| Algo.parse(a) orelse return error.UnsupportedAlgo else .rx0,
    };
    _ = try std.fmt.hexToBytes(job.blob_buf[0..job.blob_len], raw.blob);
    _ = try std.fmt.hexToBytes(&job.seed_hash, raw.seed_hash);
    return job;
}

/// Writes a `login` request. P2Pool treats `login` as a worker name (optionally "name+diff"):
/// payouts go to the wallet P2Pool itself was started with.
pub fn writeLogin(w: *Writer, request_id: u64, login: []const u8, agent: []const u8) !void {
    try std.json.Stringify.value(.{
        .id = request_id,
        .jsonrpc = "2.0",
        .method = "login",
        .params = .{ .login = login, .pass = "x", .agent = agent, .algo = supported_algos },
    }, .{}, w);
    try w.writeByte('\n');
}

/// Writes a `submit` request for a share found with `nonce`.
pub fn writeSubmit(w: *Writer, request_id: u64, session_id: []const u8, job_id: []const u8, nonce: u32, hash: *const common.Hash) !void {
    var nonce_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &nonce_bytes, nonce, .little);
    try std.json.Stringify.value(.{
        .id = request_id,
        .jsonrpc = "2.0",
        .method = "submit",
        .params = .{
            .id = session_id,
            .job_id = job_id,
            .nonce = &std.fmt.bytesToHex(nonce_bytes, .lower),
            .result = &std.fmt.bytesToHex(hash.*, .lower),
        },
    }, .{}, w);
    try w.writeByte('\n');
}

/// Writes a `keepalived` request.
pub fn writeKeepalive(w: *Writer, request_id: u64, session_id: []const u8) !void {
    try std.json.Stringify.value(.{
        .id = request_id,
        .jsonrpc = "2.0",
        .method = "keepalived",
        .params = .{ .id = session_id },
    }, .{}, w);
    try w.writeByte('\n');
}

const testing = std.testing;

const test_blob = "1010" ++ "00" ** 37 ++ "00000000" ++ "ab" ** 32 ++ "01";
const test_seed = "cd" ** 32;

test "parse login response" {
    const line =
        \\{"id":1,"jsonrpc":"2.0","result":{"id":"00000000a1b2c3d4","job":{"blob":"
    ++ test_blob ++
        \\","job_id":"0000000a","target":"f3220000","algo":"rx/0","height":3500000,"seed_hash":"
    ++ test_seed ++
        \\"},"extensions":["algo"],"status":"OK"}}
    ;
    const msg = try parseMessage(testing.allocator, line);
    const login = msg.login;
    try testing.expectEqual(1, login.request_id);
    try testing.expectEqualStrings("00000000a1b2c3d4", login.session_id.slice());
    try testing.expectEqualStrings("0000000a", login.job.id.slice());
    try testing.expectEqual(test_blob.len / 2, login.job.blob().len);
    try testing.expectEqual(3500000, login.job.height);
    try testing.expectEqual(Algo.rx0, login.job.algo);
    try testing.expectEqual(@as(u8, 0xcd), login.job.seed_hash[31]);
    try testing.expectEqual(try parseTarget("f3220000"), login.job.target);
}

test "parse pushed job" {
    const line =
        \\{"jsonrpc":"2.0","method":"job","params":{"blob":"
    ++ test_blob ++
        \\","job_id":"0000000b","target":"b88d0600","algo":"rx/2","height":3500001,"seed_hash":"
    ++ test_seed ++
        \\"}}
    ;
    const msg = try parseMessage(testing.allocator, line);
    try testing.expectEqualStrings("0000000b", msg.job.id.slice());
    try testing.expectEqual(Algo.rx2, msg.job.algo);
}

test "parse submit responses" {
    const ok = try parseMessage(testing.allocator,
        \\{"id":5,"jsonrpc":"2.0","error":null,"result":{"status":"OK"}}
    );
    try testing.expectEqual(5, ok.response.request_id);
    try testing.expect(ok.response.err == null);

    const bad = try parseMessage(testing.allocator,
        \\{"id":6,"jsonrpc":"2.0","error":{"message":"Low diff share"}}
    );
    try testing.expectEqual(6, bad.response.request_id);
    try testing.expectEqualStrings("Low diff share", bad.response.err.?.slice());
}

test "reject malformed jobs" {
    try testing.expectError(error.InvalidBlob, parseMessage(testing.allocator,
        \\{"jsonrpc":"2.0","method":"job","params":{"blob":"1010","job_id":"1","target":"b88d0600","seed_hash":"
    ++ test_seed ++
        \\"}}
    ));
    try testing.expectError(error.UnsupportedAlgo, parseMessage(testing.allocator,
        \\{"jsonrpc":"2.0","method":"job","params":{"blob":"
    ++ test_blob ++
        \\","job_id":"1","target":"b88d0600","algo":"cn/r","seed_hash":"
    ++ test_seed ++
        \\"}}
    ));
}

test "targets" {
    // Compact targets scale the way XMRig does: 0x00068db8 is difficulty 10000.
    const t = try parseTarget("b88d0600");
    try testing.expectEqual(std.math.maxInt(u64) / 10000, t);
    try testing.expectEqual(0x0123456789abcdef, try parseTarget("efcdab8967452301"));
    try testing.expectError(error.InvalidTarget, parseTarget("00000000"));
    try testing.expectError(error.InvalidTarget, parseTarget("abc"));

    var hash: common.Hash = @splat(0xff);
    std.mem.writeInt(u64, hash[24..32], t - 1, .little);
    try testing.expect(meetsTarget(&hash, t));
    std.mem.writeInt(u64, hash[24..32], t, .little);
    try testing.expect(!meetsTarget(&hash, t));
}

test "write requests" {
    var buf: [512]u8 = undefined;
    var w: Writer = .fixed(&buf);

    try writeLogin(&w, 1, "4Abc", "Quarry/0.1.0");
    try testing.expectEqualStrings(
        \\{"id":1,"jsonrpc":"2.0","method":"login","params":{"login":"4Abc","pass":"x","agent":"Quarry/0.1.0","algo":["rx/0","rx/2"]}}
    ++ "\n", w.buffered());

    w = .fixed(&buf);
    const hash: common.Hash = @splat(0x11);
    try writeSubmit(&w, 2, "sess", "0000000a", 0x04030201, &hash);
    try testing.expectEqualStrings(
        \\{"id":2,"jsonrpc":"2.0","method":"submit","params":{"id":"sess","job_id":"0000000a","nonce":"01020304","result":"
    ++ "11" ** 32 ++
        \\"}}
    ++ "\n", w.buffered());

    w = .fixed(&buf);
    try writeKeepalive(&w, 3, "sess");
    try testing.expectEqualStrings(
        \\{"id":3,"jsonrpc":"2.0","method":"keepalived","params":{"id":"sess"}}
    ++ "\n", w.buffered());
}

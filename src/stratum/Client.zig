//! Stratum connection to a P2Pool node.
//!
//! One task reads messages with `next`; any thread may `submit` shares or send `keepalive`
//! concurrently, since writes are serialized by a mutex.

const std = @import("std");
const common = @import("../common.zig");
const protocol = @import("protocol.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

const log = std.log.scoped(.stratum);

const Client = @This();

/// Longest line accepted from the pool; a job is well under 2 KiB.
const max_line_size = 16 * 1024;

gpa: Allocator,
io: Io,

stream: net.Stream,
reader: net.Stream.Reader,
writer: net.Stream.Writer,
read_buf: [max_line_size]u8,
write_buf: [1024]u8,
write_lock: Io.Mutex,

session_id: protocol.Id,
next_request_id: std.atomic.Value(u64),

/// Connects to `host:port` and logs in as worker `login`. Returns the client and the first job.
pub fn connect(gpa: Allocator, io: Io, host: []const u8, port: u16, login: []const u8, agent: []const u8) !struct { *Client, protocol.Job } {
    const stream = try connectStream(io, host, port);
    errdefer stream.close(io);

    // The reader and writer point into the client's buffers, so the client must not move.
    const self = try gpa.create(Client);
    errdefer gpa.destroy(self);
    self.* = .{
        .gpa = gpa,
        .io = io,
        .stream = stream,
        .reader = undefined,
        .writer = undefined,
        .read_buf = undefined,
        .write_buf = undefined,
        .write_lock = .init,
        .session_id = .{},
        .next_request_id = .init(1),
    };
    self.reader = stream.reader(io, &self.read_buf);
    self.writer = stream.writer(io, &self.write_buf);

    const login_id = self.requestId();
    try self.send(protocol.writeLogin, .{ login_id, login, agent });

    // The pool answers the login with the first job; nothing else is sent before it.
    switch (try self.next()) {
        .login => |ok| {
            if (ok.request_id != login_id) return error.UnexpectedResponse;
            self.session_id = ok.session_id;
            return .{ self, ok.job };
        },
        .response => |r| {
            if (r.err) |e| log.err("Login rejected: {s}", .{e.slice()});
            return error.LoginFailed;
        },
        .job => return error.UnexpectedResponse,
    }
}

fn connectStream(io: Io, host: []const u8, port: u16) !net.Stream {
    // Literal IPv4/IPv6 addresses skip name resolution.
    if (net.IpAddress.parse(host, port)) |addr| {
        return addr.connect(io, .{ .mode = .stream });
    } else |_| {}
    const host_name = try net.HostName.init(host);
    return host_name.connect(io, port, .{ .mode = .stream });
}

pub fn close(self: *Client) void {
    self.stream.close(self.io);
    self.gpa.destroy(self);
}

/// Blocks until the next message from the pool arrives.
pub fn next(self: *Client) !protocol.Message {
    while (true) {
        const line = self.reader.interface.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => return self.reader.err.?,
            error.StreamTooLong => return error.MessageTooLong,
        } orelse return error.ConnectionClosed;
        if (line.len == 0) continue;

        return protocol.parseMessage(self.gpa, line) catch |err| {
            log.warn("Ignoring unparseable message from pool ({t}): {s}", .{ err, line });
            continue;
        };
    }
}

/// Submits a share. Returns the request ID that the pool's response will carry.
pub fn submit(self: *Client, job_id: []const u8, nonce: u32, hash: *const common.Hash) !u64 {
    const id = self.requestId();
    try self.send(protocol.writeSubmit, .{ id, self.session_id.slice(), job_id, nonce, hash });
    return id;
}

/// Tells the pool the connection is still alive.
pub fn keepalive(self: *Client) !void {
    try self.send(protocol.writeKeepalive, .{ self.requestId(), self.session_id.slice() });
}

fn requestId(self: *Client) u64 {
    return self.next_request_id.fetchAdd(1, .monotonic);
}

fn send(self: *Client, comptime write_fn: anytype, args: anytype) !void {
    self.write_lock.lockUncancelable(self.io);
    defer self.write_lock.unlock(self.io);

    const w = &self.writer.interface;
    @call(.auto, write_fn, .{w} ++ args) catch |err| switch (err) {
        error.WriteFailed => return self.writer.err.?,
    };
    w.flush() catch return self.writer.err.?;
}

const testing = std.testing;

const test_job_line =
    \\{"id":1,"jsonrpc":"2.0","result":{"id":"5e55","job":{"blob":"
++ "1010" ++ "00" ** 37 ++ "00000000" ++ "ab" ** 32 ++ "01" ++
    \\","job_id":"0000000a","target":"b88d0600","algo":"rx/0","height":7,"seed_hash":"
++ "cd" ** 32 ++
    \\"},"extensions":["algo"],"status":"OK"}}
++ "\n";

/// Minimal stand-in for P2Pool's stratum server: answers a login and one submit.
fn fakePool(io: Io, server: *net.Server, received: *[2][512]u8, lens: *[2]usize) !void {
    const conn = try server.accept(io);
    defer conn.close(io);
    var rbuf: [1024]u8 = undefined;
    var wbuf: [1024]u8 = undefined;
    var r = conn.reader(io, &rbuf);
    var w = conn.writer(io, &wbuf);

    for (0..2) |i| {
        const line = (try r.interface.takeDelimiter('\n')).?;
        @memcpy(received[i][0..line.len], line);
        lens[i] = line.len;
        try w.interface.writeAll(if (i == 0) test_job_line else
            \\{"id":2,"jsonrpc":"2.0","error":null,"result":{"status":"OK"}}
        ++ "\n");
        try w.interface.flush();
    }
}

test "login and submit against a fake pool" {
    const io = testing.io;
    const addr = try net.IpAddress.parse("127.0.0.1", 0);
    var server = try addr.listen(io, .{});
    defer server.deinit(io);

    var received: [2][512]u8 = undefined;
    var lens: [2]usize = undefined;
    var pool = try io.concurrent(fakePool, .{ io, &server, &received, &lens });
    defer pool.cancel(io) catch {};

    const client, const job = try connect(testing.allocator, io, "127.0.0.1", server.socket.address.getPort(), "4Abc", "Quarry/test");
    defer client.close();

    try testing.expectEqualStrings("0000000a", job.id.slice());
    try testing.expectEqualStrings("5e55", client.session_id.slice());
    try testing.expect(std.mem.indexOf(u8, received[0][0..lens[0]], "\"method\":\"login\"") != null);

    const hash: common.Hash = @splat(0);
    const id = try client.submit(job.id.slice(), 42, &hash);
    const response = (try client.next()).response;
    try testing.expectEqual(id, response.request_id);
    try testing.expect(response.err == null);
    try testing.expect(std.mem.indexOf(u8, received[1][0..lens[1]], "\"nonce\":\"2a000000\"") != null);

    try pool.await(io);
}

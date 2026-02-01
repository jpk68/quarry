const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Server = @This();

// TODO
// Reader/writer loop
// Use better names
// Error handling for defer catch {};

allocator: Allocator,
io: Io,
server_id: u64 = undefined,
max_peers_outgoing: u32,
max_peers_incoming: u32,
peer_list: std.SinglyLinkedList = .{},

pub fn run(self: *Server) !void {
    // Set random ID number for this server
    const random_number: u64 = 431241321324;
    self.server_id = random_number;

    // Set port number based on which sidechain we're using
    const listen_port = @as(u16, switch (self.config.sidechain_type) {
        .main => 37889,
        .mini => 37888,
        .nano => 37890,
    });

    const listen_addr = try Io.net.IpAddress.parse("127.0.0.1", listen_port);
    var listen_sock = try Io.net.IpAddress.listen(listen_addr, self.io, .{});

    var task = try self.io.concurrent(acceptLoop, .{ self, &listen_sock });
    defer task.cancel(self.io) catch {};
    try task.await(self.io);
}

fn acceptLoop(self: *Server, sock: *Io.net.Server) !void {
    // Clean up socket when loop ends
    defer sock.deinit(self.io);

    while (true) {
        // Blocks waiting for a TCP connection
        const stream = try sock.accept(self.io);

        // Each peer connection makes progress independently
        // This spawns a concurrent task per connection
        var peer_task = try self.io.concurrent(handlePeer, .{ self, stream });
        // Cancel peer if the loop exits early
        defer peer_task.cancel(self.io) catch {};
    }
}

fn handlePeer(self: *Server, stream: Io.net.Stream) !void {
    // Clean up stream when loop ends
    defer stream.close(self.io);

    var in_queue: Io.Queue([]u8) = .init(&.{});
    var out_queue: Io.Queue([]u8) = .init(&.{});

    var reader = try self.io.concurrent(readerLoop, .{ self, stream, &in_queue });
    defer reader.cancel(self.io) catch {};

    var writer = try self.io.concurrent(writerLoop, .{ self, stream, &out_queue });
    defer writer.cancel(self.io) catch {};

    while (true) {
        const msg = in_queue.getOne(self.io);

        std.log.debug("Received message: {s}", .{msg});
    }
}

const MessageType = enum {
    handshake_challenge,
    handshake_solution,
    listen_port,
    block_request,
    block_response,
    block_broadcast,
    peer_list_request,
    peer_list_response,
    block_broadcast_compact,
    block_notify,
    //aux_job_donation,
    monero_block_broadcast,
};

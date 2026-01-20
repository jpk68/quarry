const std = @import("std");
const Config = @import("../config.zig").Config;
const Server = @This();

const Io = std.Io;

// TODO
// Don't use magic numbers for ports and stuff
// Use actual peer list structure

io: Io,
peer_id: u64,
peer_id_alt: u64,
listen_addr: Io.net.IpAddress,
max_peers_outgoing: usize,
max_peers_incoming: usize,
//peer_list: std.ArrayList(Client),

pub fn init(io: Io, config: *Config) !Server {
    const listen_port = @as(u16, switch (config.sidechain_type) {
        .main => 37889,
        .mini => 37888,
        .nano => 37890,
    });

    // This should be a random u64
    const random_number = 1234;

    return .{
        .io = io,
        .peer_id = random_number,
        .peer_id_alt = random_number,
        .listen_addr = Io.net.IpAddress.parseIp4("127.0.0.1", listen_port),
        .max_peers_outgoing = config.max_peers_outgoing,
        .max_peers_incoming = config.max_peers_incoming,
    };
}

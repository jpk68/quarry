const std = @import("std");
const common = @import("../common.zig");

const Keccak = std.crypto.sha3.Keccak256;
const Hash = common.Hash;
const hash_size = common.hash_size;

const challenge_size = 8;
const challenge_difficulty = 1000;

const Challenge = [challenge_size]u8;

pub const MessageType = union(enum) {
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
    aux_job_donation,
    monero_block_broadcast,
};

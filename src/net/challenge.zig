const std = @import("std");
const common = @import("../common.zig");

const keccak = std.crypto.sha3.Keccak256;
const Hash = common.Hash;

const challenge_size = 8;
const challenge_difficulty = 1000;

const Challenge = [challenge_size]u8;

pub fn getChallengeHash(self: *Challenge, consensus_id: Hash) !Hash {
    var result = keccak();
}

const std = @import("std");
const common = @import("common.zig");
const Wallet = @This();

const address_len: usize = 95;

prefix: u64,
public_spend_key: common.Hash,
public_view_key: common.Hash,
checksum: u32,
network_type: common.NetworkType,
is_subaddress: bool,

pub fn decodeFromAddress(addr: []const u8) !Wallet {
    if (addr.len != address_len) return error.InvalidAddress;
}

pub const WalletError = error{
    InvalidAddress,
};

const std = @import("std");
const base58 = @import("base58.zig");

const Allocator = std.mem.Allocator;

// TODO
// better doc comments
// validate ed25519 pubkey as curve point

// Length of a standard Monero wallet address.
const address_len: usize = 95;

pub const Wallet = struct {
    address: []const u8 = "",

    pub fn parseAddress(allocator: Allocator, input: []const u8) AddressError!Wallet {
        var result: Wallet = .{};

        if (input.len != address_len) return error.InvalidLength;

        result.address = base58.decode(allocator, input) catch return error.InvalidBase58;

        return result;
    }

    pub fn deinit(self: *Wallet, allocator: Allocator) void {
        allocator.free(self.address);
        self.* = undefined;
    }
};

const AddressError = error{
    InvalidLength,
    InvalidBase58,
    InvalidKey,
};

test "parse address" {
    const allocator = std.testing.allocator;

    const address = "4B33mFPMq6mKi7Eiyd5XuyKRVMGVZz1Rqb9ZTyGApXW5d1aT7UBDZ89ewmnWFkzJ5wPd2SFbn313vCT8a4E2Qf4KQH4pNey";

    var wallet = try Wallet.parseAddress(allocator, address);
    defer wallet.deinit(allocator);
}

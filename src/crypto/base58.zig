const std = @import("std");

const Allocator = std.mem.Allocator;
const testing = std.testing;

const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const encoded_block_sizes = [9]usize{ 0, 2, 3, 5, 6, 7, 9, 10, 11 };
const full_block_size = encoded_block_sizes.len - 1;
const full_encoded_block_size = encoded_block_sizes[full_block_size];

/// Since this is global, it's implicitly comptime.
const reverse_alphabet = blk: {
    var table: [256]i8 = [_]i8{-1} ** 256;
    for (alphabet, 0..) |c, i| {
        table[c] = @intCast(i);
    }
    break :blk table;
};

fn decodedBlockSize(encoded_len: usize) ?usize {
    return switch (encoded_len) {
        0 => 0,
        2 => 1,
        3 => 2,
        5 => 3,
        6 => 4,
        7 => 5,
        9 => 6,
        10 => 7,
        11 => 8,
        else => null,
    };
}

/// Encodes an arbitrary-length slice into Base58.
pub fn encode(allocator: Allocator, input: []const u8) Base58Error![]const u8 {
    if (input.len == 0) return error.InvalidInput;

    const full_blocks_count = input.len / full_block_size;
    const last_block_size = input.len % full_block_size;
    const output_size =
        full_encoded_block_size * full_blocks_count + encoded_block_sizes[last_block_size];

    const output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);
    // Fill output buffer with `1`s for padding
    @memset(output, alphabet[0]);

    var in_index: usize = 0;
    var out_index: usize = 0;

    for (0..full_blocks_count) |_| {
        try encodeBlock(
            input[in_index .. in_index + full_block_size],
            full_block_size,
            output[out_index .. out_index + full_encoded_block_size],
        );
        in_index += full_block_size;
        out_index += full_encoded_block_size;
    }

    if (last_block_size > 0) {
        try encodeBlock(
            input[in_index..],
            last_block_size,
            output[out_index..],
        );
    }

    return output;
}

fn encodeBlock(input: []const u8, block_size: usize, output: []u8) Base58Error!void {
    if (block_size == 0 or input.len > full_block_size) return error.InvalidBlockSize;

    var padded: [8]u8 = .{0} ** 8;
    @memcpy(padded[8 - input.len ..], input);
    var num = std.mem.readInt(u64, &padded, .big);

    var i: isize = @intCast(encoded_block_sizes[block_size] - 1);
    while (num > 0) : (i -= 1) {
        const rem = num % alphabet.len;
        num /= alphabet.len;

        output[@intCast(i)] = alphabet[@intCast(rem)];
    }
}

/// Decodes an arbitrary-length Base58 slice.
pub fn decode(allocator: Allocator, input: []const u8) Base58Error![]const u8 {
    if (input.len == 0) return error.InvalidInput;

    const full_blocks_count = input.len / full_encoded_block_size;
    const last_block_len = input.len % full_encoded_block_size;

    const last_decoded = decodedBlockSize(last_block_len) orelse return error.InvalidLength;
    const output_size = full_block_size * full_blocks_count + last_decoded;

    const output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);

    var in_index: usize = 0;
    var out_index: usize = 0;

    for (0..full_blocks_count) |_| {
        try decodeBlock(
            input[in_index .. in_index + full_encoded_block_size],
            output[out_index .. out_index + full_block_size],
        );
        in_index += full_encoded_block_size;
        out_index += full_block_size;
    }

    if (last_block_len > 0) {
        try decodeBlock(
            input[in_index..],
            output[out_index..],
        );
    }

    return output;
}

fn decodeBlock(input: []const u8, output: []u8) Base58Error!void {
    const block_size = input.len;
    if (block_size == 0 or block_size > full_encoded_block_size) return error.InvalidBlockSize;

    const decoded_size = decodedBlockSize(block_size) orelse return error.InvalidLength;

    var num: u64 = 0;
    var order: u64 = 1;

    var i: isize = @intCast(block_size - 1);
    while (i >= 0) : (i -= 1) {
        const digit = reverse_alphabet[input[@intCast(i)]];
        if (digit < 0) return error.InvalidCharacter;

        const product = @mulWithOverflow(order, @as(u64, @intCast(digit)));
        if (product[1] != 0) return error.Overflow;

        const sum = @addWithOverflow(num, product[0]);
        if (sum[1] != 0) return error.Overflow;

        num = sum[0];
        order = @mulWithOverflow(order, alphabet.len)[0];
    }

    if (decoded_size < full_block_size and
        num >= (@as(u64, 1) << @as(u6, @intCast(decoded_size * 8))))
        return error.Overflow;

    const be = std.mem.toBytes(std.mem.nativeToBig(u64, num));
    @memcpy(output, be[8 - decoded_size ..]);
}

const Base58Error = error{
    InvalidInput,
    InvalidBlockSize,
    InvalidLength,
    InvalidCharacter,
    Overflow,
} || Allocator.Error;

test "sizes of constants" {
    try testing.expectEqual(full_block_size, 8);
    try testing.expectEqual(full_encoded_block_size, 11);
    try testing.expectEqual(alphabet.len, 58);
}

test "types of constants" {
    try testing.expectEqual(@TypeOf(full_block_size), usize);
    try testing.expectEqual(@TypeOf(full_encoded_block_size), usize);
}

test "encode address" {
    const allocator = std.testing.allocator;

    // https://github.com/monero-oxide/monero-oxide/blob/main/monero-oxide/wallet/address/src/tests.rs#L13
    // https://xmr.llcoins.net/addresstests.html
    const ascii = "4B33mFPMq6mKi7Eiyd5XuyKRVMGVZz1Rqb9ZTyGApXW5d1aT7UBDZ89ewmnWFkzJ5wPd2SFbn313vCT8a4E2Qf4KQH4pNey";
    const hex = "12f8631661f6ab4e6fda310c797330d86e23a682f20d5bc8cc27b18051191f16d74a1535063ad1fee2dabbf909d4fd9a873e29541b401f0944754e17c9a41820ce5127dad6";

    var buf: [hex.len / 2]u8 = undefined;
    const bytes = try std.fmt.hexToBytes(&buf, hex);

    const result = try encode(allocator, bytes);
    defer allocator.free(result);

    try testing.expect(std.mem.eql(u8, result, ascii));
}

test "decode address" {
    const allocator = std.testing.allocator;

    const ascii = "4B33mFPMq6mKi7Eiyd5XuyKRVMGVZz1Rqb9ZTyGApXW5d1aT7UBDZ89ewmnWFkzJ5wPd2SFbn313vCT8a4E2Qf4KQH4pNey";
    const hex = "12f8631661f6ab4e6fda310c797330d86e23a682f20d5bc8cc27b18051191f16d74a1535063ad1fee2dabbf909d4fd9a873e29541b401f0944754e17c9a41820ce5127dad6";

    var buf: [hex.len / 2]u8 = undefined;
    const expected = try std.fmt.hexToBytes(&buf, hex);

    const result = try decode(allocator, ascii);
    defer allocator.free(result);

    try testing.expectEqualSlices(u8, expected, result);
}

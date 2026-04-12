const std = @import("std");

const Allocator = std.mem.Allocator;
const testing = std.testing;

const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const encoded_block_sizes = [9]usize{ 0, 2, 3, 5, 6, 7, 9, 10, 11 };
const full_block_size = encoded_block_sizes.len - 1;
const full_encoded_block_size = encoded_block_sizes[full_block_size];
const checksum_size: usize = 4;

// Since this is global, it's implicitly comptime.
const reverse_alphabet = blk: {
    var table: [256]i8 = [_]i8{-1} ** 256;
    for (alphabet, 0..) |c, i| {
        table[c] = @intCast(i);
    }
    break :blk table;
};

/// Encodes an arbitrary-length slice into Base58.
pub fn encode(allocator: Allocator, input: []const u8) Base58Error![]const u8 {
    if (input.len == 0) return error.InvalidInput;

    const full_blocks_count = @divFloor(input.len, full_block_size);
    const last_block_size = input.len % full_block_size;
    const output_size =
        full_encoded_block_size * full_blocks_count + encoded_block_sizes[last_block_size];

    var output = try allocator.alloc(u8, output_size);
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

    var num: u64 = 0;
    for (input) |b| {
        num = (num << 8) | b;
    }

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

    const full_blocks_count = @divFloor(input.len, full_encoded_block_size);
    const last_block_size = input.len % full_encoded_block_size;
    const output_size = full_block_size * full_blocks_count + maxEncodedSize(last_block_size);

    var output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);

    var in_index: usize = 0;
    var out_index: usize = 0;

    for (0..full_blocks_count) |_| {
        try decodeBlock(
            input[in_index .. in_index + full_encoded_block_size],
            full_encoded_block_size,
            output[out_index .. out_index + full_block_size],
        );
        in_index += full_encoded_block_size;
        out_index += full_block_size;
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

fn decodeBlock(input: []const u8, block_size: usize, output: []u8) Base58Error!void {
    if (block_size == 0 or block_size > full_encoded_block_size) return error.InvalidBlockSize;

    const decoded_size = @min(block_size, output.len);

    if (decoded_size == 0) return error.InvalidLength;

    var num: u64 = 0;
    var order: u64 = 1;

    var i: isize = @intCast(block_size - 1);

    while (i >= 0) : (i -= 1) {
        const char = input[@intCast(i)];

        const digit = reverse_alphabet[char];
        if (digit < 0) return error.InvalidCharacter;

        const product = @mulWithOverflow(order, @as(u64, @intCast(digit)));
        if (product[1] != 0) return error.Overflow;

        const sum = @addWithOverflow(num, product[0]);
        if (sum[1] != 0) return error.Overflow;

        num = sum[0];
        order = @mulWithOverflow(order, alphabet.len)[0];
    }

    if (decoded_size < full_block_size) {
        if (num >= (@as(u64, 1) << @as(u6, @intCast(decoded_size * 8)))) return error.Overflow;
    }

    var tmp = num;
    var j: isize = @intCast(decoded_size - 1);

    while (j >= 0) : (j -= 1) {
        output[@intCast(j)] = @intCast(tmp & 0xFF);
        tmp >>= 8;
    }
}

fn maxEncodedSize(size: usize) usize {
    const bits_count = @as(u64, size) * 8;
    var max: u64 =
        if (bits_count == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(bits_count)) - 1;

    var i: usize = 0;
    while (max != 0) : (i += 1) {
        max /= alphabet.len;
    }
    return i;
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

test "decode address" {
    const allocator = std.testing.allocator;
    const address = "4B33mFPMq6mKi7Eiyd5XuyKRVMGVZz1Rqb9ZTyGApXW5d1aT7UBDZ89ewmnWFkzJ5wPd2SFbn313vCT8a4E2Qf4KQH4pNey";

    // This is broken again :((
    const result = try decode(allocator, address);
    defer allocator.free(result);
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

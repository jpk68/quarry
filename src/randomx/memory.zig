const std = @import("std");
const Argon2 = @import("Argon2.zig");

const argon_memory = 262144;

pub const argon_iterations = 3;
pub const argon_lanes = 1;
pub const argon_salt = "RandomX\x03";

const superscalar_mul_0: u64 = 6364136223846793005;
const superscalar_add_1: u64 = 9298411001130361340;
const superscalar_add_2: u64 = 12065312585734608966;
const superscalar_add_3: u64 = 9306329213124626780;
const superscalar_add_4: u64 = 5281919268842080866;
const superscalar_add_5: u64 = 10536153434571861004;
const superscalar_add_6: u64 = 3398623926847679864;
const superscalar_add_7: u64 = 9549104520008361294;

pub const Cache = struct {
    blocks: u64,

    pub fn init(key: []const u8, cache: [cache_size]u8) void {
        var argon_inst = Argon2.init();

        var memory_blocks: u32 = argon_memory;

        const segment_size: usize = memory_blocks / (argon_lanes * argon_sync_points);

        argon_inst.passes = argon_iterations;
        argon_inst.memory_blocks = memory_blocks;
        argon_inst.segment_size = segment_size;

        const allocator = std.heap.page_allocator;
        const self = try allocator.alloc(argon_memory);
        return self;
    }
};

pub const Dataset = struct {
    jit_buf: [48 * 1024]u8,

    pub fn init(key: u32) !*Dataset {
        // TODO
        var register_value = 0;

        dataset[0] = undefined;
        dataset[1] = ds[0] ^ superscalar_add_1;
    }

    pub fn read(self: *Dataset) void {}
};

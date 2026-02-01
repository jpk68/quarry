const common = @import("common.zig");

entropy_buffer: [16]u64,
program_buffer: [common.program_size]Instruction,

pub const Instruction = struct {
    const Self = @This();

    opcode: Opcode,
    dst: u8,
    src: u8,
    mod: u8,
    imm32: u32,

    pub fn getImm32(self: *Self) u32 {}
    pub fn setImm32(self: *Self) void {}
};

pub const Opcode = enum(u8) {
    iadd_rs = 0,
    iadd_m = 1,
    isub_r = 2,
    isub_m = 3,
    imul_r = 4,
    imul_m = 5,
    imulh_r = 6,
    imulh_m = 7,
    ismulh_r = 8,
    ismulh_m = 9,
    imul_rcp = 10,
    ineg_r = 11,
    ixor_r = 12,
    ixor_m = 13,
    iror_r = 14,
    irol_r = 15,
    iswap_r = 16,
    fswap_r = 17,
    fadd_r = 18,
    fadd_m = 19,
    fsub_r = 20,
    fsub_m = 21,
    fscal_r = 22,
    fmul_r = 23,
    fdiv_m = 24,
    fsqrt_r = 25,
    cbranch = 26,
    cfround = 27,
    istore = 28,
    nop = 29,
};

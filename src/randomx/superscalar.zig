const superscalar_latency = @import("common.zig").superscalar_latency;
const buf_size = 3 * superscalar_latency + 2;

pub const SuperscalarProgram = struct {
    program_buf: [buf_size]SuperscalarInstruction,
};

pub const SuperscalarInstruction = struct {
    opcode: SuperscalarOpcode,
    dst: u8,
    src: u8,
};

pub const SuperscalarOpcode = enum(u8) {
    isub_r = 0,
    ixor_r = 1,
    iadd_rs = 2,
    imul_r = 3,
    iror_c = 4,
    iadd_c7 = 5,
    ixor_c7 = 6,
    iadd_c8 = 7,
    ixor_c8 = 8,
    iadd_c9 = 9,
    ixor_c9 = 10,
    imulh_r = 11,
    ismulh_r = 12,
    imul_rcp = 13,
};

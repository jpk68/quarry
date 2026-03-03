const std = @import("std");

const aes_gen_1r_key0 = [_]u32{ 0xb4f44917, 0xdbb5552b, 0x62716609, 0x6daca553 };
const aes_gen_1r_key1 = [_]u32{ 0x0da1dc4e, 0x1725d378, 0x846a710d, 0x6d7caf07 };
const aes_gen_1r_key2 = [_]u32{ 0x3e20e345, 0xf4c0794f, 0x9f947ec6, 0x3f1262f1 };
const aes_gen_1r_key3 = [_]u32{ 0x49169154, 0x16314c88, 0xb1ba317c, 0x6aef8135 };

// TODO
// Soft AES with hardcoded initial state
// Hardware-based one with inline asm

const std = @import("std");
const Program = @import("Program.zig");
const memory = @import("memory.zig");

const Scratchpad = memory.Scratchpad;
const Dataset = memory.Dataset;

pub const VirtualMachine = struct {
    program: Program,
    register_file: RegisterFile,
    scratchpad: Scratchpad,

    dataset: *Dataset,
    dataset_offset: u64,
};

pub const RegisterFile = struct {
    r: [8]u64,
    f: [4]u128,
    e: [4]u128,
    a: [4]u128,

    ma: u32,
    mx: u32,
    fprc: u2,
};

const std = @import("std");

peer_id: u64,

pub const ProtocolVersion = enum(u32) {
    @"1.0" = 0x00010000,
    @"1.1" = 0x00010001,
    @"1.2" = 0x00010002,
    @"1.3" = 0x00010003,
    @"1.4" = 0x00010004,
};

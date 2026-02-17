const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

const Client = @This();

allocator: Allocator,
io: Io,

stream: net.Stream,

reader: *Io.Reader,
writer: *Io.Writer,

queue: *Io.Queue(u8),
queue_lock: std.Mutex = .init,

pub const ProtocolVersion = enum(u32) {
    @"1.0" = 0x00010000,
    @"1.1" = 0x00010001,
    @"1.2" = 0x00010002,
    @"1.3" = 0x00010003,
    @"1.4" = 0x00010004,
};

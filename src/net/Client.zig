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

const std = @import("std");
const builtin = @import("builtin");

const Io = std.Io;

const Config = @import("Config.zig");
const App = @import("App.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa_inst: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (builtin.mode == .Debug) gpa_inst.allocator() else std.heap.smp_allocator;

    defer if (builtin.mode == .Debug) {
        _ = gpa_inst.deinit();
    };

    var threaded: Io.Threaded = .init(allocator);
    defer threaded.deinit();

    const config = try Config.init(threaded, init.args);

    const app = try App.init(allocator, threaded, &config);
    try app.run();
}

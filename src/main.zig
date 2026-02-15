const std = @import("std");
const builtin = @import("builtin");

const Io = std.Io;

const Config = @import("Config.zig");
const App = @import("App.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    // Use DebugAllocator in Debug mode to detect memory leaks.
    // SmpAllocator is used in Release modes.
    var gpa_inst: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (builtin.mode == .Debug) gpa_inst.allocator() else std.heap.smp_allocator;

    defer if (builtin.mode == .Debug) {
        _ = gpa_inst.deinit();
    };

    var io_inst: Io.Threaded = .init(allocator);
    defer io_inst.deinit();
    const io = io_inst.io();

    const config = try Config.init(io, init.args);

    const app = try App.init(allocator, io, &config);
    return app.run();
}

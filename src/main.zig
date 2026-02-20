const std = @import("std");
const builtin = @import("builtin");

const Config = @import("Config.zig");
const App = @import("App.zig");

const Io = std.Io;
const log = std.log.scoped(.main);

// TODO
// Set custom log function with std.Options

pub fn main(init: std.process.Init.Minimal) !void {
    // DebugAllocator is used in Debug mode to detect memory leaks.
    // SmpAllocator is used in Release modes.
    var gpa_inst: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (builtin.mode == .Debug) gpa_inst.allocator() else std.heap.smp_allocator;

    defer if (builtin.mode == .Debug) {
        _ = gpa_inst.deinit();
    };

    var io_inst: Io.Threaded = .init(allocator, .{
        .environ = init.environ,
        .argv0 = .init(init.args),
    });
    defer io_inst.deinit();
    const io = io_inst.io();

    log.debug("Attempting to set config options from args", .{});
    var config = try Config.parseArgs(io, init.args);

    log.debug("Attempting to create and run app", .{});
    const app = try App.init(allocator, io, &config);
    return app.run();
}

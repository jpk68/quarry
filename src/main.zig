const std = @import("std");
const builtin = @import("builtin");

const Config = @import("Config.zig");
const App = @import("App.zig");

const Io = std.Io;
const log = std.log.scoped(.main);

// TODO
// Use a custom log function with std.Options
// Use some dependency (or use libc) to get date/time

pub fn main(init: std.process.Init.Minimal) !void {
    // DebugAllocator is used in Debug mode to detect memory leaks.
    // SmpAllocator is used in Release modes.
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.smp_allocator;

    defer if (builtin.mode == .Debug) {
        _ = gpa.deinit();
    };

    var threaded: Io.Threaded = .init(allocator, .{
        .environ = init.environ,
        .argv0 = .init(init.args),
    });
    defer threaded.deinit();
    const io = threaded.io();

    log.debug("Attempting to load config from args", .{});
    var config = try Config.initFromArgs(allocator, init.args);

    log.debug("Running main loop", .{});
    const app = try App.init(allocator, io, &config);

    return app.run();
}

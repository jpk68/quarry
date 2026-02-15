const std = @import("std");
const Io = std.Io;

const Config = @import("Config.zig");
const App = @import("App.zig");

// TODO
// Use appropriate allocator per build mode

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: Io.Threaded = .init(allocator);
    defer threaded.deinit();

    const config = try Config.init(threaded, init.args);

    const app = try App.init(allocator, threaded, &config);
    try app.run();
}

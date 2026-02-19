const std = @import("std");
const builtin = @import("builtin");

const Config = @import("Config.zig");
const App = @import("App.zig");

const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var config = try Config.init(io, init.minimal.args);

    const app = try App.init(allocator, io, &config);
    return app.run();
}

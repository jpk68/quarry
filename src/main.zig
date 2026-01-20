const std = @import("std");
const Config = @import("config.zig").Config;

pub fn main(init: std.process.Init) !void {
    const config = Config.init();

    var args = init.minimal.args.iterate();
    _ = args.next();

    while (args.next()) |arg| {
        std.log.debug("arg: {s}", .{arg});
    }

    _ = config;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: quarry <options>
        \\
        \\Options:
        \\  --help, -h      Print help message
        \\  --version, -v   Print version info
        \\
    , .{});
}

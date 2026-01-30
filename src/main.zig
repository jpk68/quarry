const std = @import("std");
const Config = @import("config.zig").Config;

const version_string: []const u8 = "0.0.0";

pub fn main(init: std.process.Init) !void {
    // Init config with default options
    var config = Config.init();

    var args = init.minimal.args.iterate();
    // Throw away first arg (program name)
    _ = args.next();

    while (args.next()) |arg| {
        std.log.debug("Received arg: {s}", .{arg});

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            std.debug.print("Quarry v{s}\n", .{version_string});
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--rpc-port")) {
            if (args.next()) |port| {
                config.node_rpc_port = std.fmt.parseInt(u16, port, 10) catch {
                    std.log.err("Invalid port number: '{s}'", .{port});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for '{s}'", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--zmq-port")) {
            if (args.next()) |port| {
                config.node_zmq_port = std.fmt.parseInt(u16, port, 10) catch {
                    std.log.err("Invalid port number: '{s}'", .{port});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for '{s}'", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--max-peers-outgoing")) {
            if (args.next()) |n| {
                config.max_peers_outgoing = std.fmt.parseInt(u32, n, 10) catch {
                    std.log.err("Invalid number: '{s}'", .{n});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for '{s}'", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--max-peers-incoming")) {
            if (args.next()) |n| {
                config.max_peers_incoming = std.fmt.parseInt(u32, n, 10) catch {
                    std.log.err("Invalid number: '{s}'", .{n});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for '{s}'", .{arg});
                std.process.exit(1);
            }
        } else {
            std.log.err("Invalid command: '{s}'", .{arg});
            std.process.exit(1);
        }
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: quarry <options>
        \\
        \\Options:
        \\  --help, -h      Print help message
        \\  --version, -v   Print version info
        \\
        \\  --rpc-port      RPC port of Monero daemon (default: 18081)
        \\  --zmq-port      ZMQ port of Monero daemon (default: 18083)
        \\
    , .{});
}

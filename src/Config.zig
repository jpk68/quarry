const std = @import("std");
const Io = std.Io;

const common = @import("common.zig");

// TODO
// Add config options for data_dir and node_ip
// Use more sane defaults
// Don't use current directory to store everything

const version_string: []const u8 = "0.0.0";

const usage =
    \\Usage: quarry <options>
    \\
    \\Options:
    \\  --help                  Print help message
    \\  --version               Print version info
    \\
    \\  --network               Monero network type (default: Mainnet)
    \\  --sidechain             P2Pool sidechain type (default: Main)
    \\
    \\  --rpc-port              RPC port of Monero daemon (default: 18081)
    \\  --zmq-port              ZMQ port of Monero daemon (default: 18083)
    \\
    \\  --max-peers-outgoing    Maximum number of outgoing peers (default: 10)
    \\  --max-peers-incoming    Maximum number of incoming peers (default: 450)
    \\
;

const Config = @This();

network_type: common.NetworkType = .mainnet,
sidechain_type: common.SidechainType = .main,

node_rpc_port: u16 = 18081,
node_zmq_port: u16 = 18083,

max_peers_outgoing: u32 = 10,
max_peers_incoming: u32 = 450,

data_dir: ?Io.Dir = null,

fn parseArgs(io: Io, args: std.process.Args) !Config {
    var result: Config = .{};

    // Get iterator and throw away first arg (program name)
    var args_it = args.iterate();
    _ = args_it.next();

    var arg_i: usize = 0;
    while (args_it.next()) |arg| : (arg_i += 1) {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try Io.File.stdout().writeStreamingAll(io, usage);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            try Io.File.stdout().writeStreamingAll(io, "Quarry v" ++ version_string);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--network")) {
            if (args_it.next()) |s| {
                result.network_type = std.meta.stringToEnum(common.NetworkType, s) orelse {
                    std.log.err("Invalid network type: {s}", .{s});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--sidechain")) {
            if (args_it.next()) |s| {
                result.sidechain_type = std.meta.stringToEnum(common.SidechainType, s) orelse {
                    std.log.err("Invalid sidechain type: {s}", .{s});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--rpc-port")) {
            if (args_it.next()) |port| {
                result.node_rpc_port = std.fmt.parseInt(u16, port, 10) catch {
                    std.log.err("Invalid port number: {s}", .{port});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--zmq-port")) {
            if (args_it.next()) |port| {
                result.node_zmq_port = std.fmt.parseInt(u16, port, 10) catch {
                    std.log.err("Invalid port number: {s}", .{port});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--max-peers-outgoing")) {
            if (args_it.next()) |n| {
                result.max_peers_outgoing = std.fmt.parseInt(u32, n, 10) catch {
                    std.log.err("Invalid number: {s}", .{n});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--max-peers-incoming")) {
            if (args_it.next()) |n| {
                result.max_peers_incoming = std.fmt.parseInt(u32, n, 10) catch {
                    std.log.err("Invalid number: {s}", .{n});
                    std.process.exit(1);
                };
            } else {
                std.log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else {
            std.log.err("Invalid option: {s}", .{arg});
            std.process.exit(1);
        }
    }

    result.data_dir = Io.Dir.cwd();

    return result;
}

const std = @import("std");
const common = @import("common.zig");

const Io = std.Io;
const log = std.log.scoped(.config);

const Config = @This();

// TODO
// Add config options for node_addr and data_dir

network: common.NetworkType = .mainnet,
sidechain: common.SidechainType = .main,
node_addr: []const u8 = "127.0.0.1",
node_rpc_port: u16 = 18081,
node_zmq_port: u16 = 18083,
// Maybe these should be changed..?
max_peers_outgoing: u32 = 10,
max_peers_incoming: u32 = 450,
data_dir: Io.Dir = Io.Dir.cwd(),

pub fn initFromArgs(io: Io, args: std.process.Args) !Config {
    var result: Config = .{};

    // Get iterator and throw away first argument (executable name)
    var args_it = args.iterate();
    _ = args_it.next();

    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            exitHelp();
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            exitVersion();
        } else if (std.mem.eql(u8, arg, "--network")) {
            if (args_it.next()) |s| {
                result.network_type = std.meta.stringToEnum(common.NetworkType, s) orelse {
                    log.err("Invalid network type: {s}", .{s});
                    std.process.exit(1);
                };
            } else {
                log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--sidechain")) {
            if (args_it.next()) |s| {
                result.sidechain_type = std.meta.stringToEnum(common.SidechainType, s) orelse {
                    log.err("Invalid sidechain type: {s}", .{s});
                    std.process.exit(1);
                };
            } else {
                log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--rpc-port")) {
            if (args_it.next()) |port| {
                result.node_rpc_port = std.fmt.parseInt(u16, port, 10) catch {
                    log.err("Invalid port number: {s}", .{port});
                    std.process.exit(1);
                };
            } else {
                log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--zmq-port")) {
            if (args_it.next()) |port| {
                result.node_zmq_port = std.fmt.parseInt(u16, port, 10) catch {
                    log.err("Invalid port number: {s}", .{port});
                    std.process.exit(1);
                };
            } else {
                log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--max-peers-outgoing")) {
            if (args_it.next()) |n| {
                result.max_peers_outgoing = std.fmt.parseInt(u32, n, 10) catch {
                    log.err("Invalid number: {s}", .{n});
                    std.process.exit(1);
                };
            } else {
                log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--max-peers-incoming")) {
            if (args_it.next()) |n| {
                result.max_peers_incoming = std.fmt.parseInt(u32, n, 10) catch {
                    log.err("Invalid number: {s}", .{n});
                    std.process.exit(1);
                };
            } else {
                log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
        } else {
            log.err("Invalid option: {s}", .{arg});
            std.process.exit(1);
        }
    }

    return result;
}

// This will be replaced with the build script's version number after the next Zig release.
const version_string: []const u8 = "0.0.0";

fn exitHelp() noreturn {
    std.debug.print(
        \\Usage: quarry [options]
        \\
        \\Options:
        \\  --help                  Print this help message
        \\  --version               Print version and build info
        \\
        \\  --network               Monero network to connect to
        \\  --sidechain             P2Pool sidechain to mine on
        \\
        \\  --node                  Address of Monero node
        \\  --rpc-port              RPC port of Monero daemon
        \\  --zmq-port              ZMQ port of Monero daemon
        \\
        \\  --max-peers-outgoing    Maximum number of outgoing peers
        \\  --max-peers-incoming    Maximum number of incoming peers
        \\
    , .{});

    std.process.exit(0);
}

fn exitVersion() noreturn {
    std.debug.print("Quarry {s}\n", .{version_string});
    std.process.exit(0);
}

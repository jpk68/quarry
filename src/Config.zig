const std = @import("std");
const builtin = @import("builtin");

const build = @import("build.zig.zon");
const common = @import("common.zig");
const Wallet = @import("crypto/wallet.zig").Wallet;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const log = std.log.scoped(.config);

const Config = @This();

// TODO
// add config options for node_addr and data_dir
// actually validate length/validity of addresses instead of just decoding them
// deinit wallet struct on exit

network_type: common.NetworkType = .mainnet,
sidechain_type: common.SidechainType = .main,
node_addr: []const u8 = "127.0.0.1",
node_rpc_port: u16 = 18081,
node_zmq_port: u16 = 18083,
max_peers_outgoing: u32 = 10,
max_peers_incoming: u32 = 450,
wallet: Wallet = .{},
//data_dir: Io.Dir = Io.Dir.cwd(),

pub fn initFromArgs(allocator: Allocator, args: std.process.Args) !Config {
    var result: Config = .{};

    // Get iterator and throw away first argument (executable name)
    var args_it = args.iterate();
    _ = args_it.next();

    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            exitHelp();
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            exitVersion();
        } else if (std.mem.eql(u8, arg, "--wallet") or std.mem.eql(u8, arg, "-w")) {
            if (args_it.next()) |s| {
                result.wallet = Wallet.parseAddress(allocator, @constCast(s)) catch {
                    log.err("Invalid Monero address: {s}", .{s});
                    std.process.exit(1);
                };
            } else {
                log.err("An argument must be provided for {s}", .{arg});
                std.process.exit(1);
            }
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
        } else if (std.mem.eql(u8, arg, "--node")) {
            if (args_it.next()) |s| {
                result.node_addr = s;
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

fn exitHelp() noreturn {
    std.debug.print(
        \\Usage: quarry [options]
        \\
        \\Options:
        \\  --help, -h              Print this help message
        \\  --version, -v           Print version and build info
        \\
        \\  --wallet, -w            Monero wallet address to send payouts to
        \\
        \\  --node                  IP address of Monero node
        \\  --rpc-port              RPC port of Monero daemon
        \\  --zmq-port              ZMQ port of Monero daemon
        \\
        \\  --network               Monero network to connect to
        \\  --sidechain             P2Pool sidechain to mine on
        \\
        \\  --max-peers-outgoing    Maximum number of outgoing peers
        \\  --max-peers-incoming    Maximum number of incoming peers
        \\
        \\
    , .{});

    std.process.exit(0);
}

fn exitVersion() noreturn {
    std.debug.print("Quarry v{s}\n", .{build.version});
    if (builtin.mode == .Debug) std.debug.print("{s}\n", .{build.minimum_zig_version});

    std.process.exit(0);
}

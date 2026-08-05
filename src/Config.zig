const std = @import("std");
const builtin = @import("builtin");

const build = @import("build.zig.zon");
const common = @import("common.zig");
const Wallet = @import("crypto/wallet.zig").Wallet;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Args = std.process.Args;
const log = std.log.scoped(.config);

const Config = @This();

// TODO
// add config option for data_dir
// deinit wallet struct on exit

network_type: common.NetworkType = .mainnet,
sidechain_type: common.SidechainType = .main,
node_addr: Io.net.IpAddress = Io.net.IpAddress.parseLiteral("127.0.0.1") catch unreachable,
node_rpc_port: u16 = 18081,
node_zmq_port: u16 = 18083,
max_peers_outgoing: u32 = 10,
max_peers_incoming: u32 = 450,
wallet: Wallet = .{},
//data_dir: Io.Dir = Io.Dir.cwd(),

const Flag = enum {
    help,
    version,
    wallet,
    node,
    @"rpc-port",
    @"zmq-port",
    network,
    sidechain,
    @"max-peers-outgoing",
    @"max-peers-incoming",
};

const short_aliases = std.StaticStringMap(Flag).initComptime(.{
    .{ "-h", .help },
    .{ "-v", .version },
    .{ "-w", .wallet },
});

fn nextArg(args_it: *Args.Iterator, name: []const u8) [:0]const u8 {
    return args_it.next() orelse {
        log.err("An argument must be provided for {s}", .{name});
        std.process.exit(1);
    };
}

fn nextIntArg(comptime T: type, args_it: *Args.Iterator, name: []const u8, comptime label: []const u8) T {
    const input = nextArg(args_it, name);
    return std.fmt.parseInt(T, input, 10) catch {
        log.err("Invalid " ++ label ++ ": {s}", .{input});
        std.process.exit(1);
    };
}

fn nextEnumArg(comptime T: type, args_it: *Args.Iterator, name: []const u8, comptime label: []const u8) T {
    const input = nextArg(args_it, name);
    return std.meta.stringToEnum(T, input) orelse {
        log.err("Invalid " ++ label ++ ": {s}", .{input});
        std.process.exit(1);
    };
}

pub fn initFromArgs(allocator: Allocator, args: Args) !Config {
    var result: Config = .{};

    // Get iterator and throw away first argument (executable name)
    var args_it = args.iterate();
    _ = args_it.next();

    while (args_it.next()) |arg| {
        const flag = short_aliases.get(arg) orelse blk: {
            if (!std.mem.startsWith(u8, arg, "--")) {
                log.err("Invalid option: {s}", .{arg});
                std.process.exit(1);
            }
            break :blk std.meta.stringToEnum(Flag, arg[2..]) orelse {
                log.err("Invalid option: {s}", .{arg});
                std.process.exit(1);
            };
        };

        switch (flag) {
            .help => exitHelp(),
            .version => exitVersion(),
            .wallet => {
                const input = nextArg(&args_it, arg);
                result.wallet = Wallet.parseAddress(allocator, input) catch {
                    log.err("Invalid Monero address: {s}", .{input});
                    std.process.exit(1);
                };
            },
            .node => {
                const input = nextArg(&args_it, arg);
                result.node_addr = Io.net.IpAddress.parseLiteral(input) catch {
                    log.err("Invalid IP address: {s}", .{input});
                    std.process.exit(1);
                };
            },
            .@"rpc-port" => result.node_rpc_port = nextIntArg(u16, &args_it, arg, "port number"),
            .@"zmq-port" => result.node_zmq_port = nextIntArg(u16, &args_it, arg, "port number"),
            .network => result.network_type = nextEnumArg(common.NetworkType, &args_it, arg, "network type"),
            .sidechain => result.sidechain_type = nextEnumArg(common.SidechainType, &args_it, arg, "sidechain type"),
            .@"max-peers-outgoing" => result.max_peers_outgoing = nextIntArg(u32, &args_it, arg, "number"),
            .@"max-peers-incoming" => result.max_peers_incoming = nextIntArg(u32, &args_it, arg, "number"),
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
    , .{});

    std.process.exit(0);
}

fn exitVersion() noreturn {
    std.debug.print("Quarry v{s}\n", .{build.version});
    if (builtin.mode == .Debug) std.debug.print("{s}\n", .{build.minimum_zig_version});

    std.process.exit(0);
}

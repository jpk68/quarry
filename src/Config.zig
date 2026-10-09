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
/// P2Pool stratum server to mine on. When set, Quarry runs as a miner.
pool: ?Pool = null,
/// Worker name sent at login; P2Pool also accepts "name+difficulty" for a fixed share difficulty.
user: []const u8 = "quarry",
/// Mining threads; 0 means as many as the L3 cache fits (see `Miner.defaultThreadCount`).
threads: u32 = 0,
/// Mine in RandomX light mode (256 MiB) instead of fast mode (~2.3 GiB).
light: bool = false,
//data_dir: Io.Dir = Io.Dir.cwd(),

pub const Pool = struct {
    host: []const u8,
    port: u16,

    /// Parses "host:port" or "[ipv6]:port".
    pub fn parse(text: []const u8) !Pool {
        const colon = std.mem.lastIndexOfScalar(u8, text, ':') orelse return error.MissingPort;
        var host = text[0..colon];
        if (host.len >= 2 and host[0] == '[' and host[host.len - 1] == ']') host = host[1 .. host.len - 1];
        if (host.len == 0) return error.MissingHost;
        return .{ .host = host, .port = try std.fmt.parseInt(u16, text[colon + 1 ..], 10) };
    }
};

const Flag = enum {
    help,
    version,
    wallet,
    pool,
    user,
    threads,
    light,
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
            .pool => {
                const input = nextArg(&args_it, arg);
                result.pool = Pool.parse(input) catch {
                    log.err("Invalid pool address (expected host:port): {s}", .{input});
                    std.process.exit(1);
                };
            },
            .user => result.user = nextArg(&args_it, arg),
            .threads => result.threads = nextIntArg(u32, &args_it, arg, "thread count"),
            .light => result.light = true,
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
        \\  --pool                  Mine on a P2Pool stratum server (host:port, e.g. 127.0.0.1:3333)
        \\  --user                  Worker name to log in with (default: quarry)
        \\  --threads               Number of mining threads (default: L3 cache size / 2 MiB)
        \\  --light                 Use RandomX light mode (256 MiB instead of ~2.3 GiB, much slower)
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

test "parse pool address" {
    const a = try Pool.parse("127.0.0.1:3333");
    try std.testing.expectEqualStrings("127.0.0.1", a.host);
    try std.testing.expectEqual(3333, a.port);
    const b = try Pool.parse("[::1]:3334");
    try std.testing.expectEqualStrings("::1", b.host);
    const c = try Pool.parse("node.example:3333");
    try std.testing.expectEqualStrings("node.example", c.host);
    try std.testing.expectError(error.MissingPort, Pool.parse("localhost"));
    try std.testing.expectError(error.MissingHost, Pool.parse(":3333"));
}

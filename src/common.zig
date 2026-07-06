/// Type used to represent a 4-byte message digest.
pub const hash_size: usize = 32;
pub const Hash = [hash_size]u8;

/// Type used to represent the network's mining difficulty.
pub const Difficulty = u128;

/// The Monero network being used.
pub const NetworkType = enum { mainnet, testnet, stagenet };

/// The P2Pool sidechain being used.
pub const SidechainType = enum { main, mini, nano };

/// P2Pool protocol version.
pub const ProtocolVersion = enum(u32) {
    @"1.0" = 0x00010000,
    @"1.1" = 0x00010001,
    @"1.2" = 0x00010002,
    @"1.3" = 0x00010003,
    @"1.4" = 0x00010004,
};

/// P2Pool software ID.
pub const SoftwareId = enum(u32) {
    P2Pool = 0,
    GoObserver = 0x624F6F47,
    Unknown = 0xFFFFFFFF,
};

/// P2Pool sidechain parameters.
pub const SidechainParams = struct {
    network_type: NetworkType,
    pool_name: []const u8,
    target_block_time: u32,
    minimum_difficulty: u64,
    chain_window_size: u32,
    uncle_penalty: u16,
    id: Hash,
};

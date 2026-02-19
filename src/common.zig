pub const hash_size: usize = 32;
pub const Hash = [hash_size]u8;

pub const NetworkType = enum {
    mainnet,
    testnet,
    stagenet,
};

pub const SidechainType = enum {
    main,
    mini,
    nano,
};

pub const ProtocolVersion = enum(u32) {
    @"1.0" = 0x00010000,
    @"1.1" = 0x00010001,
    @"1.2" = 0x00010002,
    @"1.3" = 0x00010003,
    @"1.4" = 0x00010004,
};

pub const SoftwareId = enum(u32) {
    P2Pool = 0,
    GoObserver = 0x624F6F47,
    Unknown = 0xFFFFFFFF,
};

pub const SidechainParams = struct {
    network_type: NetworkType,
    pool_name: []const u8,
    target_block_time: u32,
    minimum_difficulty: u64,
    chain_window_size: u32,
    uncle_penalty: u16,
    id: Hash,
};

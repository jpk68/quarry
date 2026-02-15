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

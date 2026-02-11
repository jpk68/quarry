// TODO
// {root,indexed}_hash
// tx_mempool_data
// aux_chain_data
// miner_data
// main_chain
// monero_block_broadcast_header

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

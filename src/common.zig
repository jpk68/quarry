// TODO
// {root,indexed}_hash
// tx_mempool_data
// aux_chain_data
// miner_data
// main_chain
// monero_block_broadcast_header

pub const Hash = [32]u8;

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

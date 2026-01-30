const common = @import("common.zig");

pub const Config = struct {
    network_type: common.NetworkType,
    sidechain_type: common.SidechainType,

    node_rpc_port: u16,
    node_zmq_port: u16,

    max_peers_outgoing: u32,
    max_peers_incoming: u32,

    pub fn init() Config {
        return .{
            .network_type = .mainnet,
            .sidechain_type = .main,

            .node_rpc_port = 18081,
            .node_zmq_port = 18083,

            .max_peers_outgoing = 10,
            .max_peers_incoming = 450,
        };
    }
};

pub const MessageType = enum {
    handshake_challenge,
    handshake_solution,
    listen_port,
    block_request,
    block_response,
    block_broadcast,
    peer_list_request,
    peer_list_response,
    block_broadcast_compact,
    block_notify,
    aux_job_donation,
    monero_block_broadcast,
};

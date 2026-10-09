# PoW/RandomX info

Quarry hashes with [zig-randomx](https://github.com/NateBrune/zig-randomx), a Zig port of RandomX
with an x86-64 JIT and an interpreter. It is pinned in `build.zig.zon`.

Monero mainnet, and so every P2Pool sidechain, uses RandomX v1 until the RandomX v2 hard fork
activates; VMs are created with `.version = .v1`.

zig-randomx currently requires an x86-64 CPU with AES-NI.

# Quarry

Alternative client software for mining Monero with P2Pool.

## Status

Quarry can mine on a [P2Pool](https://github.com/SChernykh/p2pool) node through its stratum
server, like XMRig does. Running as a P2Pool node itself is still a work in progress.

## Mining on P2Pool

Start P2Pool with your wallet address (payouts go to the wallet P2Pool was started with), then
point Quarry at its stratum port:

```bash
quarry --pool 127.0.0.1:3333
```

Options:

- `--threads N`: mining threads (default: one per 2 MiB of L3 cache, which is what RandomX needs
  per thread; more threads than that add little)
- `--light`: RandomX light mode, using 256 MiB instead of ~2.3 GiB, but much slower
- `--user NAME`: worker name shown by P2Pool; `NAME+DIFF` requests a fixed share difficulty

Build with `zig build --release=fast` for full hashing speed (release builds use LLVM; the
self-hosted backend's code hashes about 5x slower). Mining needs an x86-64 CPU with
AES-NI.

## Full setup: Monero node, P2Pool and Quarry

Mining on P2Pool takes three programs, each in its own terminal: a Monero node (`monerod`), a
P2Pool node, and Quarry as the miner.

### 1. Monero node (pruned)

Download the latest CLI release from [getmonero.org](https://www.getmonero.org/downloads/) and
verify it against the signed `hashes.txt`
([guide](https://www.getmonero.org/resources/user-guides/verification-allos-advanced.html)):

```bash
mkdir -p ~/monero && cd ~/monero
curl -L -o monero.tar.bz2 https://downloads.getmonero.org/cli/linux64   # latest release
curl -LO https://www.getmonero.org/downloads/hashes.txt
curl -LO https://raw.githubusercontent.com/monero-project/monero/master/utils/gpg_keys/binaryfate.asc
gpg --import binaryfate.asc && gpg --verify hashes.txt   # "Good signature from binaryFate"
sha256sum monero.tar.bz2   # must equal the monero-linux-x64 line in hashes.txt
tar xjf monero.tar.bz2 && ln -sfn monero-x86_64-linux-gnu-v* current
```

Run it with ZMQ enabled (P2Pool needs it) and pruning (about a third of the full chain's disk
use; plan for ~75 GB, growing ~10 GB per year):

```bash
~/monero/current/monerod --data-dir ~/.bitmonero --prune-blockchain \
  --zmq-pub tcp://127.0.0.1:18083 --out-peers 32 --in-peers 64 \
  --add-priority-node=p2pmd.xmrvsbeast.com:18080 --add-priority-node=nodes.hashvault.pro:18080 \
  --enforce-dns-checkpointing --enable-dns-blocklist
```

- The blockchain is stored in `~/.bitmonero/lmdb/`; the log is `~/.bitmonero/bitmonero.log`.
- Type `status` in the monerod window to see sync progress, and `exit` to stop it cleanly.
- The first sync takes hours to days. P2Pool can't start until it's done.
- With less than 10 Mbit/s of upload, use `--out-peers 8 --in-peers 16`.
- Optionally open port 18080 (Monero P2P) in your firewall for better connectivity.

### 2. P2Pool node

Download the latest `linux-x64` release from
[GitHub](https://github.com/SChernykh/p2pool/releases) along with `sha256sums.txt.asc`, and check
it against SChernykh's signature (key `1FCA AB4D 3DC3 310D 16CB D508 C47F 82B5 4DA8 7ADF`):

```bash
curl -sSL https://keys.openpgp.org/vks/v1/by-fingerprint/1FCAAB4D3DC3310D16CBD508C47F82B54DA87ADF | gpg --import
gpg --verify sha256sums.txt.asc                  # "Good signature from SChernykh"
sha256sum p2pool-v*-linux-x64.tar.gz             # must match the SHA256 listed for it
tar xzf p2pool-v*-linux-x64.tar.gz
```

Or build it from source (Fedora shown; see its
[build instructions](https://github.com/SChernykh/p2pool#build-instructions) for others). The
gRPC dependency, needed only for Tari merge mining, makes this take a while; `cmake
-DWITH_GRPC=OFF ..` skips it:

```bash
sudo dnf install git cmake gcc-c++ libuv-devel zeromq-devel libsodium-devel openpgm-devel libcurl-devel
git clone --recursive https://github.com/SChernykh/p2pool
cd p2pool && mkdir build && cd build
cmake .. && make -j$(nproc)
```

Once monerod is fully synced, start P2Pool with the wallet that receives payouts:

```bash
./p2pool --host 127.0.0.1 --wallet YOUR_WALLET_ADDRESS
```

It syncs the sidechain in 5-10 minutes, then opens its stratum server on port 3333. `--mini` or
`--nano` join the smaller sidechains, where shares are easier to find with a low hashrate.
Optionally open the P2Pool P2P port (37889; 37888 for mini, 37890 for nano) for better
connectivity.

### 3. Quarry

```bash
zig build --release=fast
./zig-out/bin/quarry --pool 127.0.0.1:3333 --user my-worker
```

The wallet comes from P2Pool, so Quarry needs none. To mine from another machine, point
`--pool` at the P2Pool node's IP.

## Documentation

See the `docs` folder.

Build instructions are available [here](docs/BUILD.md).

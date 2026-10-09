//! RandomX mining threads working on the current stratum job.
//!
//! Each worker hashes the job's blob with its own nonces (worker `i` of `n` tries `i`, `i + n`,
//! ...) and reports hashes that meet the job's target through `on_share`. The RandomX cache, and
//! the dataset in fast mode, are shared by all workers and rebuilt when the job's seed hash
//! changes; workers are held off while that happens.

const std = @import("std");
const randomx = @import("randomx");
const common = @import("common.zig");
const protocol = @import("stratum/protocol.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Job = protocol.Job;

const log = std.log.scoped(.miner);

const Miner = @This();

pub const Mode = enum {
    /// Precompute the ~2 GiB dataset: fastest, needs ~2.3 GiB of memory.
    fast,
    /// Compute dataset items from the 256 MiB cache on the fly: much slower.
    light,
};

pub const Options = struct {
    threads: usize,
    mode: Mode = .fast,
    /// Passed to zig-randomx: huge pages and JIT.
    randomx: randomx.Options = .{},
};

/// Called from worker threads for each hash that meets the job's target.
pub const ShareFn = *const fn (ctx: ?*anyopaque, job: *const Job, nonce: u32, hash: *const common.Hash) void;

gpa: Allocator,
io: Io,
options: Options,
on_share: ShareFn,
share_ctx: ?*anyopaque,

cache: *randomx.Cache,
dataset: ?*randomx.Dataset,
/// Seed hash the cache (and dataset) were built from.
seed: ?common.Hash,

/// Held shared by workers while hashing, exclusively while the job or dataset changes.
lock: Io.RwLock,
job: Job,
/// Incremented on every new job; 0 means no job yet.
job_generation: std.atomic.Value(u64),
/// False while there is no job to mine (before the first job, or after `pause`).
active: std.atomic.Value(bool),
stopping: std.atomic.Value(bool),
hashes: std.atomic.Value(u64),

workers: []std.Thread,

pub fn create(gpa: Allocator, io: Io, options: Options, on_share: ShareFn, share_ctx: ?*anyopaque) !*Miner {
    std.debug.assert(options.threads > 0);
    if (!randomx.hasHardwareAes()) return error.AesNotSupported;

    const self = try gpa.create(Miner);
    errdefer gpa.destroy(self);

    // Allocate the dataset first: it gains the most from huge pages.
    const dataset = if (options.mode == .fast) try randomx.Dataset.create(gpa, options.randomx) else null;
    errdefer if (dataset) |ds| ds.destroy(gpa);
    const cache = try randomx.Cache.create(gpa, options.randomx);
    errdefer cache.destroy(gpa);

    self.* = .{
        .gpa = gpa,
        .io = io,
        .options = options,
        .on_share = on_share,
        .share_ctx = share_ctx,
        .cache = cache,
        .dataset = dataset,
        .seed = null,
        .lock = .init,
        .job = undefined,
        .job_generation = .init(0),
        .active = .init(false),
        .stopping = .init(false),
        .hashes = .init(0),
        .workers = &.{},
    };

    const workers = try gpa.alloc(std.Thread, options.threads);
    errdefer gpa.free(workers);
    var spawned: usize = 0;
    errdefer {
        self.stopping.store(true, .release);
        for (workers[0..spawned]) |t| t.join();
    }
    for (workers, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, workerMain, .{ self, @as(u32, @intCast(i)), @as(u32, @intCast(options.threads)) });
        spawned += 1;
    }
    self.workers = workers;
    return self;
}

pub fn destroy(self: *Miner) void {
    self.stopping.store(true, .release);
    for (self.workers) |t| t.join();
    self.gpa.free(self.workers);
    if (self.dataset) |ds| ds.destroy(self.gpa);
    self.cache.destroy(self.gpa);
    self.gpa.destroy(self);
}

/// Switches all workers to `job`. Rebuilds the RandomX dataset first if the seed hash changed,
/// which blocks for several seconds in fast mode.
pub fn setJob(self: *Miner, job: *const Job) !void {
    self.lock.lockUncancelable(self.io);
    defer self.lock.unlock(self.io);

    if (self.seed == null or !std.mem.eql(u8, &self.seed.?, &job.seed_hash)) {
        log.info("Initializing RandomX for seed {x}", .{job.seed_hash});
        const clock: Io.Clock = .awake;
        const start = clock.now(self.io);
        self.cache.init(&job.seed_hash);
        // Use every CPU: dataset initialization isn't limited by L3 the way hashing is.
        if (self.dataset) |ds| try ds.init(self.cache, std.Thread.getCpuCount() catch self.options.threads);
        self.seed = job.seed_hash;
        log.info("RandomX ready in {d} ms", .{start.durationTo(clock.now(self.io)).toMilliseconds()});
    }

    self.job = job.*;
    _ = self.job_generation.fetchAdd(1, .release);
    self.active.store(true, .release);
}

/// Stops hashing until the next `setJob`, e.g. while disconnected from the pool. When this
/// returns, no worker is still hashing (or reporting shares for) the previous job.
pub fn pause(self: *Miner) void {
    self.lock.lockUncancelable(self.io);
    defer self.lock.unlock(self.io);
    self.active.store(false, .release);
}

/// Bytes of L3 cache each mining thread needs for its RandomX scratchpad.
const l3_per_thread = 2 * 1024 * 1024;

/// Default number of mining threads: as many as the L3 cache holds scratchpads for (like XMRig),
/// at most one per CPU. Threads beyond that evict each other's scratchpads and add little.
pub fn defaultThreadCount(io: Io) usize {
    const cpus = std.Thread.getCpuCount() catch 1;
    const l3 = totalL3Size(io, cpus) catch return cpus;
    return std.math.clamp(l3 / l3_per_thread, 1, cpus);
}

/// Sums the sizes of the distinct L3 caches on Linux, from sysfs.
fn totalL3Size(io: Io, cpus: usize) !usize {
    var seen_ids: [64]u32 = undefined;
    var seen: usize = 0;
    var total: usize = 0;
    for (0..cpus) |cpu| {
        var path_buf: [96]u8 = undefined;
        var buf: [32]u8 = undefined;

        const id_path = try std.fmt.bufPrint(&path_buf, "/sys/devices/system/cpu/cpu{d}/cache/index3/id", .{cpu});
        const id_text = try Io.Dir.cwd().readFile(io, id_path, &buf);
        const id = try std.fmt.parseInt(u32, std.mem.trim(u8, id_text, " \n"), 10);
        if (std.mem.indexOfScalar(u32, seen_ids[0..seen], id) != null) continue;
        if (seen == seen_ids.len) break;
        seen_ids[seen] = id;
        seen += 1;

        const size_path = try std.fmt.bufPrint(&path_buf, "/sys/devices/system/cpu/cpu{d}/cache/index3/size", .{cpu});
        total += try parseCacheSize(try Io.Dir.cwd().readFile(io, size_path, &buf));
    }
    if (total == 0) return error.NoL3Cache;
    return total;
}

/// Parses a sysfs cache size such as "3072K" or "32M".
fn parseCacheSize(text: []const u8) !usize {
    const t = std.mem.trim(u8, text, " \n");
    if (t.len == 0) return error.InvalidCacheSize;
    const unit: usize = switch (t[t.len - 1]) {
        'K' => 1024,
        'M' => 1024 * 1024,
        else => 1,
    };
    const digits = if (unit == 1) t else t[0 .. t.len - 1];
    return try std.fmt.parseInt(usize, digits, 10) * unit;
}

/// Total hashes computed since the miner started.
pub fn hashCount(self: *const Miner) u64 {
    return self.hashes.load(.monotonic);
}

fn workerMain(self: *Miner, index: u32, stride: u32) void {
    var vm: ?*randomx.Vm = null;
    var vm_algo: protocol.Algo = undefined;
    defer if (vm) |v| v.destroy(self.gpa);

    var job: Job = undefined;
    var generation: u64 = 0;
    var nonce: u32 = 0;

    while (!self.stopping.load(.acquire)) {
        if (!self.active.load(.acquire)) {
            Io.sleep(self.io, .fromMilliseconds(50), .awake) catch {};
            continue;
        }

        self.lock.lockSharedUncancelable(self.io);
        defer self.lock.unlockShared(self.io);
        // Paused between the check above and taking the lock.
        if (!self.active.load(.acquire)) continue;

        const current = self.job_generation.load(.acquire);
        if (current != generation) {
            generation = current;
            job = self.job;
            nonce = index;
            if (vm == null or vm_algo != job.algo) {
                if (vm) |v| v.destroy(self.gpa);
                vm = null;
                vm = self.createVm(job.algo) catch |err| {
                    log.err("Worker {d} failed to create a RandomX VM: {t}", .{ index, err });
                    return;
                };
                vm_algo = job.algo;
            }
        }

        var blob_buf: [protocol.max_blob_size]u8 = undefined;
        const blob = blob_buf[0..job.blob_len];
        @memcpy(blob, job.blob());
        std.mem.writeInt(u32, blob[protocol.nonce_offset..][0..4], nonce, .little);

        var hash: common.Hash = undefined;
        vm.?.hash(blob, &hash);
        _ = self.hashes.fetchAdd(1, .monotonic);

        if (protocol.meetsTarget(&hash, job.target)) self.on_share(self.share_ctx, &job, nonce, &hash);
        nonce +%= stride;
    }
}

fn createVm(self: *Miner, algo: protocol.Algo) !*randomx.Vm {
    var options = self.options.randomx;
    options.version = switch (algo) {
        .rx0 => .v1,
        .rx2 => .v2,
    };
    const source: randomx.Source = if (self.dataset) |ds| .{ .fast = ds } else .{ .light = self.cache };
    return randomx.Vm.create(self.gpa, source, options);
}

const testing = std.testing;

test "parse cache size" {
    try testing.expectEqual(3 * 1024 * 1024, try parseCacheSize("3072K\n"));
    try testing.expectEqual(32 * 1024 * 1024, try parseCacheSize("32M"));
    try testing.expectEqual(512, try parseCacheSize("512"));
    try testing.expectError(error.InvalidCacheSize, parseCacheSize("\n"));
}

/// Records the first share reported by a miner.
const TestShares = struct {
    claimed: std.atomic.Value(bool) = .init(false),
    ready: std.atomic.Value(bool) = .init(false),
    nonce: u32 = 0,
    hash: common.Hash = undefined,

    fn onShare(ctx: ?*anyopaque, job: *const Job, nonce: u32, hash: *const common.Hash) void {
        _ = job;
        const self: *TestShares = @ptrCast(@alignCast(ctx.?));
        if (self.claimed.swap(true, .acq_rel)) return;
        self.nonce = nonce;
        self.hash = hash.*;
        self.ready.store(true, .release);
    }
};

test "light-mode miner finds a valid share" {
    const io = testing.io;
    var shares: TestShares = .{};
    const miner = try create(testing.allocator, io, .{ .threads = 2, .mode = .light }, TestShares.onShare, &shares);
    defer miner.destroy();

    // Target of difficulty 2: about every other hash is a share.
    var job: Job = .{
        .id = try .init("1"),
        .blob_buf = @splat(0x5a),
        .blob_len = 76,
        .target = std.math.maxInt(u64) / 2,
        .height = 1,
        .seed_hash = @splat(0x11),
        .algo = .rx0,
    };
    try miner.setJob(&job);

    while (!shares.ready.load(.acquire)) Io.sleep(io, .fromMilliseconds(50), .awake) catch {};

    // Recompute the share's hash independently with RandomX v1.
    const cache = try randomx.Cache.create(testing.allocator, .{});
    defer cache.destroy(testing.allocator);
    cache.init(&job.seed_hash);
    const vm = try randomx.Vm.create(testing.allocator, .{ .light = cache }, .{ .version = .v1 });
    defer vm.destroy(testing.allocator);

    std.mem.writeInt(u32, job.blob_buf[protocol.nonce_offset..][0..4], shares.nonce, .little);
    var want: common.Hash = undefined;
    vm.hash(job.blob(), &want);
    try testing.expectEqualSlices(u8, &want, &shares.hash);
    try testing.expect(protocol.meetsTarget(&want, job.target));
}

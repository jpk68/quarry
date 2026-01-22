const std = @import("std");
const common = @import("common.zig");

// Base block reward is constant after reaching tail emission.
const base_reward: u64 = 600000000000;

entries: std.ArrayList(Entry) = .empty,

pub const Entry = struct {
    id: common.Hash,
    blob_size: usize,
    weight: u64,
    fee: u64,
    received_timestamp: u64,
};

pub fn getBlockReward(weight: u64, median_weight: u64, fees: u64) u64 {
    // No penalty incurred if block weight is smaller than the median weight.
    if (weight <= median_weight) return base_reward + fees;
    // Block reward is reduced to zero if its weight is more than double the median weight.
    if (weight > median_weight * 2) return 0;

    const numerator: u128 =
        @as(u128, base_reward) *
        @as(u128, (2 * median_weight - weight)) *
        @as(u128, weight);

    const denominator: u128 =
        @as(u128, median_weight) *
        @as(u128, median_weight);

    const reward: u64 = @intCast(numerator / denominator);
    return reward + fees;
}

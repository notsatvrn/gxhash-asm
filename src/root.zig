const std = @import("std");
pub const core = @import("core.zig");
const options = @import("options");

pub const fallback = core.software_aes and options.fallback;

pub inline fn hash(input: []const u8, seed: u64) u64 {
    return @truncate(hash128(input, seed));
}

pub fn hash128(input: []const u8, seed: u64) u128 {
    return if (fallback) std.hash.RapidHash.hash(seed, input) else core.hash(input, seed);
}

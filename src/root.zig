const std = @import("std");
pub const core = @import("core.zig");
const options = @import("options");

pub const fallback = core.software_aes and options.fallback;

pub inline fn hash(seed: u64, input: []const u8) u64 {
    return @truncate(hash128(seed, input));
}

pub fn hash128(seed: u64, input: []const u8) u128 {
    return if (fallback) std.hash.RapidHash.hash(seed, input) else core.hash(seed, input);
}

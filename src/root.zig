const std = @import("std");
pub const core = @import("core.zig");
const options = @import("options");

pub const use_wyhash = core.software_aes and options.fast_fallback;
pub const State = core.State;

// quick hashing functions

pub inline fn hash32(input: []const u8, seed: u64) u32 {
    return hash(input, seed).u32x4[0];
}

pub inline fn hash64(input: []const u8, seed: u64) u64 {
    return hash(input, seed).u64x2[0];
}

pub inline fn hash128(input: []const u8, seed: u64) u128 {
    return hash(input, seed).u128;
}

fn hash(input: []const u8, seed: u64) core.State {
    return if (use_wyhash) std.hash.Wyhash.hash(seed, input) else core.hash(input, seed);
}

// seeded hasher struct
// if fast fallback is used it will just be a wrapper around Wyhash

pub const Hasher = if (use_wyhash) struct {
    const Self = @This();

    state: std.hash.Wyhash,

    pub inline fn init(seed: u64) Self {
        return .{ .state = std.hash.Wyhash.init(seed) };
    }

    pub inline fn update(self: *Self, input: []const u8) void {
        self.state.update(input);
    }

    pub inline fn final32(self: *Self) u32 {
        return @truncate(self.state.final());
    }

    pub inline fn final(self: *Self) u64 {
        return self.state.final();
    }

    pub inline fn final128(self: *Self) u128 {
        const tmp: u128 = @intCast(self.state.final());
        return (tmp | (tmp << 64)) *% tmp;
    }
} else struct {
    const Self = @This();

    state: State,

    pub inline fn init(seed: u64) Self {
        return .{ .state = State.init(seed) };
    }

    pub fn update(self: *Self, input: []const u8) void {
        self.state = core.aesEncryptLast(core.compressAll(input), core.aesEncrypt(self.state, core.keys[0]));
    }

    pub fn final32(self: *Self) u32 {
        return core.finalize(self.state).u32x4[0];
    }

    pub fn final(self: *Self) u64 {
        return core.finalize(self.state).u64x2[0];
    }

    pub fn final128(self: *Self) u128 {
        return core.finalize(self.state).u128;
    }
};

// HashMap context and types

// TODO: require seed or use internal state somehow?
// would require providing a HashMap with a context though, kinda messy
pub const StringHashMapContext = struct {
    pub inline fn hash(_: @This(), s: []const u8) u64 {
        return hash64(s, 0);
    }
    pub inline fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

pub inline fn StringHashMap(comptime V: type) type {
    return std.HashMap([]const u8, V, StringHashMapContext, std.hash_map.default_max_load_percentage);
}
pub inline fn StringArrayHashMap(comptime V: type) type {
    return std.ArrayHashMap([]const u8, V, StringHashMapContext, true);
}

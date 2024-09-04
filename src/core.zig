const builtin = @import("builtin");
const std = @import("std");

// AES implementation
// TODO: look into using CPUID to pick implementation at runtime

const aes = plat: {
    if (builtin.cpu.arch.isX86()) {
        const has_aes = std.Target.x86.featureSetHas(builtin.cpu.features, .aes);
        const has_avx = has_aes and std.Target.x86.featureSetHas(builtin.cpu.features, .avx);
        const has_vaes = has_avx and std.Target.x86.featureSetHasAll(builtin.cpu.features, .{ .avx2, .vaes });

        if (has_vaes and @import("options").hybrid) break :plat @import("aes/x86_vaes.zig");
        if (has_aes) break :plat @import("aes/x86.zig");
    } else if (builtin.cpu.arch.isARM()) {
        const target = switch (builtin.cpu.arch) {
            .arm, .armeb => std.Target.arm,
            _ => std.Target.aarch64,
        };

        const has_aes = target.featureSetHas(builtin.cpu.features, .aes);
        const has_neon = target.featureSetHas(builtin.cpu.features, .neon);

        if (has_aes and has_neon) break :plat @import("aes/arm.zig");
    }

    break :plat @import("aes/soft.zig");
};

pub const software_aes = @hasDecl(aes, "software");
pub const aesEncrypt = aes.encrypt;
pub const aesEncryptLast = aes.encryptLast;

// state (represented as a packed union for easy type conversion)

const i8x16 = @Vector(16, i8);
const i32x4 = @Vector(4, i32);
const u32x4 = @Vector(4, u32);
const u64x2 = @Vector(2, u64);

pub const State = packed union {
    const Self = @This();

    i8x16: i8x16,
    i32x4: i32x4,
    u32x4: u32x4,
    u64x2: u64x2,

    u128: u128,

    pub const empty = Self{ .u128 = 0 };

    pub inline fn init(seed: u64) Self {
        return .{ .u64x2 = @splat(seed) };
    }
};

comptime {
    std.debug.assert(@sizeOf(State) == 16);
    std.debug.assert(@alignOf(State) == 16);
}

// get partial

inline fn getPartialSafe(data: [*]const i8, len: usize) i8x16 {
    var buf: [16]i8 = .{0} ** 16;
    @memcpy(buf[0..16].ptr, data[0..len]);
    return buf +% @as(i8x16, @splat(@intCast(len)));
}

inline fn getPartialUnsafe(data: [*]const i8, len: usize) i8x16 {
    const indices: i8x16 = std.simd.iota(i8, 16);
    const len_vec: i8x16 = @splat(@intCast(len));
    return @select(i8, len_vec > indices, data[0..16].*, State.empty.i8x16) +% len_vec;
}

inline fn getPartial(data: [*]const i8, len: usize) i8x16 {
    return if (check_same_page(data)) getPartialUnsafe(data, len) else getPartialSafe(data, len);
}

inline fn check_same_page(ptr: [*]const i8) bool {
    const address = @intFromPtr(ptr);
    // Mask to keep only the last 12 bits
    const offset_within_page = address & (std.mem.page_size - 1);
    // Check if the 16nd byte from the current offset exceeds the page boundary
    return offset_within_page < std.mem.page_size - 16;
}

// compression

pub const keys: [3]State = .{
    .{ .u32x4 = .{ 0xF2784542, 0xB09D3E21, 0x89C222E5, 0xFC3BC28E } },
    .{ .u32x4 = .{ 0x03FCE279, 0xCB6B2E9B, 0xB361DC58, 0x39132BD9 } },
    .{ .u32x4 = .{ 0xD0012E32, 0x689D2B7D, 0x5544B1B7, 0xC78B122B } },
};

export fn compressAllExtern(pointer: u64, len: u64) State {
    return compressAll(@as([*]const u8, @ptrFromInt(pointer))[0..len]);
}

pub fn compressAll(input: []const u8) State {
    if (input.len == 0) return State.empty;

    var ptr: [*]const i8 = @ptrCast(input.ptr);

    // Input fits on a single SIMD vector, however we might read beyond the input message
    // Thus we need this safe method that checks if it can safely read beyond or must copy
    if (input.len <= 16) return .{ .i8x16 = getPartial(ptr, input.len) };

    const end = @intFromPtr(ptr) + input.len;

    const extra_bytes_count = input.len % 16;
    var hash_vector: State = undefined;
    if (extra_bytes_count == 0) {
        hash_vector = .{ .i8x16 = ptr[0..16].* };
        ptr += 16;
    } else {
        // If the input length does not match the length of a whole number of SIMD vectors,
        // it means we'll need to read a partial vector. We can start with the partial vector first,
        // so that we can safely read beyond since we expect the following bytes to still be part of
        // the input
        hash_vector = .{ .i8x16 = getPartialUnsafe(ptr, extra_bytes_count) };
        ptr += extra_bytes_count;
    }

    @prefetch(&keys, .{});

    var v0 = State{ .i8x16 = ptr[0..16].* };

    if (input.len > 16 * 2) {
        // Fast path when input length > 32 and <= 48
        v0 = aesEncrypt(v0, .{ .i8x16 = ptr[16..32].* });

        if (input.len > 16 * 3) {
            // Fast path when input length > 48 and <= 64
            v0 = aesEncrypt(v0, .{ .i8x16 = ptr[32..48].* });

            if (input.len > 16 * 4) {
                // Input message is large and we can use the high ILP loop
                hash_vector = compressMany(ptr + 48, end, hash_vector, input.len);
            }
        }
    }

    return aesEncryptLast(hash_vector, aesEncrypt(aesEncrypt(v0, keys[0]), keys[1]));
}

const unroll_factor = 8;

inline fn compressMany(pointer: [*]const i8, end: usize, hash_vec: State, len: usize) State {
    var ptr = pointer;

    var remaining_bytes = end - @intFromPtr(ptr);
    const unrollable_blocks_count = remaining_bytes / (16 * unroll_factor) * unroll_factor;
    remaining_bytes -= unrollable_blocks_count * 16;

    const end_address = @intFromPtr(ptr) + remaining_bytes;
    var hash_vector = hash_vec;
    while (@intFromPtr(ptr) < end_address) : (ptr += 16) {
        hash_vector = aesEncrypt(hash_vector, .{ .i8x16 = ptr[0..16].* });
    }

    // Process the remaining n * 8 blocks
    // This part may use 128-bit or 256-bit
    return compress8(ptr, end, hash_vector, len);
}

const compress8 = if (@hasDecl(aes, "compress8")) aes.compress8 else compress8Standard;

inline fn compress8Standard(pointer: [*]const i8, end: usize, hash_vector: State, len: usize) State {
    var ptr = pointer;

    // Disambiguation vectors
    var t1 = State.empty;
    var t2 = State.empty;

    // Hash is processed in two separate 128-bit parallel lanes
    // This allows the same processing to be applied using 256-bit V-AES instrinsics
    // so that hashes are stable in both cases.
    var lane1 = hash_vector;
    var lane2 = hash_vector;

    while (@intFromPtr(ptr) < end) : (ptr += 128) {
        var tmp1 = aesEncrypt(.{ .i8x16 = ptr[0..16].* }, .{ .i8x16 = ptr[32..48].* });
        var tmp2 = aesEncrypt(.{ .i8x16 = ptr[16..32].* }, .{ .i8x16 = ptr[48..64].* });

        tmp1 = aesEncrypt(tmp1, .{ .i8x16 = ptr[64..80].* });
        tmp2 = aesEncrypt(tmp2, .{ .i8x16 = ptr[80..96].* });

        tmp1 = aesEncrypt(tmp1, .{ .i8x16 = ptr[96..112].* });
        tmp2 = aesEncrypt(tmp2, .{ .i8x16 = ptr[112..128].* });

        //@prefetch(ptr + 128, .{});

        t1.i8x16 +%= keys[0].i8x16;
        t2.i8x16 +%= keys[1].i8x16;

        lane1 = aesEncryptLast(aesEncrypt(tmp1, t1), lane1);
        lane2 = aesEncryptLast(aesEncrypt(tmp2, t2), lane2);
    }

    // For 'Zeroes' test
    const len_vec = (State{ .i32x4 = @splat(@intCast(len)) }).i8x16;
    lane1.i8x16 +%= len_vec;
    lane2.i8x16 +%= len_vec;
    // Merge lanes
    return aesEncrypt(lane1, lane2);
}

// finalize

pub inline fn finalize(data: State) State {
    var hash = aesEncrypt(data, keys[0]);
    hash = aesEncrypt(hash, keys[1]);
    hash = aesEncryptLast(hash, keys[2]);
    return hash;
}

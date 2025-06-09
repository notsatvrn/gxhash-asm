const std = @import("std");
const gxhash = @import("gxhash");

inline fn hash32(input: []const u8, seed: u64) u32 {
    return @truncate(gxhash.hash(input, seed));
}

test "all blocks are consumed" {
    for (1..1200) |size| {
        var bytes = try std.testing.allocator.alloc(u8, size);
        @memset(bytes, 42);
        const ref_hash = hash32(bytes, 0);

        for (0..size) |i| {
            const swap = bytes[i];
            bytes[i] = 82;
            const new_hash = hash32(bytes, 0);
            bytes[i] = swap;

            try std.testing.expect(ref_hash != new_hash);
        }

        std.testing.allocator.free(bytes);
    }
}

test "add zeroes mutates hash" {
    var bytes: [1200]u8 = [_]u8{0} ** 1200;
    try std.posix.getrandom(bytes[0..32]);

    var ref_hash: u32 = 0;

    for (32..100) |i| {
        const new_hash = hash32(bytes[0..i], 0);
        try std.testing.expect(ref_hash != new_hash);
        ref_hash = new_hash;
    }
}

test "does not hash out of bounds" {
    var bytes: [1200]u8 = [_]u8{0} ** 1200;
    try std.posix.getrandom(&bytes);

    const offset = 100;

    for (1..100) |i| {
        const ref_hash = hash32(bytes[offset .. i + offset], 42);
        // We change the bytes right before and after the input slice. It shouldn't alter the hash.
        try std.posix.getrandom(bytes[0..offset]);
        try std.posix.getrandom(bytes[i + offset ..]);
        const new_hash = hash32(bytes[offset .. i + offset], 42);
        try std.testing.expectEqual(ref_hash, new_hash);
    }
}

test "hash of zero is not zero" {
    try std.testing.expect(hash32(&[_]u8{}, 0) != 0);
    try std.testing.expect(hash32(&[_]u8{0}, 0) != 0);
    try std.testing.expect(hash32(&[_]u8{0} ** 1200, 0) != 0);
}

test "stability" {
    if (gxhash.fallback) return error.SkipZigTest;

    try std.testing.expectEqual(2533353535, hash32(&[_]u8{}, 0));
    try std.testing.expectEqual(4243413987, hash32(&[_]u8{0}, 0));
    try std.testing.expectEqual(2401749549, hash32(&[_]u8{0} ** 1000, 0));
    try std.testing.expectEqual(4156851105, hash32(&[_]u8{42} ** 4242, 42));
    try std.testing.expectEqual(1981427771, hash32(&[_]u8{42} ** 4242, @bitCast(@as(i64, -42))));
    try std.testing.expectEqual(1156095992, hash32("Hello World", @bitCast(@as(i64, std.math.maxInt(i64)))));
    try std.testing.expectEqual(540827083, hash32("Hello World", @bitCast(@as(i64, std.math.minInt(i64)))));
}

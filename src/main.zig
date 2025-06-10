const std = @import("std");

pub fn main() !void {
    const gxhash = @import("gxhash").hash128;
    const rapidhash = @import("std").hash.RapidHash.hash;
    const wyhash = @import("std").hash.Wyhash.hash;

    const factor2 = 1;
    const iterations = (1_000_000_000 / factor2 / 2);
    const hash_str = "test" ** factor2;
    const size: f64 = @floatFromInt(hash_str.len * iterations);

    std.debug.print("warmup\n", .{});
    for (0..iterations / 50) |i| {
        std.mem.doNotOptimizeAway(gxhash(i, hash_str));
        std.mem.doNotOptimizeAway(@call(.never_inline, rapidhash, .{ i, hash_str }));
        std.mem.doNotOptimizeAway(@call(.never_inline, wyhash, .{ i, hash_str }));
    }

    std.debug.print("data size: {d:.0} bytes\n", .{hash_str.len});

    const gxhash_start = try std.time.Instant.now();
    for (0..iterations) |i| std.mem.doNotOptimizeAway(gxhash(i, hash_str));
    const gxhash_end = try std.time.Instant.now();
    const gxhash_sec = @as(f64, @floatFromInt(gxhash_end.since(gxhash_start))) / std.time.ns_per_s;
    std.debug.print("gxhash: {d:.2}MB/s\n", .{size / gxhash_sec / (1024 * 1024)});

    const rapidhash_start = try std.time.Instant.now();
    for (0..iterations) |i| std.mem.doNotOptimizeAway(@call(.never_inline, rapidhash, .{ i, hash_str }));
    const rapidhash_end = try std.time.Instant.now();
    const rapidhash_sec = @as(f64, @floatFromInt(rapidhash_end.since(rapidhash_start))) / std.time.ns_per_s;
    std.debug.print("rapidhash: {d:.2}MB/s\n", .{size / rapidhash_sec / (1024 * 1024)});

    const wyhash_start = try std.time.Instant.now();
    for (0..iterations) |i| std.mem.doNotOptimizeAway(@call(.never_inline, wyhash, .{ i, hash_str }));
    const wyhash_end = try std.time.Instant.now();
    const wyhash_sec = @as(f64, @floatFromInt(wyhash_end.since(wyhash_start))) / std.time.ns_per_s;
    std.debug.print("wyhash: {d:.2}MB/s\n", .{size / wyhash_sec / (1024 * 1024)});
}

const std = @import("std");
const gxhash = @import("src/core.zig");

comptime {
    asm (@embedFile("src/x86_64/avx.s"));
}

const State = @Vector(16, i8);

extern fn compress_all(ptr: u64, len: u64) State;

const iterations = 10000000 / 2;
const size = 32768;
const rust_thruput: f64 = 34000.0;

pub fn main() !void {
    var data: [size]u8 = undefined;
    try std.posix.getrandom(&data);

    std.debug.print("\n{any}\n{any}\n", .{
        @as([16]u8, @bitCast(compressAll(&data))),
        @as([16]u8, @bitCast(gxhash.compressAll(&data))),
    });

    try benchmark(&data);
}

inline fn benchmark(data: []const u8) !void {
    std.debug.print("warmup\n", .{});

    for (0..iterations) |_| {
        std.mem.doNotOptimizeAway(compressAll(data));
    }

    std.debug.print("assembly version\n", .{});

    const start = try std.time.Instant.now();

    for (0..iterations) |_| {
        std.mem.doNotOptimizeAway(compressAll(data));
    }

    const ns = (try std.time.Instant.now()).since(start);
    const thruput: f64 = @floatFromInt((iterations * size) / (ns / 1000));
    std.debug.print("took {d}ms | {d}MB/s\n", .{ ns / std.time.ns_per_ms, thruput });

    std.time.sleep(std.time.ns_per_s);

    std.debug.print("zig version\n", .{});

    const zstart = try std.time.Instant.now();

    for (0..iterations) |_| {
        std.mem.doNotOptimizeAway(@call(.never_inline, gxhash.compressAll, .{data}));
    }

    const zns = (try std.time.Instant.now()).since(zstart);
    const zig_thruput: f64 = @floatFromInt((iterations * size) / (zns / 1000));
    std.debug.print("took {d}ms | {d}MB/s\n", .{ zns / std.time.ns_per_ms, zig_thruput });

    std.debug.print("{d}% improvement over zig port\n", .{((thruput - zig_thruput) / zig_thruput) * 100});
    std.debug.print("{d}% improvement over original project\n", .{((thruput - rust_thruput) / rust_thruput) * 100});
}

pub fn compressAll(input: []const u8) State {
    return compress_all(@intCast(@intFromPtr(input.ptr)), @intCast(input.len));
}

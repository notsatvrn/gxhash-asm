const std = @import("std");

pub fn build(b: *std.Build) void {
    // OPTIONS

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fallback = b.option(bool, "gxhash_fallback", "Use RapidHash for better performance when hardware AES is not available") orelse false;
    const hybrid = b.option(bool, "gxhash_hybrid", "Use V-AES to compress large inputs on x86 when available") orelse true;

    // MODULE

    const options = b.addOptions();
    options.addOption(bool, "fallback", fallback);
    options.addOption(bool, "hybrid", hybrid);
    const options_module = options.createModule();
    const gxhash = b.addModule("gxhash", .{
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{.{ .name = "options", .module = options_module }},
    });

    // TESTS

    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("gxhash", gxhash);

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}

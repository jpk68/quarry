const std = @import("std");

// TODO add release targets

pub fn build(b: *std.Build) void {
    // Use default per-platform target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define custom build options/directives
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM backend for Zig codegen");
    const fmt_check = b.option(bool, "fmt-check", "Check formatting of source files");
    const test_filters = b.option([]const []const u8, "test-filter", "Only run tests whose names contain this text") orelse &.{};

    // Embed the build.zig.zon file to access version info
    const build_zig_zon = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });

    // RandomX comes from zig-randomx (x86-64 JIT and interpreter, v1 and v2)
    const randomx = b.dependency("randomx", .{
        .target = target,
        .optimize = optimize,
    }).module("randomx");

    const quarry = b.addExecutable(.{
        .name = "quarry",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // Needed for linking libzmq
            .link_libc = true,
            .imports = &.{
                .{ .name = "randomx", .module = randomx },
                .{ .name = "build.zig.zon", .module = build_zig_zon },
            },
        }),
        // Use LLVM for release builds: the self-hosted backend builds faster, but its code hashes
        // RandomX several times slower (AES and BLAKE2b over the scratchpad on every hash).
        .use_llvm = use_llvm orelse (optimize != .Debug),
        .use_lld = use_llvm orelse (optimize != .Debug),
    });
    quarry.root_module.linkSystemLibrary("libzmq", .{ .preferred_link_mode = .static });
    b.installArtifact(quarry);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(quarry);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const quarry_tests = b.addTest(.{ .root_module = quarry.root_module, .filters = test_filters });
    const run_quarry_tests = b.addRunArtifact(quarry_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_quarry_tests.step);

    // Custom directive to check and format source files
    const fmt = b.addFmt(.{
        .check = fmt_check orelse true,
        .paths = &.{
            "src",
            "build.zig",
            "build.zig.zon",
        },
    });
    b.step("fmt", "Check and format source files").dependOn(&fmt.step);
}

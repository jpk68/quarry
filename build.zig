const std = @import("std");

pub fn build(b: *std.Build) void {
    // Use default per-platform target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // RandomX is compiled as a separate unit
    const randomx = b.addModule("randomx", .{
        .root_source_file = b.path("src/randomx/root.zig"),
        .target = target,
    });

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
            },
        }),
        // Zig's self-hosted backend currently has some issues with C interop
        .use_llvm = true,
    });
    quarry.root_module.linkSystemLibrary("libzmq", .{});
    b.installArtifact(quarry);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(quarry);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const randomx_tests = b.addTest(.{ .root_module = randomx });
    const run_randomx_tests = b.addRunArtifact(randomx_tests);

    const quarry_tests = b.addTest(.{ .root_module = quarry.root_module });
    const run_quarry_tests = b.addRunArtifact(quarry_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_randomx_tests.step);
    test_step.dependOn(&run_quarry_tests.step);

    // Custom directive to format and check source files
    const fmt = b.addFmt(.{
        .check = b.option(bool, "fmtcheck", "fmtcheck") orelse false,
        .paths = &.{
            "src",
            "build.zig",
            "build.zig.zon",
        },
    });
    b.step("fmt", "Format source files").dependOn(&fmt.step);
}

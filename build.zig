const std = @import("std");

// TODO add release targets

pub fn build(b: *std.Build) void {
    // Use default per-platform target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define custom build options/directives
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM backend for Zig codegen");
    const fmt_check = b.option(bool, "fmt-check", "Check formatting of source files");

    // Embed the build.zig.zon file to access version info
    const build_zig_zon = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });

    // RandomX is compiled as a separate unit
    const randomx = b.addModule("randomx", .{
        .root_source_file = b.path("src/randomx/root.zig"),
        .target = target,
        .optimize = optimize,
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
                .{ .name = "build.zig.zon", .module = build_zig_zon },
            },
        }),
        // Use LLVM by default. Zig's self-hosted codegen may have some issues
        .use_llvm = use_llvm orelse false,
        .use_lld = use_llvm orelse false,
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

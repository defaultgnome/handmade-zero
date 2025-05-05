const std = @import("std");

// TODO(ariel): create build.zig for stdx and engine and import them here
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose to build command
    const handmade_internal = b.option(
        bool,
        "handmade_internal",
        "Enable developer mode features. Set to true on Debug builds.",
    ) orelse (optimize == .Debug);

    const handmade_slow = b.option(
        bool,
        "handmade_slow",
        "Enable slow debug functionality. Set to true on Debug builds.",
    ) orelse (optimize == .Debug);

    // create options to be passed to modules
    const options = b.addOptions();
    options.addOption(bool, "handmade_internal", handmade_internal);
    options.addOption(bool, "handmade_slow", handmade_slow);

    const stdx_mod = b.createModule(.{
        .root_source_file = b.path("libs/stdx/stdx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const engine_mod = b.createModule(.{
        .root_source_file = b.path("libs/engine/engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_mod.addOptions("options", options);
    engine_mod.addImport("stdx", stdx_mod);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addOptions("options", options);
    exe_mod.addImport("stdx", stdx_mod);
    exe_mod.addImport("engine", engine_mod);

    const exe = b.addExecutable(.{
        .name = "handmade_zero",
        .root_module = exe_mod,
    });
    exe.linkLibC();
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("winmm");
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

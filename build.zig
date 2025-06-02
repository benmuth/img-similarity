const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_step = b.addExecutable(.{
        .name = "main",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib_zig", .{});
    const raylib_artifact = raylib_dep.artifact("raylib");
    main_step.linkLibrary(raylib_artifact);

    main_step.root_module.addImport("raylib", raylib_dep.module("raylib"));

    b.installArtifact(main_step);
    const run_artifact = b.addRunArtifact(main_step);
    run_artifact.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "run the app");
    run_step.dependOn(&run_artifact.step);
}

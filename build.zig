// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const mod = b.addModule("mapdb_collections", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = mod;

    // Validation runner executable
    const validate_exe = b.addExecutable(.{
        .name = "validate",
        .root_source_file = b.path("src/validate.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(validate_exe);

    const run_validate = b.addRunArtifact(validate_exe);
    run_validate.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_validate.addArgs(args);
    }
    const run_step = b.step("validate", "Run the validation runner");
    run_step.dependOn(&run_validate.step);

    // NaN semantics probe executable
    const nanprobe_exe = b.addExecutable(.{
        .name = "nanprobe",
        .root_source_file = b.path("src/nanprobe.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(nanprobe_exe);

    const run_nanprobe = b.addRunArtifact(nanprobe_exe);
    run_nanprobe.step.dependOn(b.getInstallStep());
    const nanprobe_step = b.step("nanprobe", "Run the NaN semantics probe");
    nanprobe_step.dependOn(&run_nanprobe.step);

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

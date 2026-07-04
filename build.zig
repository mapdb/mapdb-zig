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

    // Validation runner executable.
    //
    // Zig 0.15 removed `root_source_file` / `target` / `optimize` from
    // std.Build.ExecutableOptions; those fields are now carried by a
    // std.Build.Module created via b.createModule and passed as
    // .root_module. The 0.14 API had them directly on ExecutableOptions.
    // `addExe` below picks the right shape at comptime.
    const validate_exe = addExe(b, "validate", b.path("src/validate.zig"), target, optimize);
    b.installArtifact(validate_exe);

    const run_validate = b.addRunArtifact(validate_exe);
    run_validate.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_validate.addArgs(args);
    }
    const run_step = b.step("validate", "Run the validation runner");
    run_step.dependOn(&run_validate.step);

    // NaN semantics probe executable
    const nanprobe_exe = addExe(b, "nanprobe", b.path("src/nanprobe.zig"), target, optimize);
    b.installArtifact(nanprobe_exe);

    const run_nanprobe = b.addRunArtifact(nanprobe_exe);
    run_nanprobe.step.dependOn(b.getInstallStep());
    const nanprobe_step = b.step("nanprobe", "Run the NaN semantics probe");
    nanprobe_step.dependOn(&run_nanprobe.step);

    // hash.zig caller-contract trap probe. The in-process unit-test runner
    // cannot catch `@panic`, so the always-on hash guards (positions out.len < k
    // and hllSplit p out of [4,18]) are exercised out-of-process: with no args
    // this exe re-execs itself once per trap case and asserts each child
    // terminated non-cleanly. Wired into `zig build test` so a ReleaseFast run
    // confirms the traps fire in release builds too.
    const hashtrapprobe_exe = addExe(b, "hashtrapprobe", b.path("src/hashtrapprobe.zig"), target, optimize);
    b.installArtifact(hashtrapprobe_exe);

    const run_hashtrapprobe = b.addRunArtifact(hashtrapprobe_exe);
    const hashtrapprobe_step = b.step("hashtrapprobe", "Run the out-of-process hash.zig caller-contract trap probe");
    hashtrapprobe_step.dependOn(&run_hashtrapprobe.step);

    // Required-input panic/trap probe. The in-process unit-test runner cannot
    // catch `@panic`, so the always-on Bloom traps (`withParams` m_bits == 0 and
    // `optimal` n == 0 / p <= 0 / p >= 1 / NaN / Inf) are verified out of
    // process: with no args this exe re-execs itself once per trap case and
    // asserts each child terminates non-cleanly. Made a `test` dependency so
    // `zig build test` (incl. `-Doptimize=ReleaseFast`) exercises it.
    const trapprobe_exe = addExe(b, "trapprobe", b.path("src/trapprobe.zig"), target, optimize);
    b.installArtifact(trapprobe_exe);

    const run_trapprobe = b.addRunArtifact(trapprobe_exe);
    const trapprobe_step = b.step("trapprobe", "Run the out-of-process required-input trap probe");
    trapprobe_step.dependOn(&run_trapprobe.step);
    // Unit tests
    const test_filters = b.option([]const []const u8, "test-filter", "Only run tests whose name contains the given substring (repeatable)") orelse &.{};
    const tsan = b.option(bool, "tsan", "Build the unit tests with ThreadSanitizer (for the concurrent collections)") orelse false;
    const lib_unit_tests = b.addTest(.{
        .filters = test_filters,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .sanitize_thread = tsan,
        }),
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_hashtrapprobe.step);
    test_step.dependOn(&run_trapprobe.step);

    // Autodoc: `zig build docs` emits HTML docs from the library's doc-comments
    // (the //! module docs + /// method docs) into zig-out/docs. This is a
    // primary way Zig users evaluate a library and the doc-comment investment
    // otherwise never renders.
    const docs_obj = b.addObject(.{
        .name = "mapdb_collections",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Emit library autodoc into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    // `zig build bench` — throughput/latency microbenchmarks. Forced to
    // ReleaseFast (a Debug bench measures safety checks, not the algorithm) and
    // given its own library module at the same optimize level so the import is
    // compiled release too. `bench_zig.zig` is the core-collections sweep; it is
    // the measurement gate for the deferred hot-internal rewrites (D3 table
    // metadata layout, D9 TreeSet pooling, D13 RangeSet splice).
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench_zig.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "mapdb_collections", .module = bench_mod }},
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run collection microbenchmarks (ReleaseFast)");
    bench_step.dependOn(&run_bench.step);
}

/// Add an executable (Zig 0.15+ module shape; build.zig.zon pins
/// minimum_zig_version = 0.15.0).
fn addExe(
    b: *std.Build,
    name: []const u8,
    src: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = src,
            .target = target,
            .optimize = optimize,
        }),
    });
}

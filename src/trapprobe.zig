// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Out-of-process trap probe for required-input `@panic` preconditions that the
// in-process `zig build test` runner cannot intercept (a `@panic` aborts the
// process). These traps are ALWAYS-ON (`if (cond) @panic(...)`, never
// `std.debug.assert`), so they must fire in every optimize mode including
// ReleaseFast/ReleaseSmall — which is exactly what this probe verifies.
//
// With no args this executable is the HARNESS: it re-execs itself once per trap
// case (via `std.fs.selfExePathAlloc`) and asserts each child terminated
// NON-cleanly (not `.Exited == 0`). With one arg it FIRES the named trap, which
// must `@panic` (so the harness child never returns 0). Wired into
// `zig build test`, so `zig build test -Doptimize=ReleaseFast` exercises it.

const std = @import("std");

const CountMin = @import("count_min.zig").CountMin;
const SpaceSaving = @import("space_saving.zig").SpaceSaving;

const cases = [_][]const u8{
    "cms_w0", // CountMin.withParams(_, 0): width w must be non-zero
    "cms_eps", // CountMin.optimal(epsilon = 1.0, _): 0 < epsilon < 1
    "cms_delta", // CountMin.optimal(_, delta = 1.0): 0 < delta < 1
    "ss_m0", // SpaceSaving.withCapacity(0): capacity m must be non-zero
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        try runHarness(allocator);
        return;
    }

    if (args.len == 2) {
        try fireTrap(args[1], allocator);
        // Reaching here means the required-input trap did NOT fire — fail loudly
        // (non-zero child status) so a regressed guard is caught.
        std.debug.print("trap case {s} returned normally\n", .{args[1]});
        return error.ExpectedTrapDidNotFire;
    }

    std.debug.print("usage: trapprobe [case]\n", .{});
    return error.InvalidArgs;
}

fn runHarness(allocator: std.mem.Allocator) !void {
    const self_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(self_path);

    for (cases) |case_name| {
        const argv = [_][]const u8{ self_path, case_name };
        var child = std.process.Child.init(&argv, allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        const term = try child.spawnAndWait();
        if (isCleanExitZero(term)) {
            std.debug.print(
                "trap case {s} exited cleanly; expected panic / non-zero termination\n",
                .{case_name},
            );
            return error.ExpectedTrapDidNotFire;
        }
    }
}

// A panic aborts (POSIX: `.Signal == SIGABRT`); some targets may surface a
// non-zero `.Exited`. Either is success here — only a clean zero exit fails.
fn isCleanExitZero(term: std.process.Child.Term) bool {
    return switch (term) {
        .Exited => |code| code == 0,
        .Signal, .Stopped, .Unknown => false,
    };
}

fn fireTrap(name: []const u8, allocator: std.mem.Allocator) !void {
    if (std.mem.eql(u8, name, "cms_w0")) {
        var cms = try CountMin.withParams(allocator, 1, 0);
        defer cms.deinit();
        std.mem.doNotOptimizeAway(cms);
        return;
    }

    if (std.mem.eql(u8, name, "cms_eps")) {
        // epsilon == 1.0 violates 0 < epsilon < 1.
        var cms = try CountMin.optimal(allocator, 1.0, 0.5);
        defer cms.deinit();
        std.mem.doNotOptimizeAway(cms);
        return;
    }

    if (std.mem.eql(u8, name, "cms_delta")) {
        // delta == 1.0 violates 0 < delta < 1.
        var cms = try CountMin.optimal(allocator, 0.5, 1.0);
        defer cms.deinit();
        std.mem.doNotOptimizeAway(cms);
        return;
    }

    if (std.mem.eql(u8, name, "ss_m0")) {
        var ss = SpaceSaving.withCapacity(allocator, 0);
        defer ss.deinit();
        std.mem.doNotOptimizeAway(ss);
        return;
    }

    std.debug.print("unknown trap case: {s}\n", .{name});
    return error.UnknownTrapCase;
}

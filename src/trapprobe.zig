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

const Bloom = @import("bloom.zig").Bloom;
const hash = @import("hash.zig");

const cases = [_][]const u8{
    "bloom_m0", // Bloom.withParams(0, _): m_bits must be >= 1
    "bloom_n0", // Bloom.optimal(0, _): n_expected must be >= 1
    "bloom_p_zero", // Bloom.optimal(_, 0.0): p must be > 0
    "bloom_p_one", // Bloom.optimal(_, 1.0): p must be < 1
    "bloom_p_nan", // Bloom.optimal(_, NaN): p must be finite
    "bloom_p_inf", // Bloom.optimal(_, Inf): p must be finite
    "bloom_tobytes_short", // Bloom.toBytes(out): out.len must equal byteLen()
    "positions_out_short", // hash.positions(.., out) with out.len < k
    "hll_p_low", // hash.hllSplit(.., p < 4)
    "hll_p_high", // hash.hllSplit(.., p > 18)
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
    if (std.mem.eql(u8, name, "bloom_m0")) {
        // m_bits == 0 is the one construction error.
        var b = try Bloom.withParams(allocator, 0, 4);
        defer b.deinit();
        std.mem.doNotOptimizeAway(b);
        return;
    }

    if (std.mem.eql(u8, name, "bloom_n0")) {
        var b = try Bloom.optimal(allocator, 0, 0.01);
        defer b.deinit();
        std.mem.doNotOptimizeAway(b);
        return;
    }

    if (std.mem.eql(u8, name, "bloom_p_zero")) {
        // p == 0.0 violates 0 < p < 1.
        var b = try Bloom.optimal(allocator, 1000, 0.0);
        defer b.deinit();
        std.mem.doNotOptimizeAway(b);
        return;
    }

    if (std.mem.eql(u8, name, "bloom_p_one")) {
        // p == 1.0 violates 0 < p < 1.
        var b = try Bloom.optimal(allocator, 1000, 1.0);
        defer b.deinit();
        std.mem.doNotOptimizeAway(b);
        return;
    }

    if (std.mem.eql(u8, name, "bloom_p_nan")) {
        var b = try Bloom.optimal(allocator, 1000, std.math.nan(f64));
        defer b.deinit();
        std.mem.doNotOptimizeAway(b);
        return;
    }

    if (std.mem.eql(u8, name, "bloom_p_inf")) {
        var b = try Bloom.optimal(allocator, 1000, std.math.inf(f64));
        defer b.deinit();
        std.mem.doNotOptimizeAway(b);
        return;
    }

    if (std.mem.eql(u8, name, "bloom_tobytes_short")) {
        // out.len (1) != byteLen() (>= 2 for m_bits == 16) violates the
        // toBytes() caller contract.
        var b = try Bloom.withParams(allocator, 16, 4);
        defer b.deinit();
        var out: [1]u8 = undefined;
        b.toBytes(&out);
        std.mem.doNotOptimizeAway(&out);
        return;
    }

    if (std.mem.eql(u8, name, "positions_out_short")) {
        // out.len (1) < k (3) violates the positions() caller contract.
        var out: [1]u32 = undefined;
        hash.positions("x", 64, 3, &out);
        std.mem.doNotOptimizeAway(&out);
        return;
    }

    if (std.mem.eql(u8, name, "hll_p_low")) {
        // p == 3 violates 4 <= p <= 18.
        const s = hash.hllSplit("x", 3);
        std.mem.doNotOptimizeAway(s);
        return;
    }

    if (std.mem.eql(u8, name, "hll_p_high")) {
        // p == 19 violates 4 <= p <= 18.
        const s = hash.hllSplit("x", 19);
        std.mem.doNotOptimizeAway(s);
        return;
    }

    std.debug.print("unknown trap case: {s}\n", .{name});
    return error.UnknownTrapCase;
}

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
// With no args this executable re-execs each case and accepts only the selected
// production guard's diagnostic exit. A normal return, another panic, an error,
// or a signal must fail, including in ReleaseFast. The message is an internal
// test discriminator, not a public API promise.

const std = @import("std");

const intended_exit = 73;
var expected_message: ?[]const u8 = null;
pub const panic = std.debug.FullPanic(checkPanic);

fn checkPanic(message: []const u8, _: ?usize) noreturn {
    if (expected_message) |expected| {
        if (std.mem.eql(u8, message, expected)) std.process.exit(intended_exit);
    }
    std.debug.print("unexpected panic: {s}\n", .{message});
    std.process.exit(74);
}

const Bloom = @import("bloom.zig").Bloom;
const CountMin = @import("count_min.zig").CountMin;
const hash = @import("hash.zig");
const SpaceSaving = @import("space_saving.zig").SpaceSaving;

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
        expected_message = try expectedGuard(args[1]);
        try fireTrap(args[1], allocator);
        // Own error exit is intentionally rejected by the parent.
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
        child.stderr_behavior = .Inherit;

        const term = try child.spawnAndWait();
        if (term != .Exited or term.Exited != intended_exit) {
            std.debug.print(
                "trap case {s}: intended guard did not fire; termination {any}\n",
                .{ case_name, term },
            );
            return error.ExpectedTrapDidNotFire;
        }
    }
}

fn expectedGuard(name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, name, "bloom_m0")) return "Bloom.withParams: m_bits must be >= 1";
    if (std.mem.eql(u8, name, "bloom_n0")) return "Bloom.optimal: n_expected must be >= 1";
    if (std.mem.eql(u8, name, "bloom_p_zero")) return "Bloom.optimal: p must be finite and in (0, 1)";
    if (std.mem.eql(u8, name, "bloom_p_one")) return "Bloom.optimal: p must be finite and in (0, 1)";
    if (std.mem.eql(u8, name, "bloom_p_nan")) return "Bloom.optimal: p must be finite and in (0, 1)";
    if (std.mem.eql(u8, name, "bloom_p_inf")) return "Bloom.optimal: p must be finite and in (0, 1)";
    if (std.mem.eql(u8, name, "bloom_tobytes_short")) return "Bloom.toBytes: out.len must equal byteLen()";
    if (std.mem.eql(u8, name, "positions_out_short")) return "hash.positions: out.len must be >= k";
    if (std.mem.eql(u8, name, "hll_p_low")) return "hash.hllSplit: p must be in [4, 18]";
    if (std.mem.eql(u8, name, "hll_p_high")) return "hash.hllSplit: p must be in [4, 18]";
    if (std.mem.eql(u8, name, "cms_w0")) return "CountMin width w must be non-zero";
    if (std.mem.eql(u8, name, "cms_eps")) return "CountMin.optimal requires 0 < epsilon < 1";
    if (std.mem.eql(u8, name, "cms_delta")) return "CountMin.optimal requires 0 < delta < 1";
    if (std.mem.eql(u8, name, "ss_m0")) return "SpaceSaving capacity m must be non-zero";
    return error.UnknownTrapCase;
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

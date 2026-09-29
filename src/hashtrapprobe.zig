// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Out-of-process trap probe for the `hash.zig` caller-contract `@panic`
// preconditions that the in-process `zig build test` runner cannot intercept (a
// `@panic` aborts the process). These guards are ALWAYS-ON
// (`if (!cond) @panic(...)`, never `std.debug.assert`), so they must fire in
// every optimize mode including ReleaseFast/ReleaseSmall — which is exactly what
// this probe verifies.
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

const hash = @import("hash.zig");

const cases = [_][]const u8{
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
        expected_message = try expectedGuard(args[1]);
        try fireTrap(args[1]);
        // Own error exit is intentionally rejected by the parent.
        std.debug.print("trap case {s} returned normally\n", .{args[1]});
        return error.ExpectedTrapDidNotFire;
    }

    std.debug.print("usage: hashtrapprobe [case]\n", .{});
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
    if (std.mem.eql(u8, name, "positions_out_short")) return "hash.positions: out.len must be >= k";
    if (std.mem.eql(u8, name, "hll_p_low")) return "hash.hllSplit: p must be in [4, 18]";
    if (std.mem.eql(u8, name, "hll_p_high")) return "hash.hllSplit: p must be in [4, 18]";
    return error.UnknownTrapCase;
}

fn fireTrap(name: []const u8) !void {
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

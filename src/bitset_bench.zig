// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Workload benchmark for the streaming BitSet iterator.
//!
//! Run with:
//!   zig run -OReleaseFast -mcpu=native src/bitset_bench.zig
//!
//! Builds a sieve-of-Eratosthenes bit set (realistic dense write pattern) and
//! times iterating every set bit two ways on the *same* BitSet:
//!   * streaming `iterator()`  — keeps the live word, clears via `word &= word-1`
//!   * rescan `nextSetBit(b+1)` — the previous per-bit re-scan
//! They yield identical sequences; the streaming form is ~4-5x faster.

const std = @import("std");
const BitSet = @import("bitset/bit_set.zig").BitSet;

fn streamSum(bs: *const BitSet) u64 {
    var s: u64 = 0;
    var it = bs.iterator();
    while (it.next()) |bit| s +%= bit;
    return s;
}

fn rescanSum(bs: *const BitSet) u64 {
    var s: u64 = 0;
    var b = bs.nextSetBit(0);
    while (b) |bit| {
        s +%= bit;
        b = bs.nextSetBit(bit + 1);
    }
    return s;
}

fn bestNs(comptime f: fn (*const BitSet) u64, bs: *const BitSet, rounds: u32) struct { ns: u64, sink: u64 } {
    var sink: u64 = f(bs); // warm
    var best: u64 = std.math.maxInt(u64);
    var r: u32 = 0;
    while (r < rounds) : (r += 1) {
        var t = std.time.Timer.start() catch unreachable;
        sink +%= f(bs);
        const ns = t.read();
        if (ns < best) best = ns;
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .ns = best, .sink = sink };
}

fn mps(items: usize, ns: u64) f64 {
    return @as(f64, @floatFromInt(items)) / (@as(f64, @floatFromInt(ns)) / 1e9) / 1e6;
}

fn run(allocator: std.mem.Allocator, n: usize, rounds: u32) !void {
    var sieve = BitSet.init(allocator);
    defer sieve.deinit();
    try sieve.set(0);
    var i: usize = 2;
    while (i * i < n) : (i += 1) {
        if (!sieve.get(i)) {
            var j = i * i;
            while (j < n) : (j += i) try sieve.set(j);
        }
    }
    const set = sieve.cardinality();
    std.debug.print("\nn={d}: {d} composite bits ({d:.1}%)\n", .{ n, set, 100.0 * @as(f64, @floatFromInt(set)) / @as(f64, @floatFromInt(n)) });

    const rs = bestNs(rescanSum, &sieve, rounds);
    const st = bestNs(streamSum, &sieve, rounds);
    if (rs.sink != st.sink) return error.Mismatch;
    std.debug.print("  rescan nextSetBit(b+1)  {d:>9.3} ms  {d:>8.1} Mitem/s\n", .{ @as(f64, @floatFromInt(rs.ns)) / 1e6, mps(set, rs.ns) });
    std.debug.print("  streaming (BLSR)        {d:>9.3} ms  {d:>8.1} Mitem/s\n", .{ @as(f64, @floatFromInt(st.ns)) / 1e6, mps(set, st.ns) });
    std.debug.print("  => streaming speedup:   {d:.2}x\n", .{@as(f64, @floatFromInt(rs.ns)) / @as(f64, @floatFromInt(st.ns))});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    std.debug.print("bitset_bench — streaming vs rescan set-bit iteration\n", .{});
    try run(a, 1_000_000, 25);
    try run(a, 8_000_000, 25);
}

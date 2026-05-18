// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Comparative benchmark: per-primitive specialization vs comptime generics.
//
// Two shapes ship side-by-side in mapdb-zig today:
//   1. `src/arraylist/i32_array_list.zig` — hand-named per-primitive type.
//   2. `src/object/arraylist.zig`         — generic `ArrayList(comptime T)`.
//
// Both wrap `std.ArrayListUnmanaged(T)`. Comptime monomorphisation should
// produce machine code indistinguishable between the two. This benchmark
// confirms that: identical operations on identical workloads should land
// within measurement noise of each other.
//
// Run with: zig build-exe -O ReleaseFast bench/specialization_bench.zig
//                          -I src --dep mapdb_collections
// or via `zig build bench`.

const std = @import("std");

const SpecificI32ArrayList = @import("arraylist/i32_array_list.zig").I32ArrayList;
const GenericArrayList = @import("object/arraylist.zig").ArrayList;

const N: usize = 10_000_000;
const TRIALS: usize = 5;

fn nowNs() i128 {
    return std.time.nanoTimestamp();
}

fn bench_specific_push(allocator: std.mem.Allocator) i128 {
    var list = SpecificI32ArrayList.init(allocator);
    defer list.deinit();
    list.items.ensureUnusedCapacity(list.config.itemsAllocator(), N) catch unreachable;
    const t0 = nowNs();
    var i: i32 = 0;
    while (i < @as(i32, @intCast(N))) : (i += 1) list.add(i);
    return nowNs() - t0;
}

fn bench_generic_push(allocator: std.mem.Allocator) i128 {
    var list = GenericArrayList(i32).init(allocator);
    defer list.deinit();
    list.inner.ensureUnusedCapacity(list.allocator, N) catch unreachable;
    const t0 = nowNs();
    var i: i32 = 0;
    while (i < @as(i32, @intCast(N))) : (i += 1) list.push(i);
    return nowNs() - t0;
}

fn bench_specific_sum(allocator: std.mem.Allocator) struct { ns: i128, sum: i64 } {
    var list = SpecificI32ArrayList.init(allocator);
    defer list.deinit();
    list.items.ensureUnusedCapacity(list.config.itemsAllocator(), N) catch unreachable;
    var i: i32 = 0;
    while (i < @as(i32, @intCast(N))) : (i += 1) list.add(i);
    const t0 = nowNs();
    const s: i64 = list.sum();
    return .{ .ns = nowNs() - t0, .sum = s };
}

fn bench_generic_sum(allocator: std.mem.Allocator) struct { ns: i128, sum: i64 } {
    var list = GenericArrayList(i32).init(allocator);
    defer list.deinit();
    list.inner.ensureUnusedCapacity(list.allocator, N) catch unreachable;
    var i: i32 = 0;
    while (i < @as(i32, @intCast(N))) : (i += 1) list.push(i);
    // GenericArrayList has no `sum`. Inline the same loop body so we are
    // benchmarking storage access, not method presence.
    const t0 = nowNs();
    var s: i64 = 0;
    for (list.inner.items) |v| s += @as(i64, @intCast(v));
    return .{ .ns = nowNs() - t0, .sum = s };
}

fn bench_specific_contains(allocator: std.mem.Allocator) i128 {
    var list = SpecificI32ArrayList.init(allocator);
    defer list.deinit();
    list.items.ensureUnusedCapacity(list.config.itemsAllocator(), N) catch unreachable;
    var i: i32 = 0;
    while (i < @as(i32, @intCast(N))) : (i += 1) list.add(i);
    const t0 = nowNs();
    // Worst-case: probe a value past the end so the linear scan touches
    // every element.
    const found = list.contains(-1);
    std.mem.doNotOptimizeAway(found);
    return nowNs() - t0;
}

fn bench_generic_contains(allocator: std.mem.Allocator) i128 {
    var list = GenericArrayList(i32).init(allocator);
    defer list.deinit();
    list.inner.ensureUnusedCapacity(list.allocator, N) catch unreachable;
    var i: i32 = 0;
    while (i < @as(i32, @intCast(N))) : (i += 1) list.push(i);
    const t0 = nowNs();
    const found = list.contains(-1);
    std.mem.doNotOptimizeAway(found);
    return nowNs() - t0;
}

fn report(name: []const u8, samples: []const i128) void {
    var total: i128 = 0;
    var min: i128 = std.math.maxInt(i128);
    var max: i128 = 0;
    for (samples) |s| {
        total += s;
        if (s < min) min = s;
        if (s > max) max = s;
    }
    const mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(samples.len));
    std.debug.print("{s:<32} min={d:>10} mean={d:>10.0} max={d:>10}  (ns over {d} elems)\n", .{
        name,
        min,
        mean,
        max,
        N,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("specialization benchmark — {d} elements × {d} trials, optimize={s}\n", .{
        N,
        TRIALS,
        @tagName(@import("builtin").mode),
    });
    std.debug.print("\n", .{});

    var spec_push: [TRIALS]i128 = undefined;
    var gen_push: [TRIALS]i128 = undefined;
    var spec_sum: [TRIALS]i128 = undefined;
    var gen_sum: [TRIALS]i128 = undefined;
    var spec_contains: [TRIALS]i128 = undefined;
    var gen_contains: [TRIALS]i128 = undefined;

    var t: usize = 0;
    while (t < TRIALS) : (t += 1) {
        spec_push[t] = bench_specific_push(allocator);
        gen_push[t] = bench_generic_push(allocator);

        const ss = bench_specific_sum(allocator);
        spec_sum[t] = ss.ns;
        std.mem.doNotOptimizeAway(ss.sum);
        const gs = bench_generic_sum(allocator);
        gen_sum[t] = gs.ns;
        std.mem.doNotOptimizeAway(gs.sum);

        spec_contains[t] = bench_specific_contains(allocator);
        gen_contains[t] = bench_generic_contains(allocator);
    }

    report("push (per-primitive)", &spec_push);
    report("push (generic)      ", &gen_push);
    std.debug.print("\n", .{});
    report("sum (per-primitive) ", &spec_sum);
    report("sum (generic)       ", &gen_sum);
    std.debug.print("\n", .{});
    report("contains (per-prim) ", &spec_contains);
    report("contains (generic)  ", &gen_contains);
}

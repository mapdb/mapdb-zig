// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Benchmark and stress test for Zig collections.
// Run: `zig build bench` (compiles this file in ReleaseFast against the
// library module). Pure-read loops are guarded with std.mem.doNotOptimizeAway
// so ReleaseFast cannot dead-code-eliminate them into 0 ns/op.

const std = @import("std");
const root = @import("mapdb_collections");
const I32I32HashMap = root.hashmap.i32_i32_hash_map.I32I32HashMap;
const I32HashSet = root.hashset.i32_hash_set.I32HashSet;
const I32ArrayList = root.arraylist.i32_array_list.I32ArrayList;
const I32HashBag = root.bag.i32_hash_bag.I32HashBag;
const F32F32HashMap = root.hashmap.f32_f32_hash_map.F32F32HashMap;
const I32ArrayDeque = root.deque.i32_array_deque.I32ArrayDeque;
const I32PriorityQueue = root.priority_queue.i32_priority_queue.I32PriorityQueue;
const BitSet = root.bitset.bit_set.BitSet;

const N: usize = 100_000;
const WARM: usize = 3;

fn nanos() i128 {
    return std.time.nanoTimestamp();
}

pub fn main() !void {
    std.debug.print("=== Zig Benchmark ===\nN={}\n\n", .{N});

    const alloc = std.heap.page_allocator;

    // HashMap.put
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) {
                _ = try m.put(i, i * 10);
            }
            const d: u64 = @intCast(nanos() - start);
            if (d < best) best = d;
        }
        std.debug.print("HashMap.put         {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // HashMap.get
    {
        var m = I32I32HashMap.init(alloc);
        defer m.deinit();
        var i: i32 = 0;
        while (i < N) : (i += 1) _ = try m.put(i, i * 10);

        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                std.mem.doNotOptimizeAway(m.get(i));
            }
            const d: u64 = @intCast(nanos() - start);
            if (d < best) best = d;
        }
        std.debug.print("HashMap.get         {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // HashMap.remove
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = try m.put(i, i * 10);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                _ = m.remove(i);
            }
            const d: u64 = @intCast(nanos() - start);
            if (d < best) best = d;
        }
        std.debug.print("HashMap.remove      {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // HashMap.forEach
    {
        var m = I32I32HashMap.init(alloc);
        defer m.deinit();
        var i: i32 = 0;
        while (i < N) : (i += 1) _ = try m.put(i, i * 10);

        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            const start = nanos();
            m.forEachValue({}, struct {
                fn f(_: void, v: i32) void {
                    std.mem.doNotOptimizeAway(v);
                }
            }.f);
            const d: u64 = @intCast(nanos() - start);
            if (d < best) best = d;
        }
        std.debug.print("HashMap.iterate     {} entries  {d:.3}ms  ({} ns/entry)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // HashSet.add
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) {
                _ = try s.add(i);
            }
            const d: u64 = @intCast(nanos() - start);
            if (d < best) best = d;
        }
        std.debug.print("HashSet.add         {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // HashSet.contains
    {
        var s = I32HashSet.init(alloc);
        defer s.deinit();
        var i: i32 = 0;
        while (i < N) : (i += 1) _ = try s.add(i);

        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                std.mem.doNotOptimizeAway(s.contains(i));
            }
            const d: u64 = @intCast(nanos() - start);
            if (d < best) best = d;
        }
        std.debug.print("HashSet.contains    {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // ArrayList.add
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) {
                try a.push(i);
            }
            const d: u64 = @intCast(nanos() - start);
            if (d < best) best = d;
        }
        std.debug.print("ArrayList.add       {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // Bag.add
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) {
                try b.add(@rem(i, 1000));
            }
            const d: u64 = @intCast(nanos() - start);
            if (d < best) best = d;
        }
        std.debug.print("Bag.add             {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // ArrayDeque.addLast
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var d = I32ArrayDeque.init(alloc);
            defer d.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) {
                try d.addLast(i);
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("ArrayDeque.addLast  {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // ArrayDeque.peek
    {
        var d = I32ArrayDeque.init(alloc);
        defer d.deinit();
        var i: i32 = 0;
        while (i < N) : (i += 1) try d.addLast(i);

        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                std.mem.doNotOptimizeAway(d.peekFirst());
                std.mem.doNotOptimizeAway(d.peekLast());
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("ArrayDeque.peek     {} ops  {d:.3}ms  ({} ns/op)\n", .{ N * 2, @as(f64, @floatFromInt(best)) / 1e6, best / (N * 2) });
    }

    // ArrayDeque.removeFirst
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var d = I32ArrayDeque.init(alloc);
            defer d.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) try d.addLast(i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                std.mem.doNotOptimizeAway(d.removeFirst());
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("ArrayDeque.remove   {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // PriorityQueue.push
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var q = I32PriorityQueue.init(alloc);
            defer q.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) {
                try q.push(i);
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("PriorityQueue.push  {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // PriorityQueue.peek
    {
        var q = I32PriorityQueue.init(alloc);
        defer q.deinit();
        var i: i32 = 0;
        while (i < N) : (i += 1) try q.push(i);

        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                std.mem.doNotOptimizeAway(q.peek());
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("PriorityQueue.peek  {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // PriorityQueue.pop
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var q = I32PriorityQueue.init(alloc);
            defer q.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) try q.push(i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                _ = q.pop();
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("PriorityQueue.pop   {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // BitSet.set
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var b = BitSet.init(alloc);
            defer b.deinit();
            const start = nanos();
            var i: usize = 0;
            while (i < N) : (i += 1) {
                try b.set(i);
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("BitSet.set          {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // BitSet.get
    {
        var b = BitSet.init(alloc);
        defer b.deinit();
        var i: usize = 0;
        while (i < N) : (i += 1) try b.set(i);

        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                std.mem.doNotOptimizeAway(b.get(i));
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("BitSet.get          {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // BitSet.clearBit
    {
        var best: u64 = std.math.maxInt(u64);
        var w: usize = 0;
        while (w < WARM) : (w += 1) {
            var b = BitSet.init(alloc);
            defer b.deinit();
            var i: usize = 0;
            while (i < N) : (i += 1) try b.set(i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) {
                b.clearBit(i);
            }
            const elapsed: u64 = @intCast(nanos() - start);
            if (elapsed < best) best = elapsed;
        }
        std.debug.print("BitSet.clearBit     {} ops  {d:.3}ms  ({} ns/op)\n", .{ N, @as(f64, @floatFromInt(best)) / 1e6, best / N });
    }

    // === Stress Tests ===
    std.debug.print("\n=== Stress Tests ===\n", .{});

    // Collision keys
    {
        var m = I32I32HashMap.init(alloc);
        defer m.deinit();
        const start = nanos();
        var i: i32 = 0;
        while (i < 10000) : (i += 1) {
            _ = try m.put(i * 16, i);
        }
        const d: u64 = @intCast(nanos() - start);
        var ok = true;
        i = 0;
        while (i < 10000) : (i += 1) {
            if (m.get(i * 16) == null) {
                ok = false;
                break;
            }
        }
        std.debug.print("STRESS collision_keys   10000 ops  {d:.3}ms  all_found={}\n", .{ @as(f64, @floatFromInt(d)) / 1e6, ok });
    }

    // Delete heavy
    {
        var m = I32I32HashMap.init(alloc);
        defer m.deinit();
        var i: i32 = 0;
        while (i < 50000) : (i += 1) _ = try m.put(i, i);
        const start = nanos();
        i = 0;
        while (i < 50000) : (i += 2) _ = m.remove(i);
        i = 50000;
        while (i < 75000) : (i += 1) _ = try m.put(i, i);
        i = 0;
        while (i < 75000) : (i += 1) _ = m.remove(i);
        const d: u64 = @intCast(nanos() - start);
        std.debug.print("STRESS delete_heavy    125000 ops  {d:.3}ms  size={} (expect 0)\n", .{ @as(f64, @floatFromInt(d)) / 1e6, m.len() });
    }

    // Resize cycles
    {
        var m = I32I32HashMap.init(alloc);
        defer m.deinit();
        const start = nanos();
        var cycle: usize = 0;
        while (cycle < 10) : (cycle += 1) {
            var i: i32 = 0;
            while (i < 10000) : (i += 1) _ = try m.put(i, i);
            m.clear();
        }
        const d: u64 = @intCast(nanos() - start);
        std.debug.print("STRESS resize_cycles   100000 ops  {d:.3}ms  size={} (expect 0)\n", .{ @as(f64, @floatFromInt(d)) / 1e6, m.len() });
    }

    // Float edge cases
    {
        var m = F32F32HashMap.init(alloc);
        defer m.deinit();
        _ = try m.put(1.0, 10.0);
        _ = try m.put(-0.0, 20.0);
        _ = try m.put(std.math.inf(f32), 30.0);
        _ = try m.put(std.math.nan(f32), 40.0);
        _ = try m.put(std.math.nan(f32), 50.0); // NaN overwrite
        const nan_val = m.get(std.math.nan(f32));
        const neg_zero = m.get(-0.0);
        const inf_val = m.get(std.math.inf(f32));
        std.debug.print("STRESS float_keys      NaN={?} -0.0={?} Inf={?} size={} (expect 4)\n", .{ nan_val, neg_zero, inf_val, m.len() });
    }

    // Edge keys
    {
        var m = I32I32HashMap.init(alloc);
        defer m.deinit();
        _ = try m.put(0, 100);
        _ = try m.put(-1, 200);
        _ = try m.put(std.math.maxInt(i32), 300);
        _ = try m.put(std.math.minInt(i32), 400);
        const ok = m.len() == 4 and
            m.get(0) != null and
            m.get(std.math.maxInt(i32)) != null and
            m.get(std.math.minInt(i32)) != null;
        std.debug.print("STRESS edge_keys       boundary values  ok={}\n", .{ok});
    }
}

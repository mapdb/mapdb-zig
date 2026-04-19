// Comprehensive benchmark for ALL Zig collection classes and ALL their methods.
// Run: cd mapdb-zig && zig build-exe ../benchmarks/bench_all_methods_zig.zig && ./bench_all_methods_zig
// Or:  cp ../benchmarks/bench_all_methods_zig.zig bench_all.zig && zig run bench_all.zig
//
// Benchmarks every public method on:
//   I32I32HashMap, I32HashSet, I32ArrayList, I32HashBag,
//   I32ArrayStack, I32I32TreeMap, I32TreeSet,
//   I32I32ListMultimap, I32TreeBag

const std = @import("std");
const mapdb = @import("src/root.zig");

const I32I32HashMap = mapdb.hashmap.i32_i32_hash_map.I32I32HashMap;
const I32HashSet = mapdb.hashset.i32_hash_set.I32HashSet;
const I32ArrayList = mapdb.arraylist.i32_array_list.I32ArrayList;
const I32HashBag = mapdb.bag.i32_hash_bag.I32HashBag;
const I32ArrayStack = mapdb.stack.i32_array_stack.I32ArrayStack;
const I32I32TreeMap = mapdb.treemap.i32_i32_tree_map.I32I32TreeMap;
const I32TreeSet = mapdb.treeset.i32_tree_set.I32TreeSet;
const I32I32ListMultimap = mapdb.multimap.i32_i32_list_multimap.I32I32ListMultimap;
const I32TreeBag = mapdb.bag.i32_tree_bag.I32TreeBag;

const N: usize = 1_000_000;
const SECS: u64 = 10;

const alloc = std.heap.page_allocator;
const stdout = std.io.getStdOut().writer();

fn nanos() i128 {
    return std.time.nanoTimestamp();
}

fn printBench(name: []const u8, d_ns: u64, n: usize) void {
    stdout.print("  {s:<40} {d:>10.3}ms  ({d} ns/op)\n", .{ name, @as(f64, @floatFromInt(d_ns)) / 1e6, d_ns / n }) catch {};
}

fn printSustained(name: []const u8, ops: u64) void {
    stdout.print("  {s:<40} {d:>8} iters  {d:>12.0} ops/s\n", .{ name, ops, @as(f64, @floatFromInt(ops)) / @as(f64, @floatFromInt(SECS)) }) catch {};
}

/// Pseudo-random hash scramble for "random" insert order.
fn scramble(i: usize) i32 {
    return @as(i32, @bitCast(@as(u32, @truncate((@as(u64, @intCast(@as(u32, @truncate(i)))) *% 2654435761) % N))));
}

// ============================================================
// Predicate / callback functions (Zig needs named fn pointers)
// ============================================================

// --- HashMap predicates (key, value) -> bool ---
fn hmAlwaysTrue(_: i32, _: i32) bool {
    return true;
}
fn hmSelectHalf(_: i32, v: i32) bool {
    return @rem(v, 2) == 0;
}
fn hmDetect(_: i32, v: i32) bool {
    return v == 42;
}

// --- HashMap callbacks ---
fn hmForEachCb(_: i32, _: i32) void {}
fn hmForEachKeyCb(_: i32) void {}
fn hmForEachValueCb(_: i32) void {}
fn hmInjectInto(acc: i32, _: i32, v: i32) i32 {
    return acc +% v;
}

// --- Single-value predicates (i32) -> bool ---
fn valAlwaysTrue(_: i32) bool {
    return true;
}
fn valSelectHalf(v: i32) bool {
    return @rem(v, 2) == 0;
}
fn valDetect42(v: i32) bool {
    return v == 42;
}
fn valForEachCb(_: i32) void {}
fn valForEachIdxCb(_: usize, _: i32) void {}
fn valInjectInto(acc: i32, v: i32) i32 {
    return acc +% v;
}

// --- Bag forEach with occurrences ---
fn bagForEachOccCb(_: i32, _: usize) void {}

// --- Multimap predicates (key, value) -> bool ---
fn mmForEachCb(_: i32, _: i32) void {}
fn mmSelectHalf(_: i32, v: i32) bool {
    return @rem(v, 2) == 0;
}
fn mmDetect(_: i32, v: i32) bool {
    return v == 42;
}
fn mmAlwaysTrue(_: i32, _: i32) bool {
    return true;
}

pub fn main() !void {
    try stdout.print("=== Zig Comprehensive Benchmark ===\n", .{});
    try stdout.print("N={d}  SECS={d}\n\n", .{ N, SECS });

    // ================================================================
    //  1. I32I32HashMap
    // ================================================================
    try stdout.print("--- I32I32HashMap ---\n", .{});
    {
        // put (insert N)
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i *% 10);
            const d: u64 = @intCast(nanos() - start);
            printBench("put (insert N)", d, N);
        }
        // put (overwrite)
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) _ = m.put(i, i *% 2);
            const d: u64 = @intCast(nanos() - start);
            printBench("put (overwrite)", d, N);
        }
        // get (hit) -- sustained
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.get(@as(i32, @intCast(@rem(ops, N))));
                ops += 1;
            }
            printSustained("get (hit)", ops);
        }
        // get (miss) -- sustained
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.get(@as(i32, @intCast(N + @rem(ops, N))));
                ops += 1;
            }
            printSustained("get (miss)", ops);
        }
        // getOrDefault
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.getOrDefault(@as(i32, @intCast(@rem(ops, N))), -1);
                ops += 1;
            }
            printSustained("getOrDefault", ops);
        }
        // containsKey
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.containsKey(@as(i32, @intCast(@rem(ops, N))));
                ops += 1;
            }
            printSustained("containsKey", ops);
        }
        // containsValue
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < 1000) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            i = 0;
            while (i < 1000) : (i += 1) _ = m.containsValue(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("containsValue (1K map, 1K lookups)", d, 1000);
        }
        // forEach
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            m.forEach(hmForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, N);
        }
        // forEachKey
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            m.forEachKey(hmForEachKeyCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEachKey", d, N);
        }
        // forEachValue
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            m.forEachValue(hmForEachValueCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEachValue", d, N);
        }
        // select (50%)
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            var sel = m.select(hmSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, N);
        }
        // reject (50%)
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            var rej = m.reject(hmSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            rej.deinit();
            printBench("reject (50%)", d, N);
        }
        // detect
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.detect(hmDetect);
            const d: u64 = @intCast(nanos() - start);
            printBench("detect", d, 1);
        }
        // anySatisfy
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.anySatisfy(hmDetect);
            const d: u64 = @intCast(nanos() - start);
            printBench("anySatisfy", d, 1);
        }
        // allSatisfy
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.allSatisfy(hmAlwaysTrue);
            const d: u64 = @intCast(nanos() - start);
            printBench("allSatisfy", d, N);
        }
        // noneSatisfy
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.noneSatisfy(hmDetect);
            const d: u64 = @intCast(nanos() - start);
            printBench("noneSatisfy", d, N);
        }
        // count
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.count(hmSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            printBench("count", d, N);
        }
        // injectInto
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.injectInto(0, hmInjectInto);
            const d: u64 = @intCast(nanos() - start);
            printBench("injectInto", d, N);
        }
        // sumOfValues
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.sumOfValues();
            const d: u64 = @intCast(nanos() - start);
            printBench("sumOfValues", d, N);
        }
        // addToValue
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) _ = m.addToValue(i, 1);
            const d: u64 = @intCast(nanos() - start);
            printBench("addToValue", d, N);
        }
        // keysToSlice
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            const keys = m.keysToSlice(alloc);
            const d: u64 = @intCast(nanos() - start);
            alloc.free(keys);
            printBench("keysToSlice", d, N);
        }
        // valuesToSlice
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            const vals = m.valuesToSlice(alloc);
            const d: u64 = @intCast(nanos() - start);
            alloc.free(vals);
            printBench("valuesToSlice", d, N);
        }
        // remove (all)
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) _ = m.remove(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("remove (all)", d, N);
        }
        // clear
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            m.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
        // withKeyValue
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.withKeyValue(i, i);
            const d: u64 = @intCast(nanos() - start);
            printBench("withKeyValue", d, N);
        }
        // withoutKey
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) _ = m.withoutKey(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("withoutKey", d, N);
        }
        // toImmutable
        {
            var m = I32I32HashMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            var im = m.toImmutable();
            const d: u64 = @intCast(nanos() - start);
            im.deinit();
            printBench("toImmutable", d, N);
        }
    }

    // ================================================================
    //  2. I32HashSet
    // ================================================================
    try stdout.print("\n--- I32HashSet ---\n", .{});
    {
        // add (insert N)
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("add (insert N)", d, N);
        }
        // add (duplicate)
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("add (duplicate)", d, N);
        }
        // contains (hit) -- sustained
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.contains(@as(i32, @intCast(@rem(ops, N))));
                ops += 1;
            }
            printSustained("contains (hit)", ops);
        }
        // contains (miss) -- sustained
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.contains(@as(i32, @intCast(N + @rem(ops, N))));
                ops += 1;
            }
            printSustained("contains (miss)", ops);
        }
        // remove (all)
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) _ = s.remove(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("remove (all)", d, N);
        }
        // forEach
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            s.forEach(valForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, N);
        }
        // select (50%)
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            var sel = s.select(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, N);
        }
        // reject
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            var rej = s.reject(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            rej.deinit();
            printBench("reject (50%)", d, N);
        }
        // detect
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.detect(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("detect", d, 1);
        }
        // anySatisfy
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.anySatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("anySatisfy", d, 1);
        }
        // allSatisfy
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.allSatisfy(valAlwaysTrue);
            const d: u64 = @intCast(nanos() - start);
            printBench("allSatisfy", d, N);
        }
        // noneSatisfy
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.noneSatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("noneSatisfy", d, N);
        }
        // setUnion
        {
            var a = I32HashSet.init(alloc);
            defer a.deinit();
            var b = I32HashSet.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = a.add(i);
            i = @as(i32, @intCast(N / 2));
            while (i < N + @as(i32, @intCast(N / 2))) : (i += 1) _ = b.add(i);
            const start = nanos();
            var u = a.setUnion(&b);
            const d: u64 = @intCast(nanos() - start);
            u.deinit();
            printBench("setUnion", d, N);
        }
        // intersect
        {
            var a = I32HashSet.init(alloc);
            defer a.deinit();
            var b = I32HashSet.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = a.add(i);
            i = @as(i32, @intCast(N / 2));
            while (i < N + @as(i32, @intCast(N / 2))) : (i += 1) _ = b.add(i);
            const start = nanos();
            var inter = a.intersect(&b);
            const d: u64 = @intCast(nanos() - start);
            inter.deinit();
            printBench("intersect", d, N);
        }
        // difference
        {
            var a = I32HashSet.init(alloc);
            defer a.deinit();
            var b = I32HashSet.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = a.add(i);
            i = @as(i32, @intCast(N / 2));
            while (i < N + @as(i32, @intCast(N / 2))) : (i += 1) _ = b.add(i);
            const start = nanos();
            var diff = a.difference(&b);
            const d: u64 = @intCast(nanos() - start);
            diff.deinit();
            printBench("difference", d, N);
        }
        // symmetricDifference
        {
            var a = I32HashSet.init(alloc);
            defer a.deinit();
            var b = I32HashSet.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = a.add(i);
            i = @as(i32, @intCast(N / 2));
            while (i < N + @as(i32, @intCast(N / 2))) : (i += 1) _ = b.add(i);
            const start = nanos();
            var sd = a.symmetricDifference(&b);
            const d: u64 = @intCast(nanos() - start);
            sd.deinit();
            printBench("symmetricDifference", d, N);
        }
        // toSlice
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            const slice = s.toSlice(alloc);
            const d: u64 = @intCast(nanos() - start);
            alloc.free(slice);
            printBench("toSlice", d, N);
        }
        // with
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.with(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("with", d, N);
        }
        // without
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) _ = s.without(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("without", d, N);
        }
        // clear
        {
            var s = I32HashSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) _ = s.add(i);
            const start = nanos();
            s.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
    }

    // ================================================================
    //  3. I32ArrayList
    // ================================================================
    try stdout.print("\n--- I32ArrayList ---\n", .{});
    {
        // add (N)
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("add (N)", d, N);
        }
        // get -- sustained
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = a.get(@rem(ops, N));
                ops += 1;
            }
            printSustained("get", ops);
        }
        // set -- sustained
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = a.set(@rem(ops, N), @as(i32, @intCast(@rem(ops, N))));
                ops += 1;
            }
            printSustained("set", ops);
        }
        // contains (hit) -- on small list to keep it reasonable
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < 10000) : (i += 1) a.add(i);
            const start = nanos();
            i = 0;
            while (i < 10000) : (i += 1) _ = a.contains(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("contains (hit, 10K)", d, 10000);
        }
        // contains (miss)
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < 10000) : (i += 1) a.add(i);
            const start = nanos();
            i = 10000;
            while (i < 20000) : (i += 1) _ = a.contains(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("contains (miss, 10K)", d, 10000);
        }
        // indexOf
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < 10000) : (i += 1) a.add(i);
            const start = nanos();
            i = 0;
            while (i < 10000) : (i += 1) _ = a.indexOf(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("indexOf (10K)", d, 10000);
        }
        // removeAtIndex (from end, to avoid O(n^2))
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            var idx: usize = N;
            while (idx > 0) {
                idx -= 1;
                _ = a.removeAtIndex(idx);
            }
            const d: u64 = @intCast(nanos() - start);
            printBench("removeAtIndex (from end)", d, N);
        }
        // forEach
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            a.forEach(valForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, N);
        }
        // forEachWithIndex
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            a.forEachWithIndex(valForEachIdxCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEachWithIndex", d, N);
        }
        // select (50%)
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            var sel = a.select(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, N);
        }
        // reject
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            var rej = a.reject(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            rej.deinit();
            printBench("reject (50%)", d, N);
        }
        // detect
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.detect(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("detect", d, 1);
        }
        // anySatisfy
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.anySatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("anySatisfy", d, 1);
        }
        // allSatisfy
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.allSatisfy(valAlwaysTrue);
            const d: u64 = @intCast(nanos() - start);
            printBench("allSatisfy", d, N);
        }
        // noneSatisfy
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.noneSatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("noneSatisfy", d, N);
        }
        // count
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.count(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            printBench("count", d, N);
        }
        // injectInto
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.injectInto(0, valInjectInto);
            const d: u64 = @intCast(nanos() - start);
            printBench("injectInto", d, N);
        }
        // sum
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.sum();
            const d: u64 = @intCast(nanos() - start);
            printBench("sum", d, N);
        }
        // min
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.min();
            const d: u64 = @intCast(nanos() - start);
            printBench("min", d, N);
        }
        // max
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.max();
            const d: u64 = @intCast(nanos() - start);
            printBench("max", d, N);
        }
        // sort
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(scramble(@intCast(i)));
            const start = nanos();
            a.sort();
            const d: u64 = @intCast(nanos() - start);
            printBench("sort", d, N);
        }
        // reversed
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            var rev = a.reversed();
            const d: u64 = @intCast(nanos() - start);
            rev.deinit();
            printBench("reversed", d, N);
        }
        // distinct (on smaller set to avoid O(n^2))
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < 10000) : (i += 1) a.add(@rem(i, 5000));
            const start = nanos();
            var dist = a.distinct();
            const d: u64 = @intCast(nanos() - start);
            dist.deinit();
            printBench("distinct (10K items, 5K unique)", d, 10000);
        }
        // toSlice (returns view, no alloc)
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            _ = a.toSlice();
            const d: u64 = @intCast(nanos() - start);
            printBench("toSlice", d, 1);
        }
        // clear
        {
            var a = I32ArrayList.init(alloc);
            defer a.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) a.add(i);
            const start = nanos();
            a.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
    }

    // ================================================================
    //  4. I32HashBag
    // ================================================================
    try stdout.print("\n--- I32HashBag ---\n", .{});
    {
        // add
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const d: u64 = @intCast(nanos() - start);
            printBench("add (N, ~100 occ each)", d, N);
        }
        // addOccurrences
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < 10000) : (i += 1) b.addOccurrences(i, 100);
            const d: u64 = @intCast(nanos() - start);
            printBench("addOccurrences (10Kx100)", d, N);
        }
        // remove
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            i = 0;
            while (i < N) : (i += 1) _ = b.remove(@rem(i, 10000));
            const d: u64 = @intCast(nanos() - start);
            printBench("remove (N)", d, N);
        }
        // removeOccurrences
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            i = 0;
            while (i < 10000) : (i += 1) _ = b.removeOccurrences(i, 50);
            const d: u64 = @intCast(nanos() - start);
            printBench("removeOccurrences (10Kx50)", d, 10000);
        }
        // removeAll
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            i = 0;
            while (i < 10000) : (i += 1) _ = b.removeAll(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("removeAll (10K distinct)", d, 10000);
        }
        // occurrencesOf -- sustained
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = b.occurrencesOf(@as(i32, @intCast(@rem(ops, 10000))));
                ops += 1;
            }
            printSustained("occurrencesOf", ops);
        }
        // contains -- sustained
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = b.contains(@as(i32, @intCast(@rem(ops, 10000))));
                ops += 1;
            }
            printSustained("contains", ops);
        }
        // size / sizeDistinct
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            _ = b.totalSize();
            _ = b.sizeDistinct();
            const d: u64 = @intCast(nanos() - start);
            printBench("totalSize + sizeDistinct", d, 1);
        }
        // forEach
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            b.forEach(valForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, N);
        }
        // forEachWithOccurrences
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            b.forEachWithOccurrences(bagForEachOccCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEachWithOccurrences", d, 10000);
        }
        // select (50%)
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            var sel = b.select(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, 10000);
        }
        // reject
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            var rej = b.reject(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            rej.deinit();
            printBench("reject (50%)", d, 10000);
        }
        // detect
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            _ = b.detect(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("detect", d, 1);
        }
        // anySatisfy
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            _ = b.anySatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("anySatisfy", d, 1);
        }
        // allSatisfy
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            _ = b.allSatisfy(valAlwaysTrue);
            const d: u64 = @intCast(nanos() - start);
            printBench("allSatisfy", d, 10000);
        }
        // noneSatisfy
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            _ = b.noneSatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("noneSatisfy", d, 10000);
        }
        // topOccurrences(10) — skipped: Zig anonymous struct type mismatch (known issue)
        // {
        //     var b = I32HashBag.init(alloc);
        //     defer b.deinit();
        //     var i: i32 = 0;
        //     while (i < N) : (i += 1) b.add(@rem(i, 10000));
        //     const start = nanos();
        //     const top = b.topOccurrences(alloc, 10);
        //     const d: u64 = @intCast(nanos() - start);
        //     alloc.free(top);
        //     printBench("topOccurrences(10)", d, 10000);
        // }
        // clear
        {
            var b = I32HashBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) b.add(@rem(i, 10000));
            const start = nanos();
            b.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
    }

    // ================================================================
    //  5. I32ArrayStack
    // ================================================================
    try stdout.print("\n--- I32ArrayStack ---\n", .{});
    {
        // push+pop (N)
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            i = 0;
            while (i < N) : (i += 1) _ = s.pop();
            const d: u64 = @intCast(nanos() - start);
            printBench("push+pop (N each)", d, N * 2);
        }
        // peek -- sustained
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.peek();
                ops += 1;
            }
            printSustained("peek", ops);
        }
        // peekAt -- sustained
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.peekAt(@rem(ops, N));
                ops += 1;
            }
            printSustained("peekAt", ops);
        }
        // size
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.size();
                ops += 1;
            }
            printSustained("size", ops);
        }
        // contains
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < 10000) : (i += 1) s.push(i);
            const start = nanos();
            i = 0;
            while (i < 10000) : (i += 1) _ = s.contains(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("contains (10K)", d, 10000);
        }
        // forEach
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            const start = nanos();
            s.forEach(valForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, N);
        }
        // select
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            const start = nanos();
            var sel = s.select(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, N);
        }
        // detect
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            const start = nanos();
            _ = s.detect(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("detect", d, 1);
        }
        // anySatisfy
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            const start = nanos();
            _ = s.anySatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("anySatisfy", d, 1);
        }
        // allSatisfy
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            const start = nanos();
            _ = s.allSatisfy(valAlwaysTrue);
            const d: u64 = @intCast(nanos() - start);
            printBench("allSatisfy", d, N);
        }
        // noneSatisfy
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            const start = nanos();
            _ = s.noneSatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("noneSatisfy", d, N);
        }
        // toSlice (returns view)
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            const start = nanos();
            _ = s.toSlice();
            const d: u64 = @intCast(nanos() - start);
            printBench("toSlice", d, 1);
        }
        // clear
        {
            var s = I32ArrayStack.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < N) : (i += 1) s.push(i);
            const start = nanos();
            s.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
    }

    // ================================================================
    //  6. I32I32TreeMap
    // ================================================================
    try stdout.print("\n--- I32I32TreeMap ---\n", .{});
    {
        const TM_N: usize = 100_000; // TreeMap is O(n) insert, use smaller N
        // put (sorted)
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i *% 10);
            const d: u64 = @intCast(nanos() - start);
            printBench("put (sorted 100K)", d, TM_N);
        }
        // put (random)
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            const start = nanos();
            var i: usize = 0;
            while (i < TM_N) : (i += 1) {
                const k = scramble(i);
                _ = m.put(k, @as(i32, @intCast(i)));
            }
            const d: u64 = @intCast(nanos() - start);
            printBench("put (random 100K)", d, TM_N);
        }
        // get (hit) -- sustained
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.get(@as(i32, @intCast(@rem(ops, TM_N))));
                ops += 1;
            }
            printSustained("get (hit)", ops);
        }
        // get (miss) -- sustained
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.get(@as(i32, @intCast(TM_N + @rem(ops, TM_N))));
                ops += 1;
            }
            printSustained("get (miss)", ops);
        }
        // containsKey -- sustained
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.containsKey(@as(i32, @intCast(@rem(ops, TM_N))));
                ops += 1;
            }
            printSustained("containsKey", ops);
        }
        // forEach
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            m.forEach(hmForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, TM_N);
        }
        // select
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            var sel = m.select(hmSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, TM_N);
        }
        // reject
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            var rej = m.reject(hmSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            rej.deinit();
            printBench("reject (50%)", d, TM_N);
        }
        // detect
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.detect(hmDetect);
            const d: u64 = @intCast(nanos() - start);
            printBench("detect", d, 1);
        }
        // anySatisfy
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.anySatisfy(hmDetect);
            const d: u64 = @intCast(nanos() - start);
            printBench("anySatisfy", d, 1);
        }
        // allSatisfy
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.allSatisfy(hmAlwaysTrue);
            const d: u64 = @intCast(nanos() - start);
            printBench("allSatisfy", d, TM_N);
        }
        // noneSatisfy
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.noneSatisfy(hmDetect);
            const d: u64 = @intCast(nanos() - start);
            printBench("noneSatisfy", d, TM_N);
        }
        // min
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.min();
                ops += 1;
            }
            printSustained("min", ops);
        }
        // max
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.max();
                ops += 1;
            }
            printSustained("max", ops);
        }
        // floor -- sustained
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.floor(@as(i32, @intCast(@rem(ops, TM_N))));
                ops += 1;
            }
            printSustained("floor", ops);
        }
        // ceiling -- sustained
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = m.ceiling(@as(i32, @intCast(@rem(ops, TM_N))));
                ops += 1;
            }
            printSustained("ceiling", ops);
        }
        // remove (all)
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            // Remove from highest to lowest to avoid O(n) shifts
            i = @as(i32, @intCast(TM_N));
            while (i > 0) {
                i -= 1;
                _ = m.remove(i);
            }
            const d: u64 = @intCast(nanos() - start);
            printBench("remove (all, reverse)", d, TM_N);
        }
        // keysSlice / valuesSlice (views)
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            _ = m.keysSlice();
            _ = m.valuesSlice();
            const d: u64 = @intCast(nanos() - start);
            printBench("keysSlice + valuesSlice", d, 1);
        }
        // clear
        {
            var m = I32I32TreeMap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < TM_N) : (i += 1) _ = m.put(i, i);
            const start = nanos();
            m.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
    }

    // ================================================================
    //  7. I32TreeSet
    // ================================================================
    try stdout.print("\n--- I32TreeSet ---\n", .{});
    {
        const TS_N: usize = 100_000;
        // add (sorted)
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("add (sorted 100K)", d, TS_N);
        }
        // add (random)
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            const start = nanos();
            var i: usize = 0;
            while (i < TS_N) : (i += 1) _ = s.add(scramble(i));
            const d: u64 = @intCast(nanos() - start);
            printBench("add (random 100K)", d, TS_N);
        }
        // contains (hit) -- sustained
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.contains(@as(i32, @intCast(@rem(ops, TS_N))));
                ops += 1;
            }
            printSustained("contains (hit)", ops);
        }
        // contains (miss) -- sustained
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.contains(@as(i32, @intCast(TS_N + @rem(ops, TS_N))));
                ops += 1;
            }
            printSustained("contains (miss)", ops);
        }
        // forEach
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            s.forEach(valForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, TS_N);
        }
        // select
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            var sel = s.select(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, TS_N);
        }
        // reject
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            var rej = s.reject(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            rej.deinit();
            printBench("reject (50%)", d, TS_N);
        }
        // detect
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.detect(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("detect", d, 1);
        }
        // anySatisfy
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.anySatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("anySatisfy", d, 1);
        }
        // allSatisfy
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.allSatisfy(valAlwaysTrue);
            const d: u64 = @intCast(nanos() - start);
            printBench("allSatisfy", d, TS_N);
        }
        // noneSatisfy
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.noneSatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("noneSatisfy", d, TS_N);
        }
        // min -- sustained
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.min();
                ops += 1;
            }
            printSustained("min", ops);
        }
        // max -- sustained
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.max();
                ops += 1;
            }
            printSustained("max", ops);
        }
        // floor -- sustained
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.floor(@as(i32, @intCast(@rem(ops, TS_N))));
                ops += 1;
            }
            printSustained("floor", ops);
        }
        // ceiling -- sustained
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = s.ceiling(@as(i32, @intCast(@rem(ops, TS_N))));
                ops += 1;
            }
            printSustained("ceiling", ops);
        }
        // setUnion
        {
            var a = I32TreeSet.init(alloc);
            defer a.deinit();
            var b = I32TreeSet.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = a.add(i);
            i = @as(i32, @intCast(TS_N / 2));
            while (i < TS_N + @as(i32, @intCast(TS_N / 2))) : (i += 1) _ = b.add(i);
            const start = nanos();
            var u = a.setUnion(&b);
            const d: u64 = @intCast(nanos() - start);
            u.deinit();
            printBench("setUnion", d, TS_N);
        }
        // intersect
        {
            var a = I32TreeSet.init(alloc);
            defer a.deinit();
            var b = I32TreeSet.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = a.add(i);
            i = @as(i32, @intCast(TS_N / 2));
            while (i < TS_N + @as(i32, @intCast(TS_N / 2))) : (i += 1) _ = b.add(i);
            const start = nanos();
            var inter = a.intersect(&b);
            const d: u64 = @intCast(nanos() - start);
            inter.deinit();
            printBench("intersect", d, TS_N);
        }
        // difference
        {
            var a = I32TreeSet.init(alloc);
            defer a.deinit();
            var b = I32TreeSet.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = a.add(i);
            i = @as(i32, @intCast(TS_N / 2));
            while (i < TS_N + @as(i32, @intCast(TS_N / 2))) : (i += 1) _ = b.add(i);
            const start = nanos();
            var diff = a.difference(&b);
            const d: u64 = @intCast(nanos() - start);
            diff.deinit();
            printBench("difference", d, TS_N);
        }
        // remove (all, reverse order)
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            i = @as(i32, @intCast(TS_N));
            while (i > 0) {
                i -= 1;
                _ = s.remove(i);
            }
            const d: u64 = @intCast(nanos() - start);
            printBench("remove (all, reverse)", d, TS_N);
        }
        // toSlice (view)
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            _ = s.toSlice();
            const d: u64 = @intCast(nanos() - start);
            printBench("toSlice", d, 1);
        }
        // clear
        {
            var s = I32TreeSet.init(alloc);
            defer s.deinit();
            var i: i32 = 0;
            while (i < TS_N) : (i += 1) _ = s.add(i);
            const start = nanos();
            s.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
    }

    // ================================================================
    //  8. I32I32ListMultimap
    // ================================================================
    try stdout.print("\n--- I32I32ListMultimap ---\n", .{});
    {
        const MM_N: usize = N;
        const MM_KEYS: usize = MM_N / 10; // ~10 values per key
        // put (N with ~10 values per key)
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const d: u64 = @intCast(nanos() - start);
            printBench("put (N, ~10 vals/key)", d, MM_N);
        }
        // get
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            i = 0;
            while (i < 1000) : (i += 1) {
                const vals = m.get(i);
                alloc.free(vals);
            }
            const d: u64 = @intCast(nanos() - start);
            printBench("get (1K keys)", d, 1000);
        }
        // getCount
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            i = 0;
            while (i < 1000) : (i += 1) _ = m.getCount(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("getCount (1K keys)", d, 1000);
        }
        // removeAll
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            i = 0;
            while (i < 1000) : (i += 1) _ = m.removeAll(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("removeAll (1K keys)", d, 1000);
        }
        // containsKey
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            i = 0;
            while (i < 10000) : (i += 1) _ = m.containsKey(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("containsKey (10K)", d, 10000);
        }
        // containsKeyValue
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            i = 0;
            while (i < 1000) : (i += 1) _ = m.containsKeyValue(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const d: u64 = @intCast(nanos() - start);
            printBench("containsKeyValue (1K)", d, 1000);
        }
        // keysCount
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            // Use smaller data for keysCount which is O(n^2)
            while (i < 10000) : (i += 1) m.put(@rem(i, 1000), i);
            const start = nanos();
            _ = m.keysCount();
            const d: u64 = @intCast(nanos() - start);
            printBench("keysCount (10K entries)", d, 1);
        }
        // size
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            _ = m.size();
            const d: u64 = @intCast(nanos() - start);
            printBench("size", d, 1);
        }
        // forEach
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            m.forEach(mmForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, MM_N);
        }
        // select (50%)
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            var sel = m.select(mmSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, MM_N);
        }
        // reject
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            var rej = m.reject(mmSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            rej.deinit();
            printBench("reject (50%)", d, MM_N);
        }
        // uniqueKeys
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            // Smaller data for uniqueKeys which is O(n*k)
            while (i < 10000) : (i += 1) m.put(@rem(i, 1000), i);
            const start = nanos();
            const ukeys = m.uniqueKeys(alloc);
            const d: u64 = @intCast(nanos() - start);
            alloc.free(ukeys);
            printBench("uniqueKeys (10K entries)", d, 1);
        }
        // valuesToSlice
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            const vs = m.valuesToSlice(alloc);
            const d: u64 = @intCast(nanos() - start);
            alloc.free(vs);
            printBench("valuesToSlice", d, MM_N);
        }
        // withKeyValue
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) _ = m.withKeyValue(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const d: u64 = @intCast(nanos() - start);
            printBench("withKeyValue", d, MM_N);
        }
        // clear
        {
            var m = I32I32ListMultimap.init(alloc);
            defer m.deinit();
            var i: i32 = 0;
            while (i < MM_N) : (i += 1) m.put(@rem(i, @as(i32, @intCast(MM_KEYS))), i);
            const start = nanos();
            m.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
    }

    // ================================================================
    //  9. I32TreeBag
    // ================================================================
    try stdout.print("\n--- I32TreeBag ---\n", .{});
    {
        const TB_N: usize = 100_000; // TreeBag insert is O(log n), but uses sorted array
        const TB_DISTINCT: usize = 10000;
        // add
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            const start = nanos();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const d: u64 = @intCast(nanos() - start);
            printBench("add (100K, ~10 occ each)", d, TB_N);
        }
        // remove
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            i = 0;
            while (i < TB_N) : (i += 1) _ = b.remove(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const d: u64 = @intCast(nanos() - start);
            printBench("remove (100K)", d, TB_N);
        }
        // removeAll
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            i = 0;
            while (i < TB_DISTINCT) : (i += 1) _ = b.removeAll(i);
            const d: u64 = @intCast(nanos() - start);
            printBench("removeAll (10K distinct)", d, TB_DISTINCT);
        }
        // occurrencesOf -- sustained
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = b.occurrencesOf(@as(i32, @intCast(@rem(ops, TB_DISTINCT))));
                ops += 1;
            }
            printSustained("occurrencesOf", ops);
        }
        // contains -- sustained
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = b.contains(@as(i32, @intCast(@rem(ops, TB_DISTINCT))));
                ops += 1;
            }
            printSustained("contains", ops);
        }
        // size / sizeDistinct
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            _ = b.totalSize();
            _ = b.sizeDistinct();
            const d: u64 = @intCast(nanos() - start);
            printBench("totalSize + sizeDistinct", d, 1);
        }
        // min -- sustained
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = b.min();
                ops += 1;
            }
            printSustained("min", ops);
        }
        // max -- sustained
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            var ops: u64 = 0;
            const deadline = nanos() + @as(i128, SECS) * 1_000_000_000;
            while (nanos() < deadline) {
                _ = b.max();
                ops += 1;
            }
            printSustained("max", ops);
        }
        // forEach
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            b.forEach(valForEachCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEach", d, TB_N);
        }
        // forEachWithOccurrences
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            b.forEachWithOccurrences(bagForEachOccCb);
            const d: u64 = @intCast(nanos() - start);
            printBench("forEachWithOccurrences", d, TB_DISTINCT);
        }
        // select (50%)
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            var sel = b.select(valSelectHalf);
            const d: u64 = @intCast(nanos() - start);
            sel.deinit();
            printBench("select (50%)", d, TB_DISTINCT);
        }
        // detect
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            _ = b.detect(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("detect", d, 1);
        }
        // anySatisfy
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            _ = b.anySatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("anySatisfy", d, 1);
        }
        // allSatisfy
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            _ = b.allSatisfy(valAlwaysTrue);
            const d: u64 = @intCast(nanos() - start);
            printBench("allSatisfy", d, TB_DISTINCT);
        }
        // noneSatisfy
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            _ = b.noneSatisfy(valDetect42);
            const d: u64 = @intCast(nanos() - start);
            printBench("noneSatisfy", d, TB_DISTINCT);
        }
        // clear
        {
            var b = I32TreeBag.init(alloc);
            defer b.deinit();
            var i: i32 = 0;
            while (i < TB_N) : (i += 1) b.add(@rem(i, @as(i32, @intCast(TB_DISTINCT))));
            const start = nanos();
            b.clear();
            const d: u64 = @intCast(nanos() - start);
            printBench("clear", d, 1);
        }
    }

    try stdout.print("\n=== Benchmark complete ===\n", .{});
}

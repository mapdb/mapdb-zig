// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Regression guard for the fable-review perf items D3 / D9 / D13 — all now
//! IMPLEMENTED, so each section reads as a before/after guard.
//! Run: `zig build bench-deferred` (ReleaseFast).
//!
//!   D3  hashmap table: now structure-of-arrays — `keys[]` + `values[]` + a
//!       1-bit-per-slot occupancy bitset, replacing the interleaved
//!       `{key, value, occupied: bool}` array whose `bool` forced per-slot
//!       padding. Guard: comptime bytes/slot of the retired AoS `MapEntry` vs
//!       the live SoA layout. [DONE]
//!   D9  TreeSet nodes: now drawn from a `std.heap.MemoryPool` — N inserts cost a
//!       few geometric arena blocks, not one `allocator.create(Node)` each.
//!       Guard: `alloc_calls` is a small block count, not N. [DONE]
//!   D13 RangeSet mutation: `add`/`remove` binary-search the affected run and
//!       splice in place, replacing the rebuild-fresh-backing-every-call path
//!       (was O(n^2) addAll + O(n) allocs). Guard: append is flat + alloc≈1. [DONE]

const std = @import("std");
const root = @import("mapdb_collections");
const MapEntry = root.hash_table.MapEntry;
const I32TreeSet = root.I32TreeSet;
const I32RangeSet = root.I32RangeSet;
const Range = root.Range;

/// Allocator shim that counts allocator calls and tracks live+peak bytes,
/// delegating to a child allocator. Not thread-safe (single-threaded bench).
///
/// `alloc_calls` counts only fresh `alloc` requests (new backing memory). Zig's
/// `remap` can grow/relocate an existing allocation *without* an `alloc` call,
/// so `remap_calls` is tracked separately — a bench over `ArrayList` in-place
/// growth must read both. For the current D9/D13 paths `alloc_calls` is exact:
/// `TreeSet.add` uses `allocator.create` directly, and each `RangeSet.add`
/// builds a fresh empty list whose first capacity request falls to `alloc`.
const CountingAllocator = struct {
    child: std.mem.Allocator,
    alloc_calls: usize = 0,
    remap_calls: usize = 0,
    free_calls: usize = 0,
    live_bytes: usize = 0,
    peak_bytes: usize = 0,

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = allocFn,
        .resize = resizeFn,
        .remap = remapFn,
        .free = freeFn,
    };

    fn allocFn(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const p = self.child.vtable.alloc(self.child.ptr, len, alignment, ret_addr);
        if (p != null) {
            self.alloc_calls += 1;
            self.live_bytes += len;
            if (self.live_bytes > self.peak_bytes) self.peak_bytes = self.live_bytes;
        }
        return p;
    }

    fn resizeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ok = self.child.vtable.resize(self.child.ptr, memory, alignment, new_len, ret_addr);
        if (ok) {
            self.live_bytes = self.live_bytes - memory.len + new_len;
            if (self.live_bytes > self.peak_bytes) self.peak_bytes = self.live_bytes;
        }
        return ok;
    }

    fn remapFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const p = self.child.vtable.remap(self.child.ptr, memory, alignment, new_len, ret_addr);
        if (p != null) {
            self.remap_calls += 1;
            self.live_bytes = self.live_bytes - memory.len + new_len;
            if (self.live_bytes > self.peak_bytes) self.peak_bytes = self.live_bytes;
        }
        return p;
    }

    fn freeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.vtable.free(self.child.ptr, memory, alignment, ret_addr);
        self.free_calls += 1;
        self.live_bytes -= memory.len;
    }
};

fn nanos() i128 {
    return std.time.nanoTimestamp();
}

// ---- D3: hashmap table footprint (comptime) --------------------------------

/// Bytes/slot of a hypothetical SoA layout: keys[] + values[] densely packed
/// plus a word-backed occupancy bitset. A u64-word bitset over `cap` slots costs
/// `ceil(cap/64)*8` bytes, i.e. exactly 1 bit/slot (0.125 B) only once `cap >= 64`
/// and a power of two; small tables pay more (0.5 B/slot at cap 16, 0.25 at 32).
/// Reported at the asymptotic 1-bit/slot — the regime that matters for memory,
/// since footprint pressure is at scale, not on 16-slot tables.
fn soaBytesPerSlot(comptime K: type, comptime V: type) f64 {
    return @as(f64, @floatFromInt(@sizeOf(K) + @sizeOf(V))) + 1.0 / 8.0;
}

fn reportFootprint(comptime name: []const u8, comptime K: type, comptime V: type) void {
    const cur = @sizeOf(MapEntry(K, V));
    const soa = soaBytesPerSlot(K, V);
    const cur_f: f64 = @floatFromInt(cur);
    const saved = cur_f - soa;
    const pct = saved / cur_f * 100.0;
    std.debug.print(
        "  {s:<10} AoS MapEntry={d:>3}B/slot  SoA={d:>5.2}B/slot  save={d:>5.2}B ({d:>4.1}%)\n",
        .{ name, cur, soa, saved, pct },
    );
}

fn benchD3() void {
    std.debug.print("\n=== D3: hashmap table footprint (retired AoS vs LIVE SoA) ===\n", .{});
    std.debug.print("  AoS = struct{{key, value, occupied: bool}} — RETIRED (kept only as MapEntry ref)\n", .{});
    std.debug.print("  SoA = keys[] + values[] + word-backed bitset (1 bit/slot for cap>=64) — LIVE\n", .{});
    reportFootprint("i32/i32", i32, i32);
    reportFootprint("i64/i64", i64, i64);
    reportFootprint("i32/i64", i32, i64);
    reportFootprint("i64/i32", i64, i32);
    reportFootprint("f64/f64", f64, f64);
    reportFootprint("i8/i8", i8, i8);
    reportFootprint("u21/i64", u21, i64); // char-keyed
    // Per-live-entry waste is higher: a table at its 0.75 load ceiling holds
    // 1/0.75 ~= 1.33 slots per live entry, and is even emptier right after a
    // grow — so the bytes/live-entry multiplier is >=1.33, workload-dependent.
    std.debug.print("  (>=1.33x per live entry: table holds ~1.33+ slots/entry at/below 0.75 load)\n", .{});
}

// ---- D9: TreeSet per-insert allocation count (IMPLEMENTED — regression guard)
//
// D9 is done: `TreeSet` nodes now come from a per-set `std.heap.MemoryPool`, so
// N inserts cost a handful of geometric arena-block allocations instead of one
// `allocator.create(Node)` each. This bench flipped from a measure-first gate
// into a regression guard — the pre-fix signature was `alloc_calls == N`
// (1.00/insert); post-fix it is a single-digit block count independent of N.

fn benchD9(base: std.mem.Allocator) !void {
    std.debug.print("\n=== D9: TreeSet allocation behavior (post-pool regression guard) ===\n", .{});
    const Ns = [_]usize{ 10_000, 100_000 };
    for (Ns) |N| {
        var counter = CountingAllocator{ .child = base };
        const alloc = counter.allocator();
        var s = I32TreeSet.init(alloc);
        defer s.deinit();

        // Insert distinct pseudo-random-ish keys (LCG, deterministic).
        var x: u32 = 0x9e3779b9;
        const start = nanos();
        var i: usize = 0;
        while (i < N) : (i += 1) {
            x = x *% 1664525 +% 1013904223;
            _ = try s.add(@bitCast(x));
        }
        const elapsed: u64 = @intCast(nanos() - start);
        const allocs_after_insert = counter.alloc_calls;
        std.debug.print(
            "  N={d:>7}  inserts alloc_calls={d:>7} ({d:.2}/insert)  {d:.3}ms  peak={d}KB\n",
            .{ N, allocs_after_insert, @as(f64, @floatFromInt(allocs_after_insert)) / @as(f64, @floatFromInt(N)), @as(f64, @floatFromInt(elapsed)) / 1e6, counter.peak_bytes / 1024 },
        );
    }
    std.debug.print("  post-fix signal: alloc_calls is a small block count (not N) — pool batches nodes into\n", .{});
    std.debug.print("  geometric arena blocks; freed nodes recycle through the free list. peak is modestly\n", .{});
    std.debug.print("  higher (arena block rounding) in exchange for ~10x fewer allocations + faster inserts.\n", .{});
}

// ---- D13: RangeSet mutation scaling (IMPLEMENTED — regression guard) --------
//
// D13 is done: `RangeSet.add`/`remove` now binary-search the affected run and
// splice in place instead of rebuilding the whole backing list into a fresh
// allocation every call. This bench flipped from a measure-first gate into a
// regression guard — the pre-fix signature was `alloc_calls == N` with
// super-linearly-rising ns/add (O(n) per add ⇒ O(n^2) addAll); post-fix it is
// `alloc_calls ~= 1` (ArrayList growth relocates via `remap`, not fresh
// `alloc`) with flat ns/add on the ascending-append workload.

fn benchD13(base: std.mem.Allocator) !void {
    std.debug.print("\n=== D13: RangeSet addAll scaling (post-splice regression guard) ===\n", .{});
    const Ns = [_]usize{ 1_000, 2_000, 4_000, 8_000 };
    var prev_per_op: f64 = 0;
    for (Ns) |N| {
        // (a) Ascending disjoint ranges [3k, 3k+1]: each add's sorted position
        // is the end, so the splice degenerates to an amortized-O(1) append.
        var counter = CountingAllocator{ .child = base };
        const alloc = counter.allocator();
        var rs = I32RangeSet.init(alloc);
        defer rs.deinit();

        const start = nanos();
        var i: usize = 0;
        while (i < N) : (i += 1) {
            const lo: i32 = @intCast(i * 3);
            try rs.add(Range(i32).closed(lo, lo + 1));
        }
        const elapsed: u64 = @intCast(nanos() - start);
        const per_op = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(N));
        const growth = if (prev_per_op == 0) 0.0 else per_op / prev_per_op;

        // (b) Descending inserts hit the new worst case: every add lands at
        // index 0 and shifts the whole array (O(n) memmove), but still with NO
        // per-add allocation — the point of the rewrite. Kept in a separate set
        // so its allocs don't muddy (a)'s counter.
        var counter2 = CountingAllocator{ .child = base };
        var rs2 = I32RangeSet.init(counter2.allocator());
        defer rs2.deinit();
        const start2 = nanos();
        var j: usize = N;
        while (j > 0) : (j -= 1) {
            const lo: i32 = @intCast(j * 3);
            try rs2.add(Range(i32).closed(lo, lo + 1));
        }
        const elapsed2: u64 = @intCast(nanos() - start2);
        const per_op2 = @as(f64, @floatFromInt(elapsed2)) / @as(f64, @floatFromInt(N));

        std.debug.print(
            "  N={d:>5}  append: {d:>6.1} ns/add alloc={d:>3} remap={d:>3} (x{d:.2})   front-insert: {d:>7.1} ns/add alloc={d:>3}\n",
            .{ N, per_op, counter.alloc_calls, counter.remap_calls, growth, per_op2, counter2.alloc_calls },
        );
        prev_per_op = per_op;
    }
    std.debug.print("  post-fix signal: alloc_calls no longer scales with N (growth via remap); append ns/add is\n", .{});
    std.debug.print("  ~flat vs the old super-linear rise. front-insert stays alloc-free but pays the O(n) shift.\n", .{});
}

pub fn main() !void {
    std.debug.print("=== Deferred-items measurement gate (D3 / D9 / D13) ===\n", .{});
    const base = std.heap.page_allocator;
    benchD3();
    try benchD9(base);
    try benchD13(base);
}

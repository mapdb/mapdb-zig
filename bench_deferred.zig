// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Measurement gate for the three "measure-first" deferred fable-review items.
//! Run: `zig build bench-deferred` (ReleaseFast).
//!
//! Each item claims a hot-path cost; this probe measures the *current* state so
//! the rewrite decision is data-driven rather than speculative:
//!
//!   D3  hashmap table: `MapEntry{key, value, occupied: bool}` interleaves the
//!       occupancy flag, forcing per-slot padding. Measured at comptime as
//!       current bytes/slot vs a structure-of-arrays (SoA) layout with a
//!       1-bit-per-slot occupancy bitset.
//!   D9  TreeSet reservation: `ensureUnusedCapacity` only *probes* (alloc+free);
//!       real inserts each do one `allocator.create(Node)`. Measured as
//!       allocation count for N inserts (a node pool would batch these).
//!   D13 RangeSet mutation: `add` rebuilds the whole ranges list + allocates a
//!       fresh backing array *every call*, so `addAll` is O(n^2) time + O(n)
//!       allocations. Measured as time/alloc scaling across N.

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
    std.debug.print("\n=== D3: hashmap table footprint (current AoS vs proposed SoA) ===\n", .{});
    std.debug.print("  AoS = struct{{key, value, occupied: bool}} (occupancy interleaved, padded)\n", .{});
    std.debug.print("  SoA = keys[] + values[] + word-backed bitset (1 bit/slot for cap>=64)\n", .{});
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

// ---- D9: TreeSet per-insert allocation count -------------------------------

fn benchD9(base: std.mem.Allocator) !void {
    std.debug.print("\n=== D9: TreeSet allocation behavior (N inserts) ===\n", .{});
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
    std.debug.print("  (~1 alloc/insert today → a node pool would batch these into O(log N) growth allocs)\n", .{});
}

// ---- D13: RangeSet mutation scaling ----------------------------------------

fn benchD13(base: std.mem.Allocator) !void {
    std.debug.print("\n=== D13: RangeSet addAll of N disjoint ranges (expose O(n^2)) ===\n", .{});
    const Ns = [_]usize{ 1_000, 2_000, 4_000, 8_000 };
    var prev_per_op: f64 = 0;
    for (Ns) |N| {
        var counter = CountingAllocator{ .child = base };
        const alloc = counter.allocator();
        var rs = I32RangeSet.init(alloc);
        defer rs.deinit();

        // Disjoint closed ranges [3k, 3k+1] so none coalesce: worst case for a
        // flat-array RangeSet — each add scans + rebuilds all prior ranges.
        const start = nanos();
        var i: usize = 0;
        while (i < N) : (i += 1) {
            const lo: i32 = @intCast(i * 3);
            try rs.add(Range(i32).closed(lo, lo + 1));
        }
        const elapsed: u64 = @intCast(nanos() - start);
        const per_op = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(N));
        const growth = if (prev_per_op == 0) 0.0 else per_op / prev_per_op;
        std.debug.print(
            "  N={d:>5}  {d:>8.3}ms total  {d:>7.1} ns/add  alloc_calls={d:>6}  (ns/add x{d:.2} vs prev N)\n",
            .{ N, @as(f64, @floatFromInt(elapsed)) / 1e6, per_op, counter.alloc_calls, growth },
        );
        prev_per_op = per_op;
    }
    std.debug.print("  primary signal: alloc_calls == N ⇒ one fresh backing allocation per add (rebuild-in-full).\n", .{});
    std.debug.print("  ns/add rises super-linearly with N (O(n)/add ⇒ O(n^2) addAll); the exact x-ratio is\n", .{});
    std.debug.print("  page_allocator/cache-noisy, so read it as \"clearly not constant\", not a precise 2.0.\n", .{});
}

pub fn main() !void {
    std.debug.print("=== Deferred-items measurement gate (D3 / D9 / D13) ===\n", .{});
    const base = std.heap.page_allocator;
    benchD3();
    try benchD9(base);
    try benchD13(base);
}

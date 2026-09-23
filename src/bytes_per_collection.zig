// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Requested-byte measurement for five collections. Not a library API.
//!
//! `BytesPerCollectionAllocator` lives only in this executable. It is not
//! imported by `root.zig`. Counts are the sizes the caller asked for.
//! `std.heap.GeneralPurposeAllocator` (Zig 0.15: an alias of `DebugAllocator`)
//! does not expose the size class it reserved through `Allocator`, and
//! `total_requested_bytes` is documented as requested bytes, not backing
//! bytes. Size-class rounding is therefore not measured.
//!
//! `safety = true` is required for that GPA counter to stay coherent:
//! with safety off, `resizeSmall` returns success for a same-class resize
//! without adjusting `total_requested_bytes` (Zig 0.15.2). The counter is
//! enabled with `enable_memory_limit = true`, which is the only config in
//! which the field exists (otherwise its type is `void`).
//!
//! `String → Vec<u8>` from `03-improvements.md` §0 is deferred. This file
//! does not build that corpus.
//!
//! Stdout is one tab-separated row per id. Stderr is notes, the GPA delta,
//! and checksums.
//!
//! ```text
//! zig build bytes-per-collection
//! zig build bytes-per-collection -- --smoke
//! zig build bytes-per-collection -- --full
//! ```

const std = @import("std");
const mapdb = @import("mapdb_collections");

const HashMap = mapdb.hashmap.I64I64HashMap;
const TreeMap = mapdb.treemap.I64I64TreeMap;
const SortedMap = mapdb.immutable_sorted.ImmutableSortedMap(i64, i64);
const ListMultimap = mapdb.multimap.I64I32ListMultimap;
const Roaring = mapdb.RoaringU32;

const LOOKUPS: usize = 10_000;
const WARMUP: usize = 64;
const VALUES_PER_KEY: usize = 8;
const ROARING_STRIDE: u32 = 100;
/// Non-zero. Same constant as the Rust harness.
const XORSHIFT_SEED: u64 = 0xA11C_E5EE_D000_0001;

const Gpa = std.heap.GeneralPurposeAllocator(.{
    .enable_memory_limit = true,
    .safety = true,
    .thread_safe = false,
});

const BytesPerCollectionAllocator = struct {
    parent: std.mem.Allocator,
    enabled: bool = false,
    alloc_bytes: u64 = 0,
    alloc_count: u64 = 0,
    free_bytes: u64 = 0,

    fn allocator(self: *BytesPerCollectionAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn reset(self: *BytesPerCollectionAllocator) void {
        self.alloc_bytes = 0;
        self.alloc_count = 0;
        self.free_bytes = 0;
    }

    fn live(self: *const BytesPerCollectionAllocator) i64 {
        return @as(i64, @intCast(self.alloc_bytes)) - @as(i64, @intCast(self.free_bytes));
    }

    fn noteAlloc(self: *BytesPerCollectionAllocator, len: usize) void {
        if (!self.enabled) return;
        self.alloc_bytes += len;
        self.alloc_count += 1;
    }

    fn noteFree(self: *BytesPerCollectionAllocator, len: usize) void {
        if (!self.enabled) return;
        self.free_bytes += len;
    }

    /// Successful realloc/resize/remap: the old requested size is gone and
    /// the new requested size is live. Same accounting as the Rust wrapper.
    fn noteRealloc(self: *BytesPerCollectionAllocator, old_len: usize, new_len: usize) void {
        if (!self.enabled) return;
        self.free_bytes += old_len;
        self.alloc_bytes += new_len;
        self.alloc_count += 1;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *BytesPerCollectionAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawAlloc(len, alignment, ret_addr);
        if (result != null) self.noteAlloc(len);
        return result;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *BytesPerCollectionAllocator = @ptrCast(@alignCast(ctx));
        const ok = self.parent.rawResize(memory, alignment, new_len, ret_addr);
        if (ok) self.noteRealloc(memory.len, new_len);
        return ok;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *BytesPerCollectionAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawRemap(memory, alignment, new_len, ret_addr);
        if (result != null) self.noteRealloc(memory.len, new_len);
        return result;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *BytesPerCollectionAllocator = @ptrCast(@alignCast(ctx));
        self.noteFree(memory.len);
        self.parent.rawFree(memory, alignment, ret_addr);
    }
};

fn xorshift64(state: *u64) u64 {
    var x = state.*;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    state.* = x;
    return x;
}

/// `count` draws in `0..n` from xorshift64 restarted at `XORSHIFT_SEED`.
/// Restarting (rather than continuing the Fisher–Yates stream) keeps the
/// draw independent of `n` and identical in the Rust harness.
fn draw(alloc: std.mem.Allocator, n: usize, count: usize) ![]usize {
    const out = try alloc.alloc(usize, count);
    var state = XORSHIFT_SEED;
    for (out) |*slot| {
        const r = xorshift64(&state);
        slot.* = @intCast(r % @as(u64, n));
    }
    return out;
}

fn permutation(alloc: std.mem.Allocator, n: usize) ![]i64 {
    const keys = try alloc.alloc(i64, n);
    for (keys, 0..) |*k, i| k.* = @intCast(i);
    var state = XORSHIFT_SEED;
    var i: usize = n;
    while (i > 1) {
        i -= 1;
        const r = xorshift64(&state);
        const j: usize = @intCast(r % @as(u64, i + 1));
        const tmp = keys[i];
        keys[i] = keys[j];
        keys[j] = tmp;
    }
    return keys;
}

const Corpus = struct {
    map_n: usize,
    mm_keys: usize,
    hash_keys: []i64,
    sorted_keys: []i64,
    sorted_vals: []i64,
    /// `LOOKUPS` indices in `0..map_n` for the tree, immutable, and roaring rows.
    lookup_map: []usize,
    /// `LOOKUPS` indices in `0..mm_keys` for the multimap.
    lookup_mm: []usize,
};

fn expectLen(id: []const u8, got: usize, want: usize) !void {
    if (got != want) {
        std.debug.print("{s}: len {d} != {d}\n", .{ id, got, want });
        return error.LengthMismatch;
    }
}

fn nsPer(elapsed_ns: u64) u64 {
    return elapsed_ns / LOOKUPS;
}

fn printRow(out: *std.Io.Writer, id: []const u8, n: usize, bytes: u64, count: u64, live: i64, lookup_ns: u64) !void {
    try out.print("{s}\t{d}\t{d}\t{d}\t{d}\t{d}\n", .{ id, n, bytes, count, live, lookup_ns });
    try out.flush();
}

fn gpaLive(gpa: *Gpa, before: usize) usize {
    return gpa.total_requested_bytes - before;
}

fn runOhm(c: *const Corpus, counter: *BytesPerCollectionAllocator, gpa: *Gpa, out: *std.Io.Writer) !void {
    const a = counter.allocator();
    const warm_n = @min(WARMUP, c.map_n);
    counter.enabled = true;
    {
        var warm = HashMap.init(a);
        defer warm.deinit();
        for (c.hash_keys[0..warm_n]) |k| _ = try warm.put(k, k);
    }
    counter.reset();
    const before = gpa.total_requested_bytes;
    var map = HashMap.init(a);
    defer map.deinit();
    for (c.hash_keys) |k| _ = try map.put(k, k);
    try expectLen("ohm-i64", map.len(), c.map_n);
    const snap_bytes = counter.alloc_bytes;
    const snap_count = counter.alloc_count;
    const snap_live = counter.live();
    const gpa_delta = gpaLive(gpa, before);
    counter.enabled = false;
    var timer = try std.time.Timer.start();
    var sum: u64 = 0;
    for (0..LOOKUPS) |i| {
        const k = c.hash_keys[i % c.map_n];
        sum +%= @as(u64, @bitCast(map.get(k) orelse 0));
    }
    std.mem.doNotOptimizeAway(sum);
    const lookup_ns = nsPer(timer.read());
    std.debug.print("checksum ohm-i64 {d}\n", .{sum});
    std.debug.print("gpa_live_requested ohm-i64 {d}\n", .{gpa_delta});
    try printRow(out, "ohm-i64", c.map_n, snap_bytes, snap_count, snap_live, lookup_ns);
}

fn runTm(c: *const Corpus, counter: *BytesPerCollectionAllocator, gpa: *Gpa, out: *std.Io.Writer) !void {
    const a = counter.allocator();
    const warm_n = @min(WARMUP, c.map_n);
    counter.enabled = true;
    {
        var warm = TreeMap.init(a);
        defer warm.deinit();
        for (0..warm_n) |i| _ = try warm.put(@intCast(i), @intCast(i));
    }
    counter.reset();
    const before = gpa.total_requested_bytes;
    var map = TreeMap.init(a);
    defer map.deinit();
    for (0..c.map_n) |i| _ = try map.put(@intCast(i), @intCast(i));
    try expectLen("tm-i64", map.len(), c.map_n);
    const snap_bytes = counter.alloc_bytes;
    const snap_count = counter.alloc_count;
    const snap_live = counter.live();
    const gpa_delta = gpaLive(gpa, before);
    counter.enabled = false;
    var timer = try std.time.Timer.start();
    var sum: u64 = 0;
    for (c.lookup_map) |idx| {
        const k: i64 = @intCast(idx);
        sum +%= @as(u64, @bitCast(map.get(k) orelse 0));
    }
    std.mem.doNotOptimizeAway(sum);
    const lookup_ns = nsPer(timer.read());
    std.debug.print("checksum tm-i64 {d}\n", .{sum});
    std.debug.print("gpa_live_requested tm-i64 {d}\n", .{gpa_delta});
    try printRow(out, "tm-i64", c.map_n, snap_bytes, snap_count, snap_live, lookup_ns);
}

fn runIsm(c: *const Corpus, counter: *BytesPerCollectionAllocator, gpa: *Gpa, out: *std.Io.Writer) !void {
    const a = counter.allocator();
    const warm_n = @min(WARMUP, c.map_n);
    counter.enabled = true;
    {
        var warm = try SortedMap.fromSorted(a, c.sorted_keys[0..warm_n], c.sorted_vals[0..warm_n]);
        defer warm.deinit();
    }
    counter.reset();
    const before = gpa.total_requested_bytes;
    var map = try SortedMap.fromSorted(a, c.sorted_keys, c.sorted_vals);
    defer map.deinit();
    try expectLen("ism", map.len(), c.map_n);
    const snap_bytes = counter.alloc_bytes;
    const snap_count = counter.alloc_count;
    const snap_live = counter.live();
    const gpa_delta = gpaLive(gpa, before);
    counter.enabled = false;
    var timer = try std.time.Timer.start();
    var sum: u64 = 0;
    for (c.lookup_map) |idx| {
        const k: i64 = @intCast(idx);
        sum +%= @as(u64, @bitCast(map.get(k) orelse 0));
    }
    std.mem.doNotOptimizeAway(sum);
    const lookup_ns = nsPer(timer.read());
    std.debug.print("checksum ism {d}\n", .{sum});
    std.debug.print("gpa_live_requested ism {d}\n", .{gpa_delta});
    try printRow(out, "ism", c.map_n, snap_bytes, snap_count, snap_live, lookup_ns);
}

fn runMm(c: *const Corpus, counter: *BytesPerCollectionAllocator, gpa: *Gpa, out: *std.Io.Writer) !void {
    const a = counter.allocator();
    const warm_keys = @min(WARMUP, c.mm_keys);
    counter.enabled = true;
    {
        var warm = ListMultimap.init(a);
        defer warm.deinit();
        for (0..warm_keys) |ki| {
            const k: i64 = @intCast(ki);
            for (0..VALUES_PER_KEY) |vi| try warm.put(k, @intCast(vi));
        }
    }
    counter.reset();
    const before = gpa.total_requested_bytes;
    var map = ListMultimap.init(a);
    defer map.deinit();
    for (0..c.mm_keys) |ki| {
        const k: i64 = @intCast(ki);
        for (0..VALUES_PER_KEY) |vi| try map.put(k, @intCast(vi));
    }
    try expectLen("mm", map.len(), c.mm_keys * VALUES_PER_KEY);
    const snap_bytes = counter.alloc_bytes;
    const snap_count = counter.alloc_count;
    const snap_live = counter.live();
    const gpa_delta = gpaLive(gpa, before);
    counter.enabled = false;
    var timer = try std.time.Timer.start();
    var sum: u64 = 0;
    for (c.lookup_mm) |idx| {
        const k: i64 = @intCast(idx);
        sum += map.get(k).len;
    }
    std.mem.doNotOptimizeAway(sum);
    const lookup_ns = nsPer(timer.read());
    std.debug.print("checksum mm {d}\n", .{sum});
    std.debug.print("gpa_live_requested mm {d}\n", .{gpa_delta});
    try printRow(out, "mm", c.mm_keys, snap_bytes, snap_count, snap_live, lookup_ns);
}

fn runRoar(c: *const Corpus, counter: *BytesPerCollectionAllocator, gpa: *Gpa, out: *std.Io.Writer) !void {
    const a = counter.allocator();
    const warm_n = @min(WARMUP, c.map_n);
    counter.enabled = true;
    {
        var warm = Roaring.init(a);
        defer warm.deinit();
        for (0..warm_n) |i| _ = try warm.add(@as(u32, @intCast(i)) * ROARING_STRIDE);
    }
    counter.reset();
    const before = gpa.total_requested_bytes;
    var set = Roaring.init(a);
    defer set.deinit();
    for (0..c.map_n) |i| _ = try set.add(@as(u32, @intCast(i)) * ROARING_STRIDE);
    try expectLen("roar", @intCast(set.cardinality()), c.map_n);
    const snap_bytes = counter.alloc_bytes;
    const snap_count = counter.alloc_count;
    const snap_live = counter.live();
    const gpa_delta = gpaLive(gpa, before);
    counter.enabled = false;
    var timer = try std.time.Timer.start();
    var sum: u64 = 0;
    for (c.lookup_map) |idx| {
        const v: u32 = @as(u32, @intCast(idx)) * ROARING_STRIDE;
        if (set.contains(v)) sum += 1;
    }
    std.mem.doNotOptimizeAway(sum);
    const lookup_ns = nsPer(timer.read());
    std.debug.print("checksum roar {d}\n", .{sum});
    std.debug.print("gpa_live_requested roar {d}\n", .{gpa_delta});
    try printRow(out, "roar", c.map_n, snap_bytes, snap_count, snap_live, lookup_ns);
}

pub fn main() !void {
    var gpa: Gpa = .init;
    defer {
        if (gpa.deinit() == .leak) {
            std.debug.print("bytes_per_collection: GPA leak\n", .{});
            std.process.exit(1);
        }
    }
    var counter = BytesPerCollectionAllocator{ .parent = gpa.allocator() };
    const a = counter.allocator();

    const args = try std.process.argsAlloc(a);
    defer std.process.argsFree(a, args);
    if (args.len > 2) {
        std.debug.print("usage: bytes-per-collection [--smoke|--full]\n", .{});
        std.process.exit(2);
    }
    const flag: []const u8 = if (args.len == 2) args[1] else "";
    const mode: []const u8, const map_n: usize, const mm_keys: usize = if (flag.len == 0)
        .{ "default", 100_000, 10_000 }
    else if (std.mem.eql(u8, flag, "--smoke"))
        .{ "smoke", 1_000, 1_000 }
    else if (std.mem.eql(u8, flag, "--full"))
        .{ "full", 1_000_000, 100_000 }
    else {
        std.debug.print("unknown argument: {s}\nusage: bytes-per-collection [--smoke|--full]\n", .{flag});
        std.process.exit(2);
    };

    std.debug.print(
        "mode {s} map_n {d} mm_keys {d} values_per_key {d} lookups {d}\n",
        .{ mode, map_n, mm_keys, VALUES_PER_KEY, LOOKUPS },
    );
    std.debug.print(
        "bytes are requested sizes. GPA total_requested_bytes is also requested, not size-class rounded. size_class_rounding=not_measured\n",
        .{},
    );

    const hash_keys = try permutation(a, map_n);
    defer a.free(hash_keys);
    const sorted_keys = try a.alloc(i64, map_n);
    defer a.free(sorted_keys);
    const sorted_vals = try a.alloc(i64, map_n);
    defer a.free(sorted_vals);
    for (sorted_keys, sorted_vals, 0..) |*k, *v, i| {
        k.* = @intCast(i);
        v.* = @intCast(i);
    }
    const lookup_map = try draw(a, map_n, LOOKUPS);
    defer a.free(lookup_map);
    const lookup_mm = try draw(a, mm_keys, LOOKUPS);
    defer a.free(lookup_mm);
    const c = Corpus{
        .map_n = map_n,
        .mm_keys = mm_keys,
        .hash_keys = hash_keys,
        .sorted_keys = sorted_keys,
        .sorted_vals = sorted_vals,
        .lookup_map = lookup_map,
        .lookup_mm = lookup_mm,
    };

    var out_buf: [256]u8 = undefined;
    var stdout = std.fs.File.stdout().writerStreaming(&out_buf);
    const out = &stdout.interface;
    try out.print("id\tn\talloc_bytes\talloc_count\tlive_bytes_if_known\tlookup_ns\n", .{});
    try out.flush();

    try runOhm(&c, &counter, &gpa, out);
    try runTm(&c, &counter, &gpa, out);
    try runIsm(&c, &counter, &gpa, out);
    try runMm(&c, &counter, &gpa, out);
    try runRoar(&c, &counter, &gpa, out);
}

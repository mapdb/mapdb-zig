// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Fixed-chunk batch iteration — the Zig analogue of Eclipse Collections'
//! `BatchIterable`.
//!
//! Unlike a `Spliterator` (see `spliterator.zig`), which divides recursively,
//! a batch iterable is partitioned **once** into `section_count` contiguous
//! sections of roughly equal length. Section *i* is then processed by
//! `batchForEach`. **No work is stolen or rebalanced**: each section is
//! handled start-to-finish by whoever owns it.
//!
//! The sectioning helpers (`sectionBounds`, `getBatchCount`, `batchForEach`)
//! are pure `std` and spawn no threads. The parallel *executors* at the bottom
//! of this file spawn one `std.Thread` per non-empty section (no work
//! stealing). Below a per-call minimum-fork-size threshold every operation
//! runs sequentially on the calling thread.
//!
//! This mirrors the Rust `batch.rs` semantics: the first `n % count` sections
//! get one extra element so bounds tile `0..n` with no gaps or overlap.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Minimum element count before batch parallelism engages. Below this, the
/// thread-spawn overhead isn't worth it and operations run sequentially.
/// Mirrors the Rust/Go ports' `DEFAULT_MIN_FORK_SIZE`.
pub const DEFAULT_MIN_FORK_SIZE: usize = 10_000;

/// The number of batches of at most `batch_size` elements needed to cover
/// `n` elements, i.e. `ceil(n / batch_size)`, but never less than 1.
/// Matches Eclipse Collections' `getBatchCount`.
pub fn getBatchCount(n: usize, batch_size: usize) usize {
    if (batch_size == 0 or n == 0) return 1;
    return std.math.divCeil(usize, n, batch_size) catch unreachable;
}

/// Returns the `[lo, hi)` element bounds of section `index` when `n` elements
/// are divided into `count` contiguous sections as evenly as possible.
///
/// The first `n % count` sections receive one extra element, so bounds tile
/// `0..n` without gaps or overlap. `count == 0` is clamped to one section.
/// Returns an empty range at `n` when `index >= count` or `index` lands past
/// the data.
pub fn sectionBounds(n: usize, index: usize, count_in: usize) struct { lo: usize, hi: usize } {
    const sections = @max(count_in, 1);
    if (index >= sections) return .{ .lo = n, .hi = n };
    const base = n / sections;
    const remainder = n % sections;
    const lo = index * base + @min(index, remainder);
    const hi = lo + base + @as(usize, if (index < remainder) 1 else 0);
    return .{ .lo = lo, .hi = hi };
}

/// Applies `action` to every element of the `section_index`-th section out of
/// `section_count` equal-sized contiguous sections of `data`, in order. A
/// section index past the populated sections yields nothing.
///
/// `action` is invoked as `callElem(action, *const T)` — see `callElem`.
pub fn batchForEach(comptime T: type, data: []const T, action: anytype, section_index: usize, section_count: usize) void {
    const b = sectionBounds(data.len, section_index, section_count);
    for (data[b.lo..b.hi]) |*v| {
        callElem(action, v);
    }
}

/// Number of non-empty sections when `n` elements are split into `count`.
fn nonEmptySectionCount(n: usize, count_in: usize) usize {
    const sections = @max(count_in, 1);
    return @min(sections, n);
}

/// The default number of sections (worker threads): `(NCPU + 1) * 2`, capped
/// at 200 — the formula Eclipse Collections' `ParallelIterate` uses.
pub fn defaultTaskCount() usize {
    const ncpu = std.Thread.getCpuCount() catch 1;
    return @min((ncpu + 1) * 2, 200);
}

fn parallelize(n: usize, min_fork_size: usize, task_count: usize) bool {
    return n >= min_fork_size and task_count > 1;
}

/// Invokes `action` with a `*const T`. `action` may be a plain function
/// pointer `fn (*const T) void`, or any value (typically a struct pointer)
/// exposing `fn call(self, *const T) void` so it can carry state. The
/// callable must be safe to invoke concurrently when used by the parallel
/// executors below (e.g. atomics for shared accumulators).
fn callElem(action: anytype, arg: anytype) void {
    const A = @TypeOf(action);
    const info = @typeInfo(A);
    if (info == .pointer and @typeInfo(info.pointer.child) == .@"fn") {
        action(arg);
    } else if (info == .@"fn") {
        action(arg);
    } else {
        action.call(arg);
    }
}

/// Applies `action` to every element of `data`, splitting it into fixed
/// sections run on `std.Thread`s (no work stealing). Order across sections is
/// unspecified; within a section it is ascending. Uses the default fork
/// threshold and task count.
///
/// `action` must be safe to call concurrently from multiple threads.
pub fn forEach(comptime T: type, data: []const T, action: anytype) void {
    forEachWith(T, data, action, DEFAULT_MIN_FORK_SIZE, defaultTaskCount());
}

/// `forEach` with explicit `min_fork_size` and `task_count`.
pub fn forEachWith(comptime T: type, data: []const T, action: anytype, min_fork_size: usize, task_count: usize) void {
    if (data.len == 0) return;
    if (!parallelize(data.len, min_fork_size, task_count)) {
        batchForEach(T, data, action, 0, 1);
        return;
    }

    const Worker = struct {
        fn run(chunk: []const T, act: @TypeOf(action)) void {
            for (chunk) |*v| callElem(act, v);
        }
    };

    const sections = nonEmptySectionCount(data.len, task_count);
    // One thread per section; run the final section inline on this thread.
    var threads_buf: [200]std.Thread = undefined;
    var spawned: usize = 0;
    var i: usize = 0;
    while (i < sections) : (i += 1) {
        const b = sectionBounds(data.len, i, sections);
        const chunk = data[b.lo..b.hi];
        if (i + 1 == sections) {
            // Run the last chunk on the calling thread to save a spawn.
            Worker.run(chunk, action);
            break;
        }
        if (std.Thread.spawn(.{}, Worker.run, .{ chunk, action })) |t| {
            threads_buf[spawned] = t;
            spawned += 1;
        } else |_| {
            // Spawn failed — process this chunk inline rather than dropping it.
            Worker.run(chunk, action);
        }
    }
    var j: usize = 0;
    while (j < spawned) : (j += 1) threads_buf[j].join();
}

/// Maps every element of `data` through `transform` in parallel sections,
/// writing results into `out` (which must have `data.len` elements) at the
/// same index — so the output preserves input order. `transform` is invoked
/// as `callMap(transform, *const T) R`.
///
/// Returns an allocator error only if a worker thread cannot be spawned and
/// the fallback path needs none — in practice this never allocates; it is
/// declared `void` and writes through `out`.
pub fn map(comptime T: type, comptime R: type, data: []const T, out: []R, transform: anytype, min_fork_size: usize, task_count: usize) void {
    std.debug.assert(out.len == data.len);
    if (data.len == 0) return;

    const Worker = struct {
        fn run(in: []const T, dst: []R, tf: @TypeOf(transform)) void {
            for (in, 0..) |*v, k| dst[k] = callMap(tf, v);
        }
    };

    if (!parallelize(data.len, min_fork_size, task_count)) {
        Worker.run(data, out, transform);
        return;
    }

    const sections = nonEmptySectionCount(data.len, task_count);
    var threads_buf: [200]std.Thread = undefined;
    var spawned: usize = 0;
    var i: usize = 0;
    while (i < sections) : (i += 1) {
        const b = sectionBounds(data.len, i, sections);
        const in = data[b.lo..b.hi];
        const dst = out[b.lo..b.hi];
        if (i + 1 == sections) {
            Worker.run(in, dst, transform);
            break;
        }
        if (std.Thread.spawn(.{}, Worker.run, .{ in, dst, transform })) |t| {
            threads_buf[spawned] = t;
            spawned += 1;
        } else |_| {
            Worker.run(in, dst, transform);
        }
    }
    var j: usize = 0;
    while (j < spawned) : (j += 1) threads_buf[j].join();
}

fn callMap(transform: anytype, arg: anytype) blk: {
    const A = @TypeOf(transform);
    const info = @typeInfo(A);
    if (info == .pointer and @typeInfo(info.pointer.child) == .@"fn") {
        break :blk @typeInfo(info.pointer.child).@"fn".return_type.?;
    } else if (info == .@"fn") {
        break :blk info.@"fn".return_type.?;
    } else {
        break :blk @typeInfo(@TypeOf(A.call)).@"fn".return_type.?;
    }
} {
    const A = @TypeOf(transform);
    const info = @typeInfo(A);
    if (info == .pointer and @typeInfo(info.pointer.child) == .@"fn") {
        return transform(arg);
    } else if (info == .@"fn") {
        return transform(arg);
    } else {
        return transform.call(arg);
    }
}

/// Returns, in input order, the elements of `data` satisfying `predicate`.
/// Caller owns the returned slice and must free it with `allocator`.
/// `predicate` is invoked as `callPred(predicate, *const T) bool`.
///
/// Thread-safety: worker threads do **no** allocation — only the calling
/// thread allocates (the per-section count array and the single result
/// buffer). So, unlike the rest of this module, `filter` places **no**
/// thread-safety requirement on `allocator`: an `ArenaAllocator`,
/// `FixedBufferAllocator`, or non-thread-safe GPA is safe here (F2). The work
/// is two parallel passes: pass 1 counts matches per section, then pass 2
/// writes each section's matches into its own disjoint sub-slice of the result.
/// Because of the two passes, `predicate` is evaluated **twice per element**
/// and must be a pure function of the element (no side effects, same answer
/// both times).
pub fn filter(comptime T: type, allocator: Allocator, data: []const T, predicate: anytype, min_fork_size: usize, task_count: usize) ![]T {
    if (data.len == 0) return try allocator.alloc(T, 0);

    if (!parallelize(data.len, min_fork_size, task_count)) {
        var list = std.ArrayListUnmanaged(T){};
        errdefer list.deinit(allocator);
        for (data) |*v| {
            if (callPred(predicate, v)) try list.append(allocator, v.*);
        }
        return list.toOwnedSlice(allocator);
    }

    const sections = nonEmptySectionCount(data.len, task_count);

    // Pass 1 — count matches per section (no worker allocation).
    const counts = try allocator.alloc(usize, sections);
    defer allocator.free(counts);
    const Counter = struct {
        fn run(in: []const T, pred: @TypeOf(predicate), out: *usize) void {
            var c: usize = 0;
            for (in) |*v| {
                if (callPred(pred, v)) c += 1;
            }
            out.* = c;
        }
    };
    {
        var threads_buf: [200]std.Thread = undefined;
        var spawned: usize = 0;
        var i: usize = 0;
        while (i < sections) : (i += 1) {
            const b = sectionBounds(data.len, i, sections);
            const in = data[b.lo..b.hi];
            if (i + 1 == sections) {
                Counter.run(in, predicate, &counts[i]);
                break;
            }
            if (std.Thread.spawn(.{}, Counter.run, .{ in, predicate, &counts[i] })) |t| {
                threads_buf[spawned] = t;
                spawned += 1;
            } else |_| {
                Counter.run(in, predicate, &counts[i]);
            }
        }
        var j: usize = 0;
        while (j < spawned) : (j += 1) threads_buf[j].join();
    }

    // Prefix offsets restore input order across sections; one allocation.
    var total: usize = 0;
    for (counts) |c| total += c;
    const result = try allocator.alloc(T, total);
    errdefer allocator.free(result);

    // Pass 2 — each section fills its disjoint sub-slice (no worker allocation).
    const Filler = struct {
        fn run(in: []const T, pred: @TypeOf(predicate), out: []T) void {
            var k: usize = 0;
            for (in) |*v| {
                if (callPred(pred, v)) {
                    out[k] = v.*;
                    k += 1;
                }
            }
        }
    };
    {
        var threads_buf: [200]std.Thread = undefined;
        var spawned: usize = 0;
        var off: usize = 0;
        var i: usize = 0;
        while (i < sections) : (i += 1) {
            const b = sectionBounds(data.len, i, sections);
            const in = data[b.lo..b.hi];
            const out = result[off .. off + counts[i]];
            off += counts[i];
            if (i + 1 == sections) {
                Filler.run(in, predicate, out);
                break;
            }
            if (std.Thread.spawn(.{}, Filler.run, .{ in, predicate, out })) |t| {
                threads_buf[spawned] = t;
                spawned += 1;
            } else |_| {
                Filler.run(in, predicate, out);
            }
        }
        var j: usize = 0;
        while (j < spawned) : (j += 1) threads_buf[j].join();
    }

    return result;
}

/// Counts the elements of `data` satisfying `predicate`, in parallel.
/// `predicate` is invoked as `callPred(predicate, *const T) bool`.
pub fn count(comptime T: type, data: []const T, predicate: anytype, min_fork_size: usize, task_count: usize) usize {
    if (data.len == 0) return 0;

    if (!parallelize(data.len, min_fork_size, task_count)) {
        var c: usize = 0;
        for (data) |*v| {
            if (callPred(predicate, v)) c += 1;
        }
        return c;
    }

    const sections = nonEmptySectionCount(data.len, task_count);
    const Worker = struct {
        fn run(in: []const T, pred: @TypeOf(predicate), out: *usize) void {
            var c: usize = 0;
            for (in) |*v| {
                if (callPred(pred, v)) c += 1;
            }
            out.* = c;
        }
    };

    var counts: [200]usize = undefined;
    var threads_buf: [200]std.Thread = undefined;
    var spawned: usize = 0;
    var i: usize = 0;
    while (i < sections) : (i += 1) {
        const b = sectionBounds(data.len, i, sections);
        const in = data[b.lo..b.hi];
        if (i + 1 == sections) {
            Worker.run(in, predicate, &counts[i]);
            break;
        }
        if (std.Thread.spawn(.{}, Worker.run, .{ in, predicate, &counts[i] })) |t| {
            threads_buf[spawned] = t;
            spawned += 1;
        } else |_| {
            Worker.run(in, predicate, &counts[i]);
        }
    }
    var j: usize = 0;
    while (j < spawned) : (j += 1) threads_buf[j].join();

    var total: usize = 0;
    var k: usize = 0;
    while (k < sections) : (k += 1) total += counts[k];
    return total;
}

fn callPred(predicate: anytype, arg: anytype) bool {
    const A = @TypeOf(predicate);
    const info = @typeInfo(A);
    if (info == .pointer and @typeInfo(info.pointer.child) == .@"fn") {
        return predicate(arg);
    } else if (info == .@"fn") {
        return predicate(arg);
    } else {
        return predicate.call(arg);
    }
}

const testing = std.testing;

test "getBatchCount is ceiling, min one" {
    try testing.expectEqual(@as(usize, 4), getBatchCount(10, 3)); // ceil(10/3)
    try testing.expectEqual(@as(usize, 1), getBatchCount(10, 10));
    try testing.expectEqual(@as(usize, 1), getBatchCount(10, 100));
    try testing.expectEqual(@as(usize, 1), getBatchCount(10, 0)); // degenerate batch size
    try testing.expectEqual(@as(usize, 1), getBatchCount(0, 3)); // empty
}

test "sectionBounds tile without gaps" {
    const n: usize = 10;
    const cnt: usize = 3;
    var covered = std.ArrayListUnmanaged(usize){};
    defer covered.deinit(testing.allocator);
    var i: usize = 0;
    while (i < cnt) : (i += 1) {
        const b = sectionBounds(n, i, cnt);
        var j = b.lo;
        while (j < b.hi) : (j += 1) try covered.append(testing.allocator, j);
    }
    try testing.expectEqual(@as(usize, n), covered.items.len);
    for (covered.items, 0..) |v, idx| try testing.expectEqual(idx, v);

    // 10 into 3 -> 4,3,3.
    try testing.expectEqual(@as(usize, 0), sectionBounds(10, 0, 3).lo);
    try testing.expectEqual(@as(usize, 4), sectionBounds(10, 0, 3).hi);
    try testing.expectEqual(@as(usize, 4), sectionBounds(10, 1, 3).lo);
    try testing.expectEqual(@as(usize, 7), sectionBounds(10, 1, 3).hi);
    try testing.expectEqual(@as(usize, 7), sectionBounds(10, 2, 3).lo);
    try testing.expectEqual(@as(usize, 10), sectionBounds(10, 2, 3).hi);
}

test "section count exceeding size yields empty tail" {
    try testing.expectEqual(@as(usize, 0), sectionBounds(2, 0, 5).lo);
    try testing.expectEqual(@as(usize, 1), sectionBounds(2, 0, 5).hi);
    try testing.expectEqual(@as(usize, 1), sectionBounds(2, 1, 5).lo);
    try testing.expectEqual(@as(usize, 2), sectionBounds(2, 1, 5).hi);
    try testing.expectEqual(@as(usize, 2), sectionBounds(2, 2, 5).lo);
    try testing.expectEqual(@as(usize, 2), sectionBounds(2, 2, 5).hi);
    try testing.expectEqual(@as(usize, 2), sectionBounds(2, 4, 5).lo);
    try testing.expectEqual(@as(usize, 2), sectionBounds(2, 4, 5).hi);
}

test "sectionBounds count zero treated as one" {
    try testing.expectEqual(@as(usize, 0), sectionBounds(10, 0, 0).lo);
    try testing.expectEqual(@as(usize, 10), sectionBounds(10, 0, 0).hi);
    try testing.expectEqual(@as(usize, 0), sectionBounds(0, 0, 0).lo);
    try testing.expectEqual(@as(usize, 0), sectionBounds(0, 0, 0).hi);
}

test "batchForEach processes one section" {
    var data: [10]i32 = undefined;
    for (&data, 0..) |*d, i| d.* = @intCast(i);

    const Collector = struct {
        list: std.ArrayListUnmanaged(i32) = .{},
        fn call(self: *@This(), v: *const i32) void {
            self.list.append(testing.allocator, v.*) catch unreachable;
        }
    };
    var c = Collector{};
    defer c.list.deinit(testing.allocator);

    batchForEach(i32, &data, &c, 1, 3); // middle section 4..7
    try testing.expectEqualSlices(i32, &[_]i32{ 4, 5, 6 }, c.list.items);
}

test "parallel forEach visits every element once (stress)" {
    const allocator = testing.allocator;
    const n: u64 = 200_000;
    const data = try allocator.alloc(u64, n);
    defer allocator.free(data);
    for (data, 0..) |*d, i| d.* = @intCast(i);

    const Acc = struct {
        xor: std.atomic.Value(u64) = .init(0),
        cnt: std.atomic.Value(u64) = .init(0),
        fn call(self: *@This(), v: *const u64) void {
            _ = self.xor.fetchXor(v.*, .monotonic);
            _ = self.cnt.fetchAdd(1, .monotonic);
        }
    };
    var acc = Acc{};
    // Force parallelism with a low fork threshold.
    forEachWith(u64, data, &acc, 1, 8);

    var expected_xor: u64 = 0;
    var k: u64 = 0;
    while (k < n) : (k += 1) expected_xor ^= k;
    try testing.expectEqual(n, acc.cnt.load(.monotonic));
    try testing.expectEqual(expected_xor, acc.xor.load(.monotonic));
}

test "parallel map matches sequential oracle" {
    const allocator = testing.allocator;
    const n: usize = 20_000;
    const data = try allocator.alloc(i64, n);
    defer allocator.free(data);
    for (data, 0..) |*d, i| d.* = @intCast(i);

    const out = try allocator.alloc(i64, n);
    defer allocator.free(out);

    const dbl = struct {
        fn f(v: *const i64) i64 {
            return v.* * 2;
        }
    }.f;
    map(i64, i64, data, out, &dbl, 1, 8);
    for (out, 0..) |v, i| try testing.expectEqual(@as(i64, @intCast(i)) * 2, v);
}

test "parallel filter preserves input order and matches oracle" {
    const allocator = testing.allocator;
    const n: usize = 20_000;
    const data = try allocator.alloc(i64, n);
    defer allocator.free(data);
    for (data, 0..) |*d, i| d.* = @intCast(i);

    const isEven = struct {
        fn f(v: *const i64) bool {
            return @rem(v.*, 2) == 0;
        }
    }.f;
    const evens = try filter(i64, allocator, data, &isEven, 1, 8);
    defer allocator.free(evens);

    try testing.expectEqual(@as(usize, n / 2), evens.len);
    for (evens, 0..) |v, i| try testing.expectEqual(@as(i64, @intCast(i)) * 2, v);
}

test "parallel filter is safe with a non-thread-safe allocator (F2)" {
    // The workers do no allocation, so a non-thread-safe allocator (here an
    // arena) is sound even though multiple threads run concurrently. Before F2,
    // every section appended through the same allocator from N threads at once.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n: usize = 20_000;
    const data = try a.alloc(i64, n);
    for (data, 0..) |*d, i| d.* = @intCast(i);

    const isEven = struct {
        fn f(v: *const i64) bool {
            return @rem(v.*, 2) == 0;
        }
    }.f;
    // min_fork_size 1, task_count 8 forces the parallel multi-thread path.
    const evens = try filter(i64, a, data, &isEven, 1, 8);
    try testing.expectEqual(@as(usize, n / 2), evens.len);
    for (evens, 0..) |v, i| try testing.expectEqual(@as(i64, @intCast(i)) * 2, v);
}

test "parallel count matches sequential" {
    const allocator = testing.allocator;
    const n: usize = 30_000;
    const data = try allocator.alloc(i64, n);
    defer allocator.free(data);
    for (data, 0..) |*d, i| d.* = @intCast(i);

    const gt = struct {
        fn f(v: *const i64) bool {
            return v.* > 10_000;
        }
    }.f;
    try testing.expectEqual(@as(usize, n - 10_001), count(i64, data, &gt, 1, 8));
}

test "operations stay sequential below fork threshold but agree" {
    const allocator = testing.allocator;
    const n: usize = 1_000;
    const data = try allocator.alloc(i64, n);
    defer allocator.free(data);
    for (data, 0..) |*d, i| d.* = @intCast(i);

    // High threshold keeps everything sequential; answers must still match.
    const out = try allocator.alloc(i64, n);
    defer allocator.free(out);
    const inc = struct {
        fn f(v: *const i64) i64 {
            return v.* + 1;
        }
    }.f;
    map(i64, i64, data, out, &inc, std.math.maxInt(usize), 16);
    for (out, 0..) |v, i| try testing.expectEqual(@as(i64, @intCast(i)) + 1, v);

    const lt = struct {
        fn f(v: *const i64) bool {
            return v.* < 500;
        }
    }.f;
    try testing.expectEqual(@as(usize, 500), count(i64, data, &lt, std.math.maxInt(usize), 16));
}

test "empty input edge cases" {
    const allocator = testing.allocator;
    const empty = try allocator.alloc(i64, 0);
    defer allocator.free(empty);

    const out = try allocator.alloc(i64, 0);
    defer allocator.free(out);

    const always = struct {
        fn f(_: *const i64) bool {
            return true;
        }
    }.f;
    try testing.expectEqual(@as(usize, 0), count(i64, empty, &always, 1, 8));
    map(i64, i64, empty, out, struct {
        fn f(v: *const i64) i64 {
            return v.*;
        }
    }.f, 1, 8);
    const filtered = try filter(i64, allocator, empty, &always, 1, 8);
    defer allocator.free(filtered);
    try testing.expectEqual(@as(usize, 0), filtered.len);
}

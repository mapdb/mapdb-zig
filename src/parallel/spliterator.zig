// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Splittable iterators — the Zig analogue of `java.util.Spliterator`.
//!
//! A spliterator traverses elements like an iterator but can also *split*
//! itself (`trySplit`), handing back a new spliterator that covers a portion
//! of the remaining elements. This is the decomposition primitive Java
//! parallel streams build on; here it underpins the fixed-chunk batch
//! executor in `batch.zig`.
//!
//! This module is pure `std` and performs no parallel execution by itself —
//! it only describes how work can be divided. No threads are spawned here.

const std = @import("std");

/// Spliterator characteristic flags, matching the bit values of
/// `java.util.Spliterator` so that ported code reads identically.
pub const characteristics = struct {
    /// Elements are distinct (no duplicates) — e.g. a set source.
    pub const DISTINCT: u32 = 0x0000_0001;
    /// Elements follow a defined sort order (see also `ORDERED`).
    pub const SORTED: u32 = 0x0000_0004;
    /// Encounter order is meaningful and preserved across splits.
    pub const ORDERED: u32 = 0x0000_0010;
    /// `estimateSize` is an exact element count before traversal.
    pub const SIZED: u32 = 0x0000_0040;
    /// No element is null (always true for non-optional Zig sources).
    pub const NONNULL: u32 = 0x0000_0100;
    /// The source will not be structurally modified during traversal.
    pub const IMMUTABLE: u32 = 0x0000_0400;
    /// The source may be safely modified concurrently by other threads.
    pub const CONCURRENT: u32 = 0x0000_1000;
    /// All spliterators produced by `trySplit` are themselves `SIZED`.
    pub const SUBSIZED: u32 = 0x0000_4000;
};

/// A traversable, splittable source over a borrowed slice of `T`, yielding
/// `*const T` to each element.
///
/// Mirrors `java.util.Spliterator`: `tryAdvance` consumes one element,
/// `trySplit` partitions the remainder (returning a prefix and keeping the
/// suffix, the Java convention), and `characteristics` advertises
/// ordering/size guarantees.
///
/// Splitting is O(1): the backing slice is halved at the midpoint. Reports
/// `ORDERED | SIZED | SUBSIZED` since slices have an exact, stable length.
pub fn Spliterator(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The element type yielded by traversal.
        pub const Item = *const T;

        slice: []const T,

        /// Creates a spliterator covering the whole of `slice`.
        pub fn init(slice: []const T) Self {
            return .{ .slice = slice };
        }

        /// The not-yet-traversed remainder, as a slice.
        pub fn remainder(self: *const Self) []const T {
            return self.slice;
        }

        /// If an element remains, passes a `*const T` to it to `action` and
        /// returns `true`; otherwise returns `false` and does nothing.
        ///
        /// `action` is any value with a callable `fn (@TypeOf(action), *const T) void`
        /// — typically a pointer to a struct holding accumulator state.
        pub fn tryAdvance(self: *Self, action: anytype) bool {
            if (self.slice.len == 0) return false;
            const first = &self.slice[0];
            self.slice = self.slice[1..];
            call(action, first);
            return true;
        }

        /// Attempts to split off a prefix of the remaining elements into a new
        /// spliterator, leaving the suffix in `self` (the Java convention).
        ///
        /// Returns `null` when the source is too small to divide usefully
        /// (fewer than two elements), in which case `self` is unchanged and
        /// should be traversed sequentially.
        pub fn trySplit(self: *Self) ?Self {
            const n = self.slice.len;
            if (n < 2) return null;
            const mid = n / 2;
            const prefix = self.slice[0..mid];
            self.slice = self.slice[mid..];
            return Self{ .slice = prefix };
        }

        /// An estimate of the number of elements that would be traversed by
        /// `forEachRemaining`. Exact here, since slices are `SIZED`.
        pub fn estimateSize(self: *const Self) u64 {
            return @intCast(self.slice.len);
        }

        /// The bitwise-OR of this spliterator's characteristic flags.
        pub fn getCharacteristics(self: *const Self) u32 {
            _ = self;
            return characteristics.ORDERED | characteristics.SIZED | characteristics.SUBSIZED;
        }

        /// Returns `true` if all of the given characteristic bits are set.
        pub fn hasCharacteristics(self: *const Self, flags: u32) bool {
            return (self.getCharacteristics() & flags) == flags;
        }

        /// The exact remaining count if `SIZED`, otherwise `null`.
        pub fn exactSize(self: *const Self) ?u64 {
            if (self.hasCharacteristics(characteristics.SIZED)) {
                return self.estimateSize();
            }
            return null;
        }

        /// Traverses every remaining element, applying `action` to each.
        pub fn forEachRemaining(self: *Self, action: anytype) void {
            while (self.tryAdvance(action)) {}
        }
    };
}

/// Invokes `action` with `arg`. `action` may be a plain function pointer
/// `fn (*const T) void`, or any value (typically a struct pointer) exposing
/// a method `call(self, *const T) void` so it can carry accumulator state.
fn call(action: anytype, arg: anytype) void {
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

const testing = std.testing;

test "tryAdvance walks every element" {
    const data = [_]i32{ 1, 2, 3 };
    var sp = Spliterator(i32).init(&data);

    const Collector = struct {
        seen: std.ArrayListUnmanaged(i32) = .{},
        fn call(self: *@This(), v: *const i32) void {
            self.seen.append(testing.allocator, v.*) catch unreachable;
        }
    };
    var c = Collector{};
    defer c.seen.deinit(testing.allocator);

    while (sp.tryAdvance(&c)) {}
    try testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, c.seen.items);
    // Exhausted: a further advance is a no-op returning false.
    try testing.expect(!sp.tryAdvance(&c));
}

test "forEachRemaining visits all" {
    const data = [_]i32{ 10, 20, 30, 40 };
    var sp = Spliterator(i32).init(&data);

    const Summer = struct {
        sum: i32 = 0,
        fn call(self: *@This(), v: *const i32) void {
            self.sum += v.*;
        }
    };
    var s = Summer{};
    sp.forEachRemaining(&s);
    try testing.expectEqual(@as(i32, 100), s.sum);
}

test "trySplit returns prefix keeps suffix" {
    const data = [_]i32{ 1, 2, 3, 4, 5 };
    var sp = Spliterator(i32).init(&data);
    const prefix = sp.trySplit().?;
    // Java convention: prefix covers the front, self keeps the back.
    try testing.expectEqualSlices(i32, &[_]i32{ 1, 2 }, prefix.remainder());
    try testing.expectEqualSlices(i32, &[_]i32{ 3, 4, 5 }, sp.remainder());
}

test "split recursively covers every element once" {
    const allocator = testing.allocator;
    var data: [1000]i32 = undefined;
    for (&data, 0..) |*d, i| d.* = @intCast(i);

    var collected = std.ArrayListUnmanaged(i32){};
    defer collected.deinit(allocator);

    var work = std.ArrayListUnmanaged(Spliterator(i32)){};
    defer work.deinit(allocator);
    try work.append(allocator, Spliterator(i32).init(&data));

    while (work.pop()) |popped| {
        var sp = popped;
        if (sp.trySplit()) |prefix| {
            try work.append(allocator, prefix);
            try work.append(allocator, sp);
        } else {
            const Collector = struct {
                list: *std.ArrayListUnmanaged(i32),
                alloc: std.mem.Allocator,
                fn call(self: *@This(), v: *const i32) void {
                    self.list.append(self.alloc, v.*) catch unreachable;
                }
            };
            var c = Collector{ .list = &collected, .alloc = allocator };
            sp.forEachRemaining(&c);
        }
    }

    std.mem.sort(i32, collected.items, {}, std.sort.asc(i32));
    try testing.expectEqual(@as(usize, 1000), collected.items.len);
    for (collected.items, 0..) |v, i| try testing.expectEqual(@as(i32, @intCast(i)), v);
}

test "singletons and empties do not split" {
    const one = [_]i32{42};
    var sp_one = Spliterator(i32).init(&one);
    try testing.expect(sp_one.trySplit() == null);

    const none = [_]i32{};
    var sp_none = Spliterator(i32).init(&none);
    try testing.expect(sp_none.trySplit() == null);
}

test "characteristics and exact size" {
    const data = [_]i32{ 1, 2, 3 };
    const sp = Spliterator(i32).init(&data);
    try testing.expect(sp.hasCharacteristics(characteristics.SIZED));
    try testing.expect(sp.hasCharacteristics(characteristics.ORDERED | characteristics.SUBSIZED));
    try testing.expect(!sp.hasCharacteristics(characteristics.SORTED));
    try testing.expectEqual(@as(?u64, 3), sp.exactSize());
    try testing.expectEqual(@as(u64, 3), sp.estimateSize());
}

test "tryAdvance accepts a plain function pointer" {
    const data = [_]i32{7};
    var sp = Spliterator(i32).init(&data);
    const f = struct {
        fn f(v: *const i32) void {
            std.debug.assert(v.* == 7);
        }
    }.f;
    try testing.expect(sp.tryAdvance(&f));
    try testing.expect(!sp.tryAdvance(&f));
}

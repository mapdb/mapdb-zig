// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const F64ArrayList = @import("../arraylist/f64_array_list.zig").F64ArrayList;

/// Immutable list of `f64` values, backed by an owned allocated slice.
///
/// All operations are read-only. To modify, call `toMutable()` to get
/// an independent mutable copy. The caller must call `deinit()` when done.
///
/// Go equivalent:   ImmutableF64ArrayList
/// Rust equivalent:  ImmutableF64ArrayList (Arc-backed)
pub const ImmutableF64ArrayList = struct {
    items: []const f64,
    allocator: Allocator,

    /// Create from a slice by copying it. Caller retains ownership of the input.
    pub fn of(allocator: Allocator, values: []const f64) ImmutableF64ArrayList {
        const owned = allocator.dupe(f64, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    /// Create from a mutable list by taking a snapshot.
    pub fn fromMutable(allocator: Allocator, mutable: *const F64ArrayList) ImmutableF64ArrayList {
        return of(allocator, mutable.items.items);
    }

    /// Release the owned slice.
    pub fn deinit(self: *ImmutableF64ArrayList) void {
        self.allocator.free(self.items);
    }

    pub fn get(self: *const ImmutableF64ArrayList, index: usize) ?f64 {
        if (index >= self.items.len) return null;
        return self.items[index];
    }

    pub fn len(self: *const ImmutableF64ArrayList) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableF64ArrayList) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableF64ArrayList, value: f64) bool {
        for (self.items) |item| {
            if (@as(u64, @bitCast(item)) == @as(u64, @bitCast(value))) return true;
        }
        return false;
    }

    pub fn indexOf(self: *const ImmutableF64ArrayList, value: f64) ?usize {
        for (self.items, 0..) |item, i| {
            if (@as(u64, @bitCast(item)) == @as(u64, @bitCast(value))) return i;
        }
        return null;
    }

    pub fn toSlice(self: *const ImmutableF64ArrayList) []const f64 {
        return self.items;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const ImmutableF64ArrayList) f64 {
        var total: f64 = 0;
        for (self.items) |item| {
            total += item;
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const ImmutableF64ArrayList) ?f64 {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if ((blk: {
                const a_bits: u64 = @bitCast(item);
                const b_bits: u64 = @bitCast(result);
                if (std.math.isNan(item) or std.math.isNan(result)) break :blk std.math.order(a_bits, b_bits);
                const ord = std.math.order(item, result);
                if (ord != .eq) break :blk ord;
                break :blk std.math.order(a_bits, b_bits);
            }) == .lt) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const ImmutableF64ArrayList) ?f64 {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if ((blk: {
                const a_bits: u64 = @bitCast(item);
                const b_bits: u64 = @bitCast(result);
                if (std.math.isNan(item) or std.math.isNan(result)) break :blk std.math.order(a_bits, b_bits);
                const ord = std.math.order(item, result);
                if (ord != .eq) break :blk ord;
                break :blk std.math.order(a_bits, b_bits);
            }) == .gt) result = item;
        }
        return result;
    }

    pub fn anySatisfy(self: *const ImmutableF64ArrayList, predicate: *const fn (f64) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const ImmutableF64ArrayList, predicate: *const fn (f64) bool) bool {
        for (self.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const ImmutableF64ArrayList, predicate: *const fn (f64) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Create an independent mutable copy.
    pub fn toMutable(self: *const ImmutableF64ArrayList) F64ArrayList {
        return F64ArrayList.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableF64ArrayList, other: *const ImmutableF64ArrayList) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(@as(u64, @bitCast(a)) == @as(u64, @bitCast(b)))) return false;
        }
        return true;
    }
};

test "ImmutableF64ArrayList: of and get" {
    var il = ImmutableF64ArrayList.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 3), il.len());
    try std.testing.expectEqual(@as(?f64, 1.0), il.get(0));
    try std.testing.expectEqual(@as(?f64, null), il.get(99));
}

test "ImmutableF64ArrayList: contains" {
    var il = ImmutableF64ArrayList.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer il.deinit();
    try std.testing.expect(il.contains(1.0));
    try std.testing.expect(!il.contains(99.0));
}

test "ImmutableF64ArrayList: fromMutable" {
    var ml = F64ArrayList.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer ml.deinit();
    var il = ImmutableF64ArrayList.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "ImmutableF64ArrayList: toMutable independence" {
    var il = ImmutableF64ArrayList.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    ml.push(3.0);
    // Immutable list unchanged
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}

test "ImmutableF64ArrayList: eql" {
    var a = ImmutableF64ArrayList.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer a.deinit();
    var b = ImmutableF64ArrayList.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}

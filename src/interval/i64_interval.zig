// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// A virtual collection representing a range of `i64` values [from, to] with
/// a given step. No elements are materialised in memory.
pub const I64Interval = struct {
    from: i64,
    to: i64,
    step: i64,

    /// Creates an interval from `from` to `to` (inclusive) with the given step.
    pub fn fromToBy(from: i64, to: i64, step: i64) I64Interval {
        std.debug.assert(step != 0); // step must not be zero
        if (from < to) std.debug.assert(step > 0); // step must be positive when from < to
        if (from > to) std.debug.assert(step < 0); // step must be negative when from > to
        return .{ .from = from, .to = to, .step = step };
    }

    /// Creates an interval from `from` to `to` (inclusive) with step 1 or -1.
    pub fn fromTo(from: i64, to: i64) I64Interval {
        const step: i64 = if (from <= to) 1 else -1;
        return .{ .from = from, .to = to, .step = step };
    }

    /// Creates an interval from 1 to `to` (inclusive).
    pub fn oneTo(to: i64) I64Interval {
        return fromTo(1, to);
    }

    /// Creates an interval from 0 to `to` (inclusive).
    pub fn zeroTo(to: i64) I64Interval {
        return fromTo(0, to);
    }

    /// Returns the number of elements in the interval.
    pub fn len(self: *const I64Interval) usize {
        if ((self.step > 0 and self.from > self.to) or (self.step < 0 and self.from < self.to)) {
            return 0;
        }
        const diff: i128 = @as(i128, self.to) - @as(i128, self.from);
        const s: i128 = @as(i128, self.step);
        return @intCast(@divTrunc(diff, s) + 1);
    }

    /// Returns true if the interval is empty.
    pub fn isEmpty(self: *const I64Interval) bool {
        return self.len() == 0;
    }

    /// Returns true if the interval contains the given value.
    pub fn contains(self: *const I64Interval, value: i64) bool {
        if (self.step > 0) {
            const diff: i128 = @as(i128, value) - @as(i128, self.from);
            return value >= self.from and value <= self.to and @mod(diff, @as(i128, self.step)) == 0;
        } else {
            const diff: i128 = @as(i128, self.from) - @as(i128, value);
            return value <= self.from and value >= self.to and @mod(diff, -@as(i128, self.step)) == 0;
        }
    }

    /// Returns the element at the given index, or null if out of bounds.
    pub fn get(self: *const I64Interval, index: usize) ?i64 {
        if (index >= self.len()) return null;
        return @intCast(@as(i128, self.from) + @as(i128, self.step) * @as(i128, @intCast(index)));
    }

    /// Returns all elements as a slice. Caller must free the returned slice.
    pub fn toSlice(self: *const I64Interval, allocator: std.mem.Allocator) ![]i64 {
        const n = self.len();
        var result = try allocator.alloc(i64, n);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            result[i] = self.get(i).?;
        }
        return result;
    }

    /// Returns a reversed interval. Panics for the minimum signed
    /// step: negating `std.math.minInt(i64)` overflows.
    pub fn reversed(self: *const I64Interval) I64Interval {
        if (self.step == std.math.minInt(i64)) {
            @panic("I64Interval: cannot reverse interval with minimum step");
        }
        return .{ .from = self.to, .to = self.from, .step = -self.step };
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "I64Interval fromTo ascending" {
    const iv = I64Interval.fromTo(1, 5);
    try std.testing.expectEqual(@as(usize, 5), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5 }, slice);
}

test "I64Interval fromTo descending" {
    const iv = I64Interval.fromTo(5, 1);
    try std.testing.expectEqual(@as(usize, 5), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 5, 4, 3, 2, 1 }, slice);
}

test "I64Interval fromToBy" {
    const iv = I64Interval.fromToBy(0, 10, 2);
    try std.testing.expectEqual(@as(usize, 6), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 0, 2, 4, 6, 8, 10 }, slice);
}

test "I64Interval fromToBy negative step" {
    const iv = I64Interval.fromToBy(10, 1, -3);
    try std.testing.expectEqual(@as(usize, 4), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 10, 7, 4, 1 }, slice);
}

test "I64Interval single element" {
    const iv = I64Interval.fromTo(3, 3);
    try std.testing.expectEqual(@as(usize, 1), iv.len());
}

test "I64Interval contains" {
    const iv = I64Interval.fromToBy(0, 10, 2);
    try std.testing.expect(iv.contains(0));
    try std.testing.expect(iv.contains(4));
    try std.testing.expect(iv.contains(10));
    try std.testing.expect(!iv.contains(3));
    try std.testing.expect(!iv.contains(11));
}

test "I64Interval get" {
    const iv = I64Interval.fromTo(1, 5);
    try std.testing.expectEqual(@as(?i64, 1), iv.get(0));
    try std.testing.expectEqual(@as(?i64, 5), iv.get(4));
    try std.testing.expectEqual(@as(?i64, null), iv.get(5));
}

test "I64Interval reversed" {
    const iv = I64Interval.fromTo(1, 5);
    const rev = iv.reversed();
    const slice = try rev.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 5, 4, 3, 2, 1 }, slice);
}

test "I64Interval oneTo" {
    const iv = I64Interval.oneTo(3);
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3 }, slice);
}

test "I64Interval zeroTo" {
    const iv = I64Interval.zeroTo(3);
    try std.testing.expectEqual(@as(usize, 4), iv.len());
}

test "I64Interval isEmpty" {
    const iv = I64Interval.fromTo(1, 5);
    try std.testing.expect(!iv.isEmpty());
}

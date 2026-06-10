// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// A virtual collection representing a range of `i32` values [from, to] with
/// a given step. No elements are materialised in memory.
pub const I32Interval = struct {
    from: i32,
    to: i32,
    step: i32,

    /// Creates an interval from `from` to `to` (inclusive) with the given step.
    pub fn fromToBy(from: i32, to: i32, step: i32) I32Interval {
        // Always-on validation (not std.debug.assert, which is a no-op in
        // ReleaseFast): a zero step would divide by zero in len().
        if (step == 0) @panic("Interval.fromToBy: step must not be zero");
        if (from < to and step <= 0) @panic("Interval.fromToBy: step must be positive when from < to");
        if (from > to and step >= 0) @panic("Interval.fromToBy: step must be negative when from > to");
        return .{ .from = from, .to = to, .step = step };
    }

    /// Creates an interval from `from` to `to` (inclusive) with step 1 or -1.
    pub fn fromTo(from: i32, to: i32) I32Interval {
        const step: i32 = if (from <= to) 1 else -1;
        return .{ .from = from, .to = to, .step = step };
    }

    /// Creates an interval from 1 to `to` (inclusive).
    pub fn oneTo(to: i32) I32Interval {
        return fromTo(1, to);
    }

    /// Creates an interval from 0 to `to` (inclusive).
    pub fn zeroTo(to: i32) I32Interval {
        return fromTo(0, to);
    }

    /// Returns the number of elements in the interval.
    pub fn len(self: *const I32Interval) usize {
        if ((self.step > 0 and self.from > self.to) or (self.step < 0 and self.from < self.to)) {
            return 0;
        }
        const diff: i128 = @as(i128, self.to) - @as(i128, self.from);
        const s: i128 = @as(i128, self.step);
        const count: i128 = @divTrunc(diff, s) + 1;
        // Cap at the native maxInt(usize) instead of panicking on @intCast.
        // A full-range i64 interval has 2^64 elements, which exceeds usize.
        const cap: i128 = std.math.maxInt(usize);
        return @intCast(if (count > cap) cap else count);
    }

    /// Returns true if the interval is empty.
    pub fn isEmpty(self: *const I32Interval) bool {
        return self.len() == 0;
    }

    /// Returns true if the interval contains the given value.
    pub fn contains(self: *const I32Interval, value: i32) bool {
        if (self.step > 0) {
            const diff: i128 = @as(i128, value) - @as(i128, self.from);
            return value >= self.from and value <= self.to and @mod(diff, @as(i128, self.step)) == 0;
        } else {
            const diff: i128 = @as(i128, self.from) - @as(i128, value);
            return value <= self.from and value >= self.to and @mod(diff, -@as(i128, self.step)) == 0;
        }
    }

    /// Returns the element at the given index, or null if out of bounds.
    pub fn get(self: *const I32Interval, index: usize) ?i32 {
        if (index >= self.len()) return null;
        return @intCast(@as(i128, self.from) + @as(i128, self.step) * @as(i128, @intCast(index)));
    }

    /// Returns all elements as a slice. Caller must free the returned slice.
    pub fn toSlice(self: *const I32Interval, allocator: std.mem.Allocator) ![]i32 {
        const n = self.len();
        var result = try allocator.alloc(i32, n);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            result[i] = self.get(i).?;
        }
        return result;
    }

    /// Returns a reversed interval. Panics for the minimum signed
    /// step: negating `std.math.minInt(i32)` overflows.
    pub fn reversed(self: *const I32Interval) I32Interval {
        if (self.step == std.math.minInt(i32)) {
            @panic("I32Interval: cannot reverse interval with minimum step");
        }
        return .{ .from = self.to, .to = self.from, .step = -self.step };
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "I32Interval fromTo ascending" {
    const iv = I32Interval.fromTo(1, 5);
    try std.testing.expectEqual(@as(usize, 5), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3, 4, 5 }, slice);
}

test "I32Interval fromTo descending" {
    const iv = I32Interval.fromTo(5, 1);
    try std.testing.expectEqual(@as(usize, 5), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 5, 4, 3, 2, 1 }, slice);
}

test "I32Interval fromToBy" {
    const iv = I32Interval.fromToBy(0, 10, 2);
    try std.testing.expectEqual(@as(usize, 6), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 0, 2, 4, 6, 8, 10 }, slice);
}

test "I32Interval fromToBy negative step" {
    const iv = I32Interval.fromToBy(10, 1, -3);
    try std.testing.expectEqual(@as(usize, 4), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 7, 4, 1 }, slice);
}

test "I32Interval single element" {
    const iv = I32Interval.fromTo(3, 3);
    try std.testing.expectEqual(@as(usize, 1), iv.len());
}

test "I32Interval contains" {
    const iv = I32Interval.fromToBy(0, 10, 2);
    try std.testing.expect(iv.contains(0));
    try std.testing.expect(iv.contains(4));
    try std.testing.expect(iv.contains(10));
    try std.testing.expect(!iv.contains(3));
    try std.testing.expect(!iv.contains(11));
}

test "I32Interval get" {
    const iv = I32Interval.fromTo(1, 5);
    try std.testing.expectEqual(@as(?i32, 1), iv.get(0));
    try std.testing.expectEqual(@as(?i32, 5), iv.get(4));
    try std.testing.expectEqual(@as(?i32, null), iv.get(5));
}

test "I32Interval reversed" {
    const iv = I32Interval.fromTo(1, 5);
    const rev = iv.reversed();
    const slice = try rev.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 5, 4, 3, 2, 1 }, slice);
}

test "I32Interval oneTo" {
    const iv = I32Interval.oneTo(3);
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, slice);
}

test "I32Interval zeroTo" {
    const iv = I32Interval.zeroTo(3);
    try std.testing.expectEqual(@as(usize, 4), iv.len());
}

test "I32Interval isEmpty" {
    const iv = I32Interval.fromTo(1, 5);
    try std.testing.expect(!iv.isEmpty());
}

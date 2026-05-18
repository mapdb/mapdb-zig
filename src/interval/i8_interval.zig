
const std = @import("std");

/// A virtual collection representing a range of `i8` values [from, to] with
/// a given step. No elements are materialised in memory.
pub const I8Interval = struct {
    from: i8,
    to: i8,
    step: i8,

    /// Creates an interval from `from` to `to` (inclusive) with the given step.
    pub fn fromToBy(from: i8, to: i8, step: i8) I8Interval {
        std.debug.assert(step != 0); // step must not be zero
        if (from < to) std.debug.assert(step > 0); // step must be positive when from < to
        if (from > to) std.debug.assert(step < 0); // step must be negative when from > to
        return .{ .from = from, .to = to, .step = step };
    }

    /// Creates an interval from `from` to `to` (inclusive) with step 1 or -1.
    pub fn fromTo(from: i8, to: i8) I8Interval {
        const step: i8 = if (from <= to) 1 else -1;
        return .{ .from = from, .to = to, .step = step };
    }

    /// Creates an interval from 1 to `to` (inclusive).
    pub fn oneTo(to: i8) I8Interval {
        return fromTo(1, to);
    }

    /// Creates an interval from 0 to `to` (inclusive).
    pub fn zeroTo(to: i8) I8Interval {
        return fromTo(0, to);
    }

    /// Returns the number of elements in the interval.
    pub fn len(self: *const I8Interval) usize {
        if ((self.step > 0 and self.from > self.to) or (self.step < 0 and self.from < self.to)) {
            return 0;
        }
        const diff: i128 = @as(i128, self.to) - @as(i128, self.from);
        const s: i128 = @as(i128, self.step);
        return @intCast(@divTrunc(diff, s) + 1);
    }

    /// Returns true if the interval is empty.
    pub fn isEmpty(self: *const I8Interval) bool {
        return self.len() == 0;
    }

    /// Returns true if the interval contains the given value.
    pub fn contains(self: *const I8Interval, value: i8) bool {
        if (self.step > 0) {
            const diff: i128 = @as(i128, value) - @as(i128, self.from);
            return value >= self.from and value <= self.to and @mod(diff, @as(i128, self.step)) == 0;
        } else {
            const diff: i128 = @as(i128, self.from) - @as(i128, value);
            return value <= self.from and value >= self.to and @mod(diff, -@as(i128, self.step)) == 0;
        }
    }

    /// Returns the element at the given index, or null if out of bounds.
    pub fn get(self: *const I8Interval, index: usize) ?i8 {
        if (index >= self.len()) return null;
        return @intCast(@as(i128, self.from) + @as(i128, self.step) * @as(i128, @intCast(index)));
    }

    /// Returns all elements as a slice. Caller must free the returned slice.
    pub fn toSlice(self: *const I8Interval, allocator: std.mem.Allocator) ![]i8 {
        const n = self.len();
        var result = try allocator.alloc(i8, n);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            result[i] = self.get(i).?;
        }
        return result;
    }

    /// Returns a reversed interval.
    pub fn reversed(self: *const I8Interval) I8Interval {
        return .{ .from = self.to, .to = self.from, .step = -self.step };
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "I8Interval fromTo ascending" {
    const iv = I8Interval.fromTo(1, 5);
    try std.testing.expectEqual(@as(usize, 5), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i8, &[_]i8{ 1, 2, 3, 4, 5 }, slice);
}

test "I8Interval fromTo descending" {
    const iv = I8Interval.fromTo(5, 1);
    try std.testing.expectEqual(@as(usize, 5), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i8, &[_]i8{ 5, 4, 3, 2, 1 }, slice);
}

test "I8Interval fromToBy" {
    const iv = I8Interval.fromToBy(0, 10, 2);
    try std.testing.expectEqual(@as(usize, 6), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i8, &[_]i8{ 0, 2, 4, 6, 8, 10 }, slice);
}

test "I8Interval fromToBy negative step" {
    const iv = I8Interval.fromToBy(10, 1, -3);
    try std.testing.expectEqual(@as(usize, 4), iv.len());
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i8, &[_]i8{ 10, 7, 4, 1 }, slice);
}

test "I8Interval single element" {
    const iv = I8Interval.fromTo(3, 3);
    try std.testing.expectEqual(@as(usize, 1), iv.len());
}

test "I8Interval contains" {
    const iv = I8Interval.fromToBy(0, 10, 2);
    try std.testing.expect(iv.contains(0));
    try std.testing.expect(iv.contains(4));
    try std.testing.expect(iv.contains(10));
    try std.testing.expect(!iv.contains(3));
    try std.testing.expect(!iv.contains(11));
}

test "I8Interval get" {
    const iv = I8Interval.fromTo(1, 5);
    try std.testing.expectEqual(@as(?i8, 1), iv.get(0));
    try std.testing.expectEqual(@as(?i8, 5), iv.get(4));
    try std.testing.expectEqual(@as(?i8, null), iv.get(5));
}

test "I8Interval reversed" {
    const iv = I8Interval.fromTo(1, 5);
    const rev = iv.reversed();
    const slice = try rev.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i8, &[_]i8{ 5, 4, 3, 2, 1 }, slice);
}

test "I8Interval oneTo" {
    const iv = I8Interval.oneTo(3);
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i8, &[_]i8{ 1, 2, 3 }, slice);
}

test "I8Interval zeroTo" {
    const iv = I8Interval.zeroTo(3);
    try std.testing.expectEqual(@as(usize, 4), iv.len());
}

test "I8Interval isEmpty" {
    const iv = I8Interval.fromTo(1, 5);
    try std.testing.expect(!iv.isEmpty());
}

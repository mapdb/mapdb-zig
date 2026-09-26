// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");

/// A virtual collection representing a range of signed-integer values
/// `[from, to]` (inclusive) with a given step. No elements are materialised in
/// memory.
///
/// `Interval(T)` is a single-source generic that reproduces the former per-type
/// `<T>Interval` structs (`i8`/`i16`/`i32`/`i64`) byte-for-byte, with the type
/// token substituted. Interval is only meaningful for signed integer element
/// types; instantiating it with any other type is a `@compileError`. The
/// `bool`/`char`/`f32`/`f64` cases that the original family carried were inert
/// stubs ("Interval is not applicable to <type>") and are therefore simply not
/// instantiated by the aggregator.
///
/// The arithmetic widens to `i128` for the wrapping range computation so that a
/// full-range `i64` interval (whose element count is `2^64`) does not overflow;
/// `len()` then caps at `maxInt(usize)`. `reversed()` panics for the minimum
/// signed step, since negating `std.math.minInt(T)` overflows; otherwise it
/// starts from the last element actually produced (`to` pulled onto the step
/// grid), so `fromToBy(0, 10, 3).reversed()` is `9, 6, 3, 0`.
pub fn Interval(comptime T: type) type {
    switch (@typeInfo(T)) {
        .int => |info| if (info.signedness != .signed)
            @compileError("Interval is only applicable to signed integer types, got " ++ @typeName(T)),
        else => @compileError("Interval is only applicable to signed integer types, got " ++ @typeName(T)),
    }

    return struct {
        from: T,
        to: T,
        step: T,

        const Self = @This();

        /// Creates an interval from `from` to `to` (inclusive) with the given step.
        pub fn fromToBy(from: T, to: T, step: T) Self {
            // Always-on validation (not std.debug.assert, which is a no-op in
            // ReleaseFast): a zero step would divide by zero in len().
            if (step == 0) @panic("Interval.fromToBy: step must not be zero");
            if (from < to and step <= 0) @panic("Interval.fromToBy: step must be positive when from < to");
            if (from > to and step >= 0) @panic("Interval.fromToBy: step must be negative when from > to");
            return .{ .from = from, .to = to, .step = step };
        }

        /// Creates an interval from `from` to `to` (inclusive) with step 1 or -1.
        pub fn fromTo(from: T, to: T) Self {
            const step: T = if (from <= to) 1 else -1;
            return .{ .from = from, .to = to, .step = step };
        }

        /// Creates an interval from 1 to `to` (inclusive).
        pub fn oneTo(to: T) Self {
            return fromTo(1, to);
        }

        /// Creates an interval from 0 to `to` (inclusive).
        pub fn zeroTo(to: T) Self {
            return fromTo(0, to);
        }

        /// Returns the number of elements in the interval.
        pub fn len(self: *const Self) usize {
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
        pub fn isEmpty(self: *const Self) bool {
            return self.len() == 0;
        }

        /// Returns true if the interval contains the given value.
        pub fn contains(self: *const Self, value: T) bool {
            if (self.step > 0) {
                const diff: i128 = @as(i128, value) - @as(i128, self.from);
                return value >= self.from and value <= self.to and @mod(diff, @as(i128, self.step)) == 0;
            } else {
                const diff: i128 = @as(i128, self.from) - @as(i128, value);
                return value <= self.from and value >= self.to and @mod(diff, -@as(i128, self.step)) == 0;
            }
        }

        /// Returns the element at the given index, or null if out of bounds.
        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.len()) return null;
            return @intCast(@as(i128, self.from) + @as(i128, self.step) * @as(i128, @intCast(index)));
        }

        /// Returns all elements as a slice. Caller must free the returned slice.
        pub fn toSlice(self: *const Self, allocator: std.mem.Allocator) ![]T {
            const n = self.len();
            var result = try allocator.alloc(T, n);
            var i: usize = 0;
            while (i < n) : (i += 1) {
                result[i] = self.get(i).?;
            }
            return result;
        }

        /// Pull-based iterator yielding each element in order (`from`,
        /// `from + step`, … up to and including `to`) — the same sequence as
        /// `get(0)`, `get(1)`, … and as `toSlice`. Non-allocating: computes each
        /// value by index, materialising nothing. Holds the interval by value (a
        /// virtual collection with no backing storage), so it is unaffected by
        /// the source going out of scope.
        pub const Iterator = struct {
            interval: Self,
            index: usize = 0,

            pub fn next(self: *Iterator) ?T {
                const v = self.interval.get(self.index) orelse return null;
                self.index += 1;
                return v;
            }
        };

        /// Returns a pull-based iterator over the interval's elements in order
        /// (same sequence as `toSlice`). Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .interval = self.* };
        }

        /// Returns a reversed interval: the same elements in the opposite
        /// order, `get(len()-1)`, …, `get(0)`. Its `from` is the last element
        /// actually produced, not this interval's `to`, which is only an
        /// inclusive bound and may sit off the step grid (`fromToBy(0, 10, 3)`
        /// yields `0, 3, 6, 9`; its reverse is `9, 6, 3, 0`). Panics for the
        /// minimum signed step: negating `std.math.minInt(T)` overflows. The
        /// `@panic` is always-on (not `std.debug.assert`), so the trap holds in
        /// ReleaseFast too.
        pub fn reversed(self: *const Self) Self {
            if (self.step == std.math.minInt(T)) {
                @panic("Interval: cannot reverse interval with minimum step");
            }
            // Last element: pull `to` back onto the step grid. The remainder
            // never exceeds the distance, so `last` stays inside [from, to]
            // and the narrowing cast cannot fail. Computed in i128 (the width
            // len/contains/get already use) rather than via get(len()-1),
            // whose len() caps at maxInt(usize).
            const wide_from: i128 = self.from;
            const wide_to: i128 = self.to;
            const wide_step: i128 = self.step;
            const distance: i128 = if (wide_step > 0) wide_to - wide_from else wide_from - wide_to;
            const abs_step: i128 = if (wide_step > 0) wide_step else -wide_step;
            const rem: i128 = @rem(distance, abs_step);
            const last: T = @intCast(if (wide_step > 0) wide_to - rem else wide_to + rem);
            return .{ .from = last, .to = self.from, .step = -self.step };
        }
    };
}

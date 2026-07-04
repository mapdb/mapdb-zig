// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic immutable hash set. Single source for the 8 `Immutable<T>HashSet`
//! per-type wrappers.
//!
//! Backed by an owned allocated slice of the distinct members. Deduplication is
//! delegated to the production mutable `<T>HashSet` (already NaN/±0-correct).
//! `contains` compares float elements by bit pattern (NaN-aware, signed-zero
//! distinct); other types compare with `==`. `eql` builds on `contains`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const hashset = @import("../hashset/hashset.zig");

fn typeToken(comptime T: type) []const u8 {
    return switch (T) {
        bool => "bool",
        u21 => "char",
        i8 => "i8",
        i16 => "i16",
        i32 => "i32",
        i64 => "i64",
        f32 => "f32",
        f64 => "f64",
        else => @compileError("unsupported hash set type: " ++ @typeName(T)),
    };
}

fn typePascal(comptime T: type) []const u8 {
    return switch (T) {
        bool => "Bool",
        u21 => "Char",
        i8 => "I8",
        i16 => "I16",
        i32 => "I32",
        i64 => "I64",
        f32 => "F32",
        f64 => "F64",
        else => @compileError("unsupported hash set type: " ++ @typeName(T)),
    };
}

fn MutableType(comptime T: type) type {
    const module = @field(hashset, typeToken(T) ++ "_hash_set");
    return @field(module, typePascal(T) ++ "HashSet");
}

fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Immutable set of unique `T` values, backed by an owned allocated slice.
pub fn ImmutableHashSet(comptime T: type) type {
    return struct {
        items: []const T,
        allocator: Allocator,

        const Self = @This();
        const Mutable = MutableType(T);

        pub fn fromSlice(allocator: Allocator, values: []const T) Allocator.Error!Self {
            // Deduplicate via the production set.
            var mutable = try Mutable.init(allocator);
            defer mutable.deinit();
            for (values) |val| _ = try mutable.add(val);
            // Snapshot to owned slice.
            var buf: std.ArrayListUnmanaged(T) = .empty;
            errdefer buf.deinit(allocator);
            for (0..mutable.inner.capacity) |i| {
                if (mutable.inner.entries[i].occupied) try buf.append(allocator, mutable.inner.entries[i].key);
            }
            const owned = try buf.toOwnedSlice(allocator);
            return .{ .items = owned, .allocator = allocator };
        }

        pub fn fromMutable(allocator: Allocator, mutable: *const Mutable) Allocator.Error!Self {
            var buf: std.ArrayListUnmanaged(T) = .empty;
            errdefer buf.deinit(allocator);
            for (0..mutable.inner.capacity) |i| {
                if (mutable.inner.entries[i].occupied) try buf.append(allocator, mutable.inner.entries[i].key);
            }
            const owned = try buf.toOwnedSlice(allocator);
            return .{ .items = owned, .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn len(self: *const Self) usize {
            return self.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.len == 0;
        }

        /// Pull-based iterator yielding each element by value. The immutable hash
        /// set is backed by an owned snapshot slice, so iteration order is the
        /// fixed order captured at construction. Non-allocating: indexes directly
        /// into the owned backing slice.
        pub const Iterator = struct {
            items: []const T,
            index: usize = 0,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.items.len) return null;
                const item = self.items[self.index];
                self.index += 1;
                return item;
            }
        };

        /// Returns a pull-based iterator over the elements in the snapshot's
        /// fixed order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .items = self.items };
        }

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items) |item| {
                if (elemEql(T, item, value)) return true;
            }
            return false;
        }

        /// Borrowed view into internal storage; invalidated by any structural
        /// mutation; do not free.
        pub fn slice(self: *const Self) []const T {
            return self.items;
        }

        pub fn toMutable(self: *const Self) Allocator.Error!Mutable {
            return try Mutable.fromSlice(self.allocator, self.items);
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.items.len != other.items.len) return false;
            for (self.items) |item| {
                if (!other.contains(item)) return false;
            }
            return true;
        }
    };
}

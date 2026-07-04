// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic immutable bag (multiset). Single source for the 8 `Immutable<T>HashBag`
//! per-type wrappers.
//!
//! Backed by a snapshot of the counts map (`OpenHashMap(T, usize)`). All
//! operations are read-only. Key-equality (NaN-aware / signed-zero distinct for
//! float keys) is delegated entirely to `OpenHashMap`, so there is no
//! element-type-dependent logic in this wrapper.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const bag = @import("../bag/bag.zig");

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
        else => @compileError("unsupported hash bag type: " ++ @typeName(T)),
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
        else => @compileError("unsupported hash bag type: " ++ @typeName(T)),
    };
}

fn MutableType(comptime T: type) type {
    const module = @field(bag, typeToken(T) ++ "_hash_bag");
    return @field(module, typePascal(T) ++ "HashBag");
}

/// Immutable bag (multiset) of `T` values with occurrence counting.
pub fn ImmutableHashBag(comptime T: type) type {
    return struct {
        counts: OpenHashMap(T, usize),
        size: usize,
        allocator: Allocator,

        const Self = @This();
        const Mutable = MutableType(T);

        pub fn of(allocator: Allocator, values: []const T) Allocator.Error!Self {
            var mutable = try Mutable.init(allocator);
            defer mutable.deinit();
            for (values) |val| try mutable.add(val);
            const result = try fromMutable(allocator, &mutable);
            return result;
        }

        pub fn fromMutable(allocator: Allocator, mutable: *const Mutable) Allocator.Error!Self {
            var counts = try OpenHashMap(T, usize).init(allocator);
            errdefer counts.deinit();
            for (0..mutable.counts.capacity) |i| {
                if (mutable.counts.entries[i].occupied) {
                    _ = try counts.put(mutable.counts.entries[i].key, mutable.counts.entries[i].value);
                }
            }
            return .{
                .counts = counts,
                .size = mutable.size,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.counts.deinit();
        }

        pub fn occurrencesOf(self: *const Self, value: T) usize {
            return self.counts.get(value) orelse 0;
        }

        pub fn contains(self: *const Self, value: T) bool {
            return self.occurrencesOf(value) > 0;
        }

        pub fn totalSize(self: *const Self) usize {
            return self.size;
        }

        pub fn sizeDistinct(self: *const Self) usize {
            return self.counts.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }

        /// Borrowed view into internal storage; invalidated by any structural
        /// mutation; do not free.
        pub fn slice(self: *const Self) []const T {
            _ = self;
            // Not directly applicable for bags; use toMutable().
            return &[_]T{};
        }

        const InnerEntry = @import("../hash_table.zig").MapEntry(T, usize);

        /// Pull-based iterator yielding each element by value, repeated once per
        /// occurrence (matching the mutable `HashBag` iterator), in arbitrary
        /// (hash-table) order. Non-allocating: walks the inner snapshot
        /// count-map's occupied slots directly, tracking remaining occurrences.
        pub const Iterator = struct {
            entries: []const InnerEntry,
            index: usize = 0,
            remaining: usize = 0,
            current: T = undefined,

            pub fn next(self: *Iterator) ?T {
                if (self.remaining > 0) {
                    self.remaining -= 1;
                    return self.current;
                }
                while (self.index < self.entries.len) {
                    const e = self.entries[self.index];
                    self.index += 1;
                    if (e.occupied and e.value > 0) {
                        self.current = e.key;
                        self.remaining = e.value - 1;
                        return e.key;
                    }
                }
                return null;
            }
        };

        /// Returns a pull-based iterator yielding each element repeated by its
        /// occurrence count, in arbitrary order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .entries = self.counts.entries };
        }

        pub fn toMutable(self: *const Self) Allocator.Error!Mutable {
            var mutable = try Mutable.init(self.allocator);
            errdefer mutable.deinit();
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    var j: usize = 0;
                    while (j < self.counts.entries[i].value) : (j += 1) {
                        try mutable.add(self.counts.entries[i].key);
                    }
                }
            }
            return mutable;
        }
    };
}

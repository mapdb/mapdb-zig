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

        pub fn of(allocator: Allocator, values: []const T) Self {
            // Deduplicate via the production set.
            var mutable = Mutable.init(allocator);
            for (values) |val| _ = mutable.add(val);
            // Snapshot to owned slice.
            var buf: std.ArrayListUnmanaged(T) = .empty;
            for (0..mutable.inner.capacity) |i| {
                if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
            }
            mutable.deinit();
            const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
            return .{ .items = owned, .allocator = allocator };
        }

        pub fn fromMutable(allocator: Allocator, mutable: *const Mutable) Self {
            var buf: std.ArrayListUnmanaged(T) = .empty;
            for (0..mutable.inner.capacity) |i| {
                if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
            }
            const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
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

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items) |item| {
                if (elemEql(T, item, value)) return true;
            }
            return false;
        }

        pub fn toSlice(self: *const Self) []const T {
            return self.items;
        }

        pub fn toMutable(self: *const Self) Mutable {
            return Mutable.of(self.allocator, self.items);
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

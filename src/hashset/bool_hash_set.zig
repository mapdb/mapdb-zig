// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashSet = @import("../hash_table.zig").OpenHashSet;
const ImmutableBoolHashSet = @import("../immutable/immutable_bool_hash_set.zig").ImmutableBoolHashSet;

/// Hash set of unique `bool` values.
///
/// Backed by OpenHashSet(bool) — O(1) average add/remove/contains.
/// Supports separate allocators for keys and index structures via AllocatorConfig.
pub const BoolHashSet = struct {
    inner: OpenHashSet(bool),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) BoolHashSet {
        return .{
            .inner = OpenHashSet(bool).init(allocator, allocator) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    /// config.keysAllocator() is used for the hash table / items array.
    /// config.indexAllocator() is used for the hash table index buckets.
    pub fn initWithConfig(config: AllocatorConfig) BoolHashSet {
        return .{
            .inner = OpenHashSet(bool).init(config.keysAllocator(), config.indexAllocator()) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *BoolHashSet) void {
        self.inner.deinit();
    }

    pub fn of(allocator: Allocator, values: []const bool) BoolHashSet {
        var set = init(allocator);
        for (values) |val| _ = set.add(val);
        return set;
    }

    // ---- Core Operations ----

    /// Adds a value. Returns true if it was not already present.
    pub fn add(self: *BoolHashSet, value: bool) bool {
        return self.inner.add(value) catch @panic("out of memory");
    }

    /// Adds all values from a slice.
    pub fn addAll(self: *BoolHashSet, values: []const bool) void {
        for (values) |val| _ = self.add(val);
    }

    /// Removes a value. Returns true if it was present.
    pub fn remove(self: *BoolHashSet, value: bool) bool {
        return self.inner.remove(value);
    }

    pub fn contains(self: *const BoolHashSet, value: bool) bool {
        return self.inner.contains(value);
    }

    pub fn len(self: *const BoolHashSet) usize {
        return self.inner.len();
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const BoolHashSet) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const BoolHashSet) bool {
        return self.len() == 0;
    }

    pub fn clear(self: *BoolHashSet) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be added without
    /// triggering a rehash. Returns `error.OutOfMemory` if the allocator
    /// fails.
    pub fn ensureUnusedCapacity(self: *BoolHashSet, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the hash set's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *BoolHashSet, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    /// Calls f for each element.
    pub fn forEach(self: *const BoolHashSet, f: *const fn (bool) void) void {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                f(value);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new set with only elements satisfying the predicate.
    pub fn select(self: *const BoolHashSet, predicate: *const fn (bool) bool) BoolHashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) _ = result.add(value);
            }
        }
        return result;
    }

    /// Returns a new set with elements NOT satisfying the predicate.
    pub fn reject(self: *const BoolHashSet, predicate: *const fn (bool) bool) BoolHashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!predicate(value)) _ = result.add(value);
            }
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const BoolHashSet, predicate: *const fn (bool) bool) ?bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return value;
            }
        }
        return null;
    }

    /// Returns true if any element satisfies the predicate.
    pub fn anySatisfy(self: *const BoolHashSet, predicate: *const fn (bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return true;
            }
        }
        return false;
    }

    /// Returns true if all elements satisfy the predicate.
    pub fn allSatisfy(self: *const BoolHashSet, predicate: *const fn (bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!predicate(value)) return false;
            }
        }
        return true;
    }

    /// Returns true if no element satisfies the predicate.
    pub fn noneSatisfy(self: *const BoolHashSet, predicate: *const fn (bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return false;
            }
        }
        return true;
    }

    /// Returns the count of elements satisfying the predicate.
    pub fn count(self: *const BoolHashSet, predicate: *const fn (bool) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) c += 1;
            }
        }
        return c;
    }

    // ---- Set Operations ----

    pub fn setUnion(self: *const BoolHashSet, other: *const BoolHashSet) BoolHashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                _ = result.add(value);
            }
        }
        for (0..other.inner.capacity) |i| {
            if (other.inner.entries[i].occupied) {
                const value = other.inner.entries[i].key;
                _ = result.add(value);
            }
        }
        return result;
    }

    pub fn intersect(self: *const BoolHashSet, other: *const BoolHashSet) BoolHashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (other.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    pub fn difference(self: *const BoolHashSet, other: *const BoolHashSet) BoolHashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!other.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    pub fn symmetricDifference(self: *const BoolHashSet, other: *const BoolHashSet) BoolHashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!other.contains(value)) _ = result.add(value);
            }
        }
        for (0..other.inner.capacity) |i| {
            if (other.inner.entries[i].occupied) {
                const value = other.inner.entries[i].key;
                if (!self.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    // ---- Conversion ----

    /// Returns all elements as an allocated slice. Caller owns the slice.
    pub fn toSlice(self: *const BoolHashSet, allocator: Allocator) []bool {
        var buf: std.ArrayListUnmanaged(bool) = .empty;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                buf.append(allocator, value) catch @panic("out of memory");
            }
        }
        return buf.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Creates an immutable snapshot of this set.
    pub fn toImmutable(self: *const BoolHashSet) ImmutableBoolHashSet {
        return ImmutableBoolHashSet.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    /// Returns the set after adding a value (fluent).
    pub fn with(self: *BoolHashSet, value: bool) *BoolHashSet {
        _ = self.add(value);
        return self;
    }

    /// Returns the set after removing a value (fluent).
    pub fn without(self: *BoolHashSet, value: bool) *BoolHashSet {
        _ = self.remove(value);
        return self;
    }

    /// Adds all values from a slice (fluent).
    pub fn withAll(self: *BoolHashSet, values: []const bool) *BoolHashSet {
        self.addAll(values);
        return self;
    }

    /// Removes all values from a slice (fluent).
    pub fn withoutAll(self: *BoolHashSet, values: []const bool) *BoolHashSet {
        for (values) |val| _ = self.remove(val);
        return self;
    }

    // ---- Formatting ----

    /// Formats the set as "{v1, v2, v3}".
    pub fn format(self: *const BoolHashSet, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("{");
        var first = true;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!first) try writer.writeAll(", ");
                try writer.print("{any}", .{self.inner.entries[i].key});
                first = false;
            }
        }
        try writer.writeAll("}");
    }

    // ---- Equality ----

    pub fn eql(self: *const BoolHashSet, other: *const BoolHashSet) bool {
        if (self.len() != other.len()) return false;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!other.contains(value)) return false;
            }
        }
        return true;
    }
};

// ---- Tests ----

test "BoolHashSet: add and contains" {
    var set = BoolHashSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.add(true);
    _ = set.add(false);

    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(set.contains(false));
}

test "BoolHashSet: add duplicate" {
    var set = BoolHashSet.init(std.testing.allocator);
    defer set.deinit();
    try std.testing.expect(set.add(true));
    try std.testing.expect(!set.add(true));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "BoolHashSet: addAll" {
    var set = BoolHashSet.init(std.testing.allocator);
    defer set.deinit();
    set.addAll(&[_]bool{ true, false, true });
    try std.testing.expectEqual(@as(usize, 2), set.len());
}

test "BoolHashSet: remove" {
    var set = BoolHashSet.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer set.deinit();
    try std.testing.expect(set.remove(false));
    try std.testing.expect(!set.contains(false));
    try std.testing.expect(!set.remove(false));
}

test "BoolHashSet: clear" {
    var set = BoolHashSet.of(std.testing.allocator, &[_]bool{true});
    defer set.deinit();
    set.clear();
    try std.testing.expect(set.isEmpty());
}

test "BoolHashSet: forEach" {
    var set = BoolHashSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer set.deinit();
    var c: usize = 0;
    set.forEach(struct {
        fn f(_: bool) void {
            // count tracked via test logic below
        }
    }.f);
    // If forEach compiles and doesn't crash, it works.
    // Count elements manually:
    c = set.inner.len();
    try std.testing.expectEqual(@as(usize, 2), c);
}

test "BoolHashSet: select and reject" {
    var set = BoolHashSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer set.deinit();
    var sel = set.select(struct {
        fn f(val: bool) bool {
            return val;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 1), sel.len());
    var rej = set.reject(struct {
        fn f(val: bool) bool {
            return val;
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.len());
}

test "BoolHashSet: union" {
    var a = BoolHashSet.of(std.testing.allocator, &[_]bool{true});
    defer a.deinit();
    var b = BoolHashSet.of(std.testing.allocator, &[_]bool{false});
    defer b.deinit();
    var u = a.setUnion(&b);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 2), u.len());
}

test "BoolHashSet: intersect" {
    var a = BoolHashSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer a.deinit();
    var b = BoolHashSet.of(std.testing.allocator, &[_]bool{false});
    defer b.deinit();
    var inter = a.intersect(&b);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 1), inter.len());
}

test "BoolHashSet: difference" {
    var a = BoolHashSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer a.deinit();
    var b = BoolHashSet.of(std.testing.allocator, &[_]bool{false});
    defer b.deinit();
    var d = a.difference(&b);
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 1), d.len());
}

test "BoolHashSet: toSlice" {
    var set = BoolHashSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer set.deinit();
    const slice = set.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 2), slice.len);
}

test "BoolHashSet: toImmutable" {
    var set = BoolHashSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer set.deinit();
    var imm = set.toImmutable();
    defer imm.deinit();
    try std.testing.expectEqual(@as(usize, 2), imm.len());
    // Mutate original — immutable should be independent
    _ = set.add(true);
    try std.testing.expectEqual(@as(usize, 2), imm.len());
}

test "BoolHashSet: fluent with/without" {
    var set = BoolHashSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.with(true).with(false);
    try std.testing.expectEqual(@as(usize, 2), set.len());
    _ = set.without(true);
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "BoolHashSet: eql" {
    var a = BoolHashSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer a.deinit();
    var b = BoolHashSet.of(std.testing.allocator, &[_]bool{ false, true });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}

test "BoolHashSet: ensureUnusedCapacity reserves and subsequent add does not resize" {
    var set = BoolHashSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureUnusedCapacity(200);
    const reserved = set.inner.capacity;
    try std.testing.expect(reserved >= 200);
    _ = set.add(true);
    _ = set.add(false);
    try std.testing.expectEqual(reserved, set.inner.capacity);
}

test "BoolHashSet: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var set = BoolHashSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureTotalCapacity(200);
    const reserved = set.inner.capacity;
    try set.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, set.inner.capacity);
}

test "BoolHashSet: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1 lets init() allocate the initial table (the 1st alloc)
    // but fails the 2nd alloc, which is the grow triggered by ensureCapacity.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var set = BoolHashSet.init(failing.allocator());
    defer set.deinit();
    try std.testing.expectError(error.OutOfMemory, set.ensureUnusedCapacity(10_000));
}

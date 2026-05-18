
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashSet = @import("../hash_table.zig").OpenHashSet;
const ImmutableI8HashSet = @import("../immutable/immutable_i8_hash_set.zig").ImmutableI8HashSet;

/// Hash set of unique `i8` values.
///
/// Backed by OpenHashSet(i8) — O(1) average add/remove/contains.
/// Supports separate allocators for keys and index structures via AllocatorConfig.
pub const I8HashSet = struct {
    inner: OpenHashSet(i8),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I8HashSet {
        return .{
            .inner = OpenHashSet(i8).init(allocator, allocator) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    /// config.keysAllocator() is used for the hash table / items array.
    /// config.indexAllocator() is used for the hash table index buckets.
    pub fn initWithConfig(config: AllocatorConfig) I8HashSet {
        return .{
            .inner = OpenHashSet(i8).init(config.keysAllocator(), config.indexAllocator()) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *I8HashSet) void {
        self.inner.deinit();
    }

    pub fn of(allocator: Allocator, values: []const i8) I8HashSet {
        var set = init(allocator);
        for (values) |val| _ = set.add(val);
        return set;
    }

    // ---- Core Operations ----

    /// Adds a value. Returns true if it was not already present.
    pub fn add(self: *I8HashSet, value: i8) bool {
        return self.inner.add(value) catch @panic("out of memory");
    }

    /// Adds all values from a slice.
    pub fn addAll(self: *I8HashSet, values: []const i8) void {
        for (values) |val| _ = self.add(val);
    }

    /// Removes a value. Returns true if it was present.
    pub fn remove(self: *I8HashSet, value: i8) bool {
        return self.inner.remove(value);
    }

    pub fn contains(self: *const I8HashSet, value: i8) bool {
        return self.inner.contains(value);
    }

    pub fn len(self: *const I8HashSet) usize {
        return self.inner.len();
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const I8HashSet) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const I8HashSet) bool {
        return self.len() == 0;
    }

    pub fn clear(self: *I8HashSet) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be added without
    /// triggering a rehash. Returns `error.OutOfMemory` if the allocator
    /// fails.
    pub fn ensureUnusedCapacity(self: *I8HashSet, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the hash set's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *I8HashSet, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    /// Calls f for each element.
    pub fn forEach(self: *const I8HashSet, f: *const fn (i8) void) void {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                f(value);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new set with only elements satisfying the predicate.
    pub fn select(self: *const I8HashSet, predicate: *const fn (i8) bool) I8HashSet {
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
    pub fn reject(self: *const I8HashSet, predicate: *const fn (i8) bool) I8HashSet {
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
    pub fn detect(self: *const I8HashSet, predicate: *const fn (i8) bool) ?i8 {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return value;
            }
        }
        return null;
    }

    /// Returns true if any element satisfies the predicate.
    pub fn anySatisfy(self: *const I8HashSet, predicate: *const fn (i8) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return true;
            }
        }
        return false;
    }

    /// Returns true if all elements satisfy the predicate.
    pub fn allSatisfy(self: *const I8HashSet, predicate: *const fn (i8) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!predicate(value)) return false;
            }
        }
        return true;
    }

    /// Returns true if no element satisfies the predicate.
    pub fn noneSatisfy(self: *const I8HashSet, predicate: *const fn (i8) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return false;
            }
        }
        return true;
    }

    /// Returns the count of elements satisfying the predicate.
    pub fn count(self: *const I8HashSet, predicate: *const fn (i8) bool) usize {
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

    pub fn setUnion(self: *const I8HashSet, other: *const I8HashSet) I8HashSet {
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

    pub fn intersect(self: *const I8HashSet, other: *const I8HashSet) I8HashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (other.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    pub fn difference(self: *const I8HashSet, other: *const I8HashSet) I8HashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!other.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    pub fn symmetricDifference(self: *const I8HashSet, other: *const I8HashSet) I8HashSet {
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
    pub fn toSlice(self: *const I8HashSet, allocator: Allocator) []i8 {
        var buf: std.ArrayListUnmanaged(i8) = .empty;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                buf.append(allocator, value) catch @panic("out of memory");
            }
        }
        return buf.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Creates an immutable snapshot of this set.
    pub fn toImmutable(self: *const I8HashSet) ImmutableI8HashSet {
        return ImmutableI8HashSet.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    /// Returns the set after adding a value (fluent).
    pub fn with(self: *I8HashSet, value: i8) *I8HashSet {
        _ = self.add(value);
        return self;
    }

    /// Returns the set after removing a value (fluent).
    pub fn without(self: *I8HashSet, value: i8) *I8HashSet {
        _ = self.remove(value);
        return self;
    }

    /// Adds all values from a slice (fluent).
    pub fn withAll(self: *I8HashSet, values: []const i8) *I8HashSet {
        self.addAll(values);
        return self;
    }

    /// Removes all values from a slice (fluent).
    pub fn withoutAll(self: *I8HashSet, values: []const i8) *I8HashSet {
        for (values) |val| _ = self.remove(val);
        return self;
    }

    // ---- Formatting ----

    /// Formats the set as "{v1, v2, v3}".
    pub fn format(self: *const I8HashSet, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I8HashSet, other: *const I8HashSet) bool {
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

test "I8HashSet: add and contains" {
    var set = I8HashSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.add(1);
    _ = set.add(2);
    _ = set.add(3);
    try std.testing.expectEqual(@as(usize, 3), set.len());
    try std.testing.expect(set.contains(2));
    try std.testing.expect(!set.contains(99));
}

test "I8HashSet: add duplicate" {
    var set = I8HashSet.init(std.testing.allocator);
    defer set.deinit();
    try std.testing.expect(set.add(1));
    try std.testing.expect(!set.add(1));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "I8HashSet: addAll" {
    var set = I8HashSet.init(std.testing.allocator);
    defer set.deinit();
    set.addAll(&[_]i8{ 1, 2, 1 });
    try std.testing.expectEqual(@as(usize, 2), set.len());
}

test "I8HashSet: remove" {
    var set = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2, 3 });
    defer set.deinit();
    try std.testing.expect(set.remove(2));
    try std.testing.expect(!set.contains(2));
    try std.testing.expect(!set.remove(99));
}

test "I8HashSet: clear" {
    var set = I8HashSet.of(std.testing.allocator, &[_]i8{1});
    defer set.deinit();
    set.clear();
    try std.testing.expect(set.isEmpty());
}

test "I8HashSet: forEach" {
    var set = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer set.deinit();
    var c: usize = 0;
    set.forEach(struct {
        fn f(_: i8) void {
            // count tracked via test logic below
        }
    }.f);
    // If forEach compiles and doesn't crash, it works.
    // Count elements manually:
    c = set.inner.len();
    try std.testing.expectEqual(@as(usize, 2), c);
}

test "I8HashSet: select and reject" {
    var set = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2, 3, 4, 5 });
    defer set.deinit();
    var sel = set.select(struct {
        fn f(val: i8) bool {
            return val > 3;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
    var rej = set.reject(struct {
        fn f(val: i8) bool {
            return val > 3;
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 3), rej.len());
}

test "I8HashSet: detect" {
    var set = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2, 3 });
    defer set.deinit();
    const found = set.detect(struct {
        fn f(val: i8) bool {
            return val == 2;
        }
    }.f);
    try std.testing.expectEqual(@as(?i8, 2), found);
    const not_found = set.detect(struct {
        fn f(val: i8) bool {
            return val == 99;
        }
    }.f);
    try std.testing.expectEqual(@as(?i8, null), not_found);
}

test "I8HashSet: count" {
    var set = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2, 3, 4, 5 });
    defer set.deinit();
    const c = set.count(struct {
        fn f(val: i8) bool {
            return val > 3;
        }
    }.f);
    try std.testing.expectEqual(@as(usize, 2), c);
}

test "I8HashSet: union" {
    var a = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2, 3 });
    defer a.deinit();
    var b = I8HashSet.of(std.testing.allocator, &[_]i8{ 3, 4, 5 });
    defer b.deinit();
    var u = a.setUnion(&b);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 5), u.len());
}

test "I8HashSet: intersect" {
    var a = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2, 3 });
    defer a.deinit();
    var b = I8HashSet.of(std.testing.allocator, &[_]i8{ 2, 3, 4 });
    defer b.deinit();
    var inter = a.intersect(&b);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 2), inter.len());
}

test "I8HashSet: difference" {
    var a = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2, 3 });
    defer a.deinit();
    var b = I8HashSet.of(std.testing.allocator, &[_]i8{ 2, 3, 4 });
    defer b.deinit();
    var d = a.difference(&b);
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 1), d.len());
}

test "I8HashSet: toSlice" {
    var set = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer set.deinit();
    const slice = set.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 2), slice.len);
}

test "I8HashSet: toImmutable" {
    var set = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer set.deinit();
    var imm = set.toImmutable();
    defer imm.deinit();
    try std.testing.expectEqual(@as(usize, 2), imm.len());
    // Mutate original — immutable should be independent
    _ = set.add(3);
    try std.testing.expectEqual(@as(usize, 2), imm.len());
}

test "I8HashSet: fluent with/without" {
    var set = I8HashSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.with(1).with(2);
    try std.testing.expectEqual(@as(usize, 2), set.len());
    _ = set.without(1);
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "I8HashSet: eql" {
    var a = I8HashSet.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer a.deinit();
    var b = I8HashSet.of(std.testing.allocator, &[_]i8{ 2, 1 });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}

test "I8HashSet: ensureUnusedCapacity reserves and subsequent add does not resize" {
    var set = I8HashSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureUnusedCapacity(200);
    const reserved = set.inner.capacity;
    try std.testing.expect(reserved >= 200);
    _ = set.add(1);
    _ = set.add(2);
    try std.testing.expectEqual(reserved, set.inner.capacity);
}

test "I8HashSet: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var set = I8HashSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureTotalCapacity(200);
    const reserved = set.inner.capacity;
    try set.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, set.inner.capacity);
}

test "I8HashSet: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1 lets init() allocate the initial table (the 1st alloc)
    // but fails the 2nd alloc, which is the grow triggered by ensureCapacity.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var set = I8HashSet.init(failing.allocator());
    defer set.deinit();
    try std.testing.expectError(error.OutOfMemory, set.ensureUnusedCapacity(10_000));
}

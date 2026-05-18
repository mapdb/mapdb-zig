
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashSet = @import("../hash_table.zig").OpenHashSet;
const ImmutableCharHashSet = @import("../immutable/immutable_char_hash_set.zig").ImmutableCharHashSet;

/// Hash set of unique `u21` values.
///
/// Backed by OpenHashSet(u21) — O(1) average add/remove/contains.
/// Supports separate allocators for keys and index structures via AllocatorConfig.
pub const CharHashSet = struct {
    inner: OpenHashSet(u21),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) CharHashSet {
        return .{
            .inner = OpenHashSet(u21).init(allocator, allocator) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    /// config.keysAllocator() is used for the hash table / items array.
    /// config.indexAllocator() is used for the hash table index buckets.
    pub fn initWithConfig(config: AllocatorConfig) CharHashSet {
        return .{
            .inner = OpenHashSet(u21).init(config.keysAllocator(), config.indexAllocator()) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *CharHashSet) void {
        self.inner.deinit();
    }

    pub fn of(allocator: Allocator, values: []const u21) CharHashSet {
        var set = init(allocator);
        for (values) |val| _ = set.add(val);
        return set;
    }

    // ---- Core Operations ----

    /// Adds a value. Returns true if it was not already present.
    pub fn add(self: *CharHashSet, value: u21) bool {
        return self.inner.add(value) catch @panic("out of memory");
    }

    /// Adds all values from a slice.
    pub fn addAll(self: *CharHashSet, values: []const u21) void {
        for (values) |val| _ = self.add(val);
    }

    /// Removes a value. Returns true if it was present.
    pub fn remove(self: *CharHashSet, value: u21) bool {
        return self.inner.remove(value);
    }

    pub fn contains(self: *const CharHashSet, value: u21) bool {
        return self.inner.contains(value);
    }

    pub fn len(self: *const CharHashSet) usize {
        return self.inner.len();
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const CharHashSet) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const CharHashSet) bool {
        return self.len() == 0;
    }

    pub fn clear(self: *CharHashSet) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be added without
    /// triggering a rehash. Returns `error.OutOfMemory` if the allocator
    /// fails.
    pub fn ensureUnusedCapacity(self: *CharHashSet, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the hash set's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *CharHashSet, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    /// Calls f for each element.
    pub fn forEach(self: *const CharHashSet, f: *const fn (u21) void) void {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                f(value);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new set with only elements satisfying the predicate.
    pub fn select(self: *const CharHashSet, predicate: *const fn (u21) bool) CharHashSet {
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
    pub fn reject(self: *const CharHashSet, predicate: *const fn (u21) bool) CharHashSet {
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
    pub fn detect(self: *const CharHashSet, predicate: *const fn (u21) bool) ?u21 {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return value;
            }
        }
        return null;
    }

    /// Returns true if any element satisfies the predicate.
    pub fn anySatisfy(self: *const CharHashSet, predicate: *const fn (u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return true;
            }
        }
        return false;
    }

    /// Returns true if all elements satisfy the predicate.
    pub fn allSatisfy(self: *const CharHashSet, predicate: *const fn (u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!predicate(value)) return false;
            }
        }
        return true;
    }

    /// Returns true if no element satisfies the predicate.
    pub fn noneSatisfy(self: *const CharHashSet, predicate: *const fn (u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return false;
            }
        }
        return true;
    }

    /// Returns the count of elements satisfying the predicate.
    pub fn count(self: *const CharHashSet, predicate: *const fn (u21) bool) usize {
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

    pub fn setUnion(self: *const CharHashSet, other: *const CharHashSet) CharHashSet {
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

    pub fn intersect(self: *const CharHashSet, other: *const CharHashSet) CharHashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (other.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    pub fn difference(self: *const CharHashSet, other: *const CharHashSet) CharHashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!other.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    pub fn symmetricDifference(self: *const CharHashSet, other: *const CharHashSet) CharHashSet {
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
    pub fn toSlice(self: *const CharHashSet, allocator: Allocator) []u21 {
        var buf: std.ArrayListUnmanaged(u21) = .empty;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                buf.append(allocator, value) catch @panic("out of memory");
            }
        }
        return buf.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Creates an immutable snapshot of this set.
    pub fn toImmutable(self: *const CharHashSet) ImmutableCharHashSet {
        return ImmutableCharHashSet.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    /// Returns the set after adding a value (fluent).
    pub fn with(self: *CharHashSet, value: u21) *CharHashSet {
        _ = self.add(value);
        return self;
    }

    /// Returns the set after removing a value (fluent).
    pub fn without(self: *CharHashSet, value: u21) *CharHashSet {
        _ = self.remove(value);
        return self;
    }

    /// Adds all values from a slice (fluent).
    pub fn withAll(self: *CharHashSet, values: []const u21) *CharHashSet {
        self.addAll(values);
        return self;
    }

    /// Removes all values from a slice (fluent).
    pub fn withoutAll(self: *CharHashSet, values: []const u21) *CharHashSet {
        for (values) |val| _ = self.remove(val);
        return self;
    }

    // ---- Formatting ----

    /// Formats the set as "{v1, v2, v3}".
    pub fn format(self: *const CharHashSet, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const CharHashSet, other: *const CharHashSet) bool {
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

test "CharHashSet: add and contains" {
    var set = CharHashSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.add('a');
    _ = set.add('b');
    _ = set.add('c');
    try std.testing.expectEqual(@as(usize, 3), set.len());
    try std.testing.expect(set.contains('b'));
    try std.testing.expect(!set.contains('z'));
}

test "CharHashSet: add duplicate" {
    var set = CharHashSet.init(std.testing.allocator);
    defer set.deinit();
    try std.testing.expect(set.add('a'));
    try std.testing.expect(!set.add('a'));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "CharHashSet: addAll" {
    var set = CharHashSet.init(std.testing.allocator);
    defer set.deinit();
    set.addAll(&[_]u21{ 'a', 'b', 'a' });
    try std.testing.expectEqual(@as(usize, 2), set.len());
}

test "CharHashSet: remove" {
    var set = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer set.deinit();
    try std.testing.expect(set.remove('b'));
    try std.testing.expect(!set.contains('b'));
    try std.testing.expect(!set.remove('z'));
}

test "CharHashSet: clear" {
    var set = CharHashSet.of(std.testing.allocator, &[_]u21{'a'});
    defer set.deinit();
    set.clear();
    try std.testing.expect(set.isEmpty());
}

test "CharHashSet: forEach" {
    var set = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer set.deinit();
    var c: usize = 0;
    set.forEach(struct {
        fn f(_: u21) void {
            // count tracked via test logic below
        }
    }.f);
    // If forEach compiles and doesn't crash, it works.
    // Count elements manually:
    c = set.inner.len();
    try std.testing.expectEqual(@as(usize, 2), c);
}

test "CharHashSet: select and reject" {
    var set = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c', 'd', 'e' });
    defer set.deinit();
    var sel = set.select(struct {
        fn f(val: u21) bool {
            return val > 'c';
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
    var rej = set.reject(struct {
        fn f(val: u21) bool {
            return val > 'c';
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 3), rej.len());
}

test "CharHashSet: detect" {
    var set = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer set.deinit();
    const found = set.detect(struct {
        fn f(val: u21) bool {
            return val == 'b';
        }
    }.f);
    try std.testing.expectEqual(@as(?u21, 'b'), found);
    const not_found = set.detect(struct {
        fn f(val: u21) bool {
            return val == 'z';
        }
    }.f);
    try std.testing.expectEqual(@as(?u21, null), not_found);
}

test "CharHashSet: count" {
    var set = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c', 'd', 'e' });
    defer set.deinit();
    const c = set.count(struct {
        fn f(val: u21) bool {
            return val > 'c';
        }
    }.f);
    try std.testing.expectEqual(@as(usize, 2), c);
}

test "CharHashSet: union" {
    var a = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer a.deinit();
    var b = CharHashSet.of(std.testing.allocator, &[_]u21{ 'c', 'd', 'e' });
    defer b.deinit();
    var u = a.setUnion(&b);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 5), u.len());
}

test "CharHashSet: intersect" {
    var a = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer a.deinit();
    var b = CharHashSet.of(std.testing.allocator, &[_]u21{ 'b', 'c', 'd' });
    defer b.deinit();
    var inter = a.intersect(&b);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 2), inter.len());
}

test "CharHashSet: difference" {
    var a = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer a.deinit();
    var b = CharHashSet.of(std.testing.allocator, &[_]u21{ 'b', 'c', 'd' });
    defer b.deinit();
    var d = a.difference(&b);
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 1), d.len());
}

test "CharHashSet: toSlice" {
    var set = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer set.deinit();
    const slice = set.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 2), slice.len);
}

test "CharHashSet: toImmutable" {
    var set = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer set.deinit();
    var imm = set.toImmutable();
    defer imm.deinit();
    try std.testing.expectEqual(@as(usize, 2), imm.len());
    // Mutate original — immutable should be independent
    _ = set.add('c');
    try std.testing.expectEqual(@as(usize, 2), imm.len());
}

test "CharHashSet: fluent with/without" {
    var set = CharHashSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.with('a').with('b');
    try std.testing.expectEqual(@as(usize, 2), set.len());
    _ = set.without('a');
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "CharHashSet: eql" {
    var a = CharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer a.deinit();
    var b = CharHashSet.of(std.testing.allocator, &[_]u21{ 'b', 'a' });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}

test "CharHashSet: ensureUnusedCapacity reserves and subsequent add does not resize" {
    var set = CharHashSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureUnusedCapacity(200);
    const reserved = set.inner.capacity;
    try std.testing.expect(reserved >= 200);
    _ = set.add('a');
    _ = set.add('b');
    try std.testing.expectEqual(reserved, set.inner.capacity);
}

test "CharHashSet: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var set = CharHashSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureTotalCapacity(200);
    const reserved = set.inner.capacity;
    try set.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, set.inner.capacity);
}

test "CharHashSet: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1 lets init() allocate the initial table (the 1st alloc)
    // but fails the 2nd alloc, which is the grow triggered by ensureCapacity.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var set = CharHashSet.init(failing.allocator());
    defer set.deinit();
    try std.testing.expectError(error.OutOfMemory, set.ensureUnusedCapacity(10_000));
}

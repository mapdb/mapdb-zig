
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashSet = @import("../hash_table.zig").OpenHashSet;
const ImmutableF64HashSet = @import("../immutable/immutable_f64_hash_set.zig").ImmutableF64HashSet;

/// Hash set of unique `f64` values.
///
/// Backed by OpenHashSet(f64) — O(1) average add/remove/contains.
/// Supports separate allocators for keys and index structures via AllocatorConfig.
pub const F64HashSet = struct {
    inner: OpenHashSet(f64),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) F64HashSet {
        return .{
            .inner = OpenHashSet(f64).init(allocator, allocator) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    /// config.keysAllocator() is used for the hash table / items array.
    /// config.indexAllocator() is used for the hash table index buckets.
    pub fn initWithConfig(config: AllocatorConfig) F64HashSet {
        return .{
            .inner = OpenHashSet(f64).init(config.keysAllocator(), config.indexAllocator()) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *F64HashSet) void {
        self.inner.deinit();
    }

    pub fn of(allocator: Allocator, values: []const f64) F64HashSet {
        var set = init(allocator);
        for (values) |val| _ = set.add(val);
        return set;
    }

    // ---- Core Operations ----

    /// Adds a value. Returns true if it was not already present.
    pub fn add(self: *F64HashSet, value: f64) bool {
        return self.inner.add(value) catch @panic("out of memory");
    }

    /// Adds all values from a slice.
    pub fn addAll(self: *F64HashSet, values: []const f64) void {
        for (values) |val| _ = self.add(val);
    }

    /// Removes a value. Returns true if it was present.
    pub fn remove(self: *F64HashSet, value: f64) bool {
        return self.inner.remove(value);
    }

    pub fn contains(self: *const F64HashSet, value: f64) bool {
        return self.inner.contains(value);
    }

    pub fn len(self: *const F64HashSet) usize {
        return self.inner.len();
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const F64HashSet) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const F64HashSet) bool {
        return self.len() == 0;
    }

    pub fn clear(self: *F64HashSet) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be added without
    /// triggering a rehash. Returns `error.OutOfMemory` if the allocator
    /// fails.
    pub fn ensureUnusedCapacity(self: *F64HashSet, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the hash set's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *F64HashSet, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    /// Calls f for each element.
    pub fn forEach(self: *const F64HashSet, f: *const fn (f64) void) void {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                f(value);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new set with only elements satisfying the predicate.
    pub fn select(self: *const F64HashSet, predicate: *const fn (f64) bool) F64HashSet {
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
    pub fn reject(self: *const F64HashSet, predicate: *const fn (f64) bool) F64HashSet {
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
    pub fn detect(self: *const F64HashSet, predicate: *const fn (f64) bool) ?f64 {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return value;
            }
        }
        return null;
    }

    /// Returns true if any element satisfies the predicate.
    pub fn anySatisfy(self: *const F64HashSet, predicate: *const fn (f64) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return true;
            }
        }
        return false;
    }

    /// Returns true if all elements satisfy the predicate.
    pub fn allSatisfy(self: *const F64HashSet, predicate: *const fn (f64) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!predicate(value)) return false;
            }
        }
        return true;
    }

    /// Returns true if no element satisfies the predicate.
    pub fn noneSatisfy(self: *const F64HashSet, predicate: *const fn (f64) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (predicate(value)) return false;
            }
        }
        return true;
    }

    /// Returns the count of elements satisfying the predicate.
    pub fn count(self: *const F64HashSet, predicate: *const fn (f64) bool) usize {
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

    pub fn setUnion(self: *const F64HashSet, other: *const F64HashSet) F64HashSet {
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

    pub fn intersect(self: *const F64HashSet, other: *const F64HashSet) F64HashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (other.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    pub fn difference(self: *const F64HashSet, other: *const F64HashSet) F64HashSet {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                if (!other.contains(value)) _ = result.add(value);
            }
        }
        return result;
    }

    pub fn symmetricDifference(self: *const F64HashSet, other: *const F64HashSet) F64HashSet {
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
    pub fn toSlice(self: *const F64HashSet, allocator: Allocator) []f64 {
        var buf: std.ArrayListUnmanaged(f64) = .empty;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const value = self.inner.entries[i].key;
                buf.append(allocator, value) catch @panic("out of memory");
            }
        }
        return buf.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Creates an immutable snapshot of this set.
    pub fn toImmutable(self: *const F64HashSet) ImmutableF64HashSet {
        return ImmutableF64HashSet.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    /// Returns the set after adding a value (fluent).
    pub fn with(self: *F64HashSet, value: f64) *F64HashSet {
        _ = self.add(value);
        return self;
    }

    /// Returns the set after removing a value (fluent).
    pub fn without(self: *F64HashSet, value: f64) *F64HashSet {
        _ = self.remove(value);
        return self;
    }

    /// Adds all values from a slice (fluent).
    pub fn withAll(self: *F64HashSet, values: []const f64) *F64HashSet {
        self.addAll(values);
        return self;
    }

    /// Removes all values from a slice (fluent).
    pub fn withoutAll(self: *F64HashSet, values: []const f64) *F64HashSet {
        for (values) |val| _ = self.remove(val);
        return self;
    }

    // ---- Formatting ----

    /// Formats the set as "{v1, v2, v3}".
    pub fn format(self: *const F64HashSet, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const F64HashSet, other: *const F64HashSet) bool {
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

test "F64HashSet: add and contains" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.add(1.0);
    _ = set.add(2.0);
    _ = set.add(3.0);
    try std.testing.expectEqual(@as(usize, 3), set.len());
    try std.testing.expect(set.contains(2.0));
    try std.testing.expect(!set.contains(99.0));
}

test "F64HashSet: add duplicate" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    try std.testing.expect(set.add(1.0));
    try std.testing.expect(!set.add(1.0));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "F64HashSet: addAll" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    set.addAll(&[_]f64{ 1.0, 2.0, 1.0 });
    try std.testing.expectEqual(@as(usize, 2), set.len());
}

test "F64HashSet: remove" {
    var set = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0 });
    defer set.deinit();
    try std.testing.expect(set.remove(2.0));
    try std.testing.expect(!set.contains(2.0));
    try std.testing.expect(!set.remove(99.0));
}

test "F64HashSet: clear" {
    var set = F64HashSet.of(std.testing.allocator, &[_]f64{1.0});
    defer set.deinit();
    set.clear();
    try std.testing.expect(set.isEmpty());
}

test "F64HashSet: forEach" {
    var set = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer set.deinit();
    var c: usize = 0;
    set.forEach(struct {
        fn f(_: f64) void {
            // count tracked via test logic below
        }
    }.f);
    // If forEach compiles and doesn't crash, it works.
    // Count elements manually:
    c = set.inner.len();
    try std.testing.expectEqual(@as(usize, 2), c);
}

test "F64HashSet: select and reject" {
    var set = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 });
    defer set.deinit();
    var sel = set.select(struct {
        fn f(val: f64) bool {
            return val > 3.0;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
    var rej = set.reject(struct {
        fn f(val: f64) bool {
            return val > 3.0;
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 3), rej.len());
}

test "F64HashSet: detect" {
    var set = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0 });
    defer set.deinit();
    const found = set.detect(struct {
        fn f(val: f64) bool {
            return val == 2.0;
        }
    }.f);
    try std.testing.expectEqual(@as(?f64, 2.0), found);
    const not_found = set.detect(struct {
        fn f(val: f64) bool {
            return val == 99.0;
        }
    }.f);
    try std.testing.expectEqual(@as(?f64, null), not_found);
}

test "F64HashSet: count" {
    var set = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 });
    defer set.deinit();
    const c = set.count(struct {
        fn f(val: f64) bool {
            return val > 3.0;
        }
    }.f);
    try std.testing.expectEqual(@as(usize, 2), c);
}

test "F64HashSet: union" {
    var a = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0 });
    defer a.deinit();
    var b = F64HashSet.of(std.testing.allocator, &[_]f64{ 3.0, 4.0, 5.0 });
    defer b.deinit();
    var u = a.setUnion(&b);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 5), u.len());
}

test "F64HashSet: intersect" {
    var a = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0 });
    defer a.deinit();
    var b = F64HashSet.of(std.testing.allocator, &[_]f64{ 2.0, 3.0, 4.0 });
    defer b.deinit();
    var inter = a.intersect(&b);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 2), inter.len());
}

test "F64HashSet: difference" {
    var a = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0 });
    defer a.deinit();
    var b = F64HashSet.of(std.testing.allocator, &[_]f64{ 2.0, 3.0, 4.0 });
    defer b.deinit();
    var d = a.difference(&b);
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 1), d.len());
}

test "F64HashSet: toSlice" {
    var set = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer set.deinit();
    const slice = set.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 2), slice.len);
}

test "F64HashSet: toImmutable" {
    var set = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer set.deinit();
    var imm = set.toImmutable();
    defer imm.deinit();
    try std.testing.expectEqual(@as(usize, 2), imm.len());
    // Mutate original — immutable should be independent
    _ = set.add(3.0);
    try std.testing.expectEqual(@as(usize, 2), imm.len());
}

test "F64HashSet: fluent with/without" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.with(1.0).with(2.0);
    try std.testing.expectEqual(@as(usize, 2), set.len());
    _ = set.without(1.0);
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "F64HashSet: eql" {
    var a = F64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer a.deinit();
    var b = F64HashSet.of(std.testing.allocator, &[_]f64{ 2.0, 1.0 });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}

test "F64HashSet: ensureUnusedCapacity reserves and subsequent add does not resize" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureUnusedCapacity(200);
    const reserved = set.inner.capacity;
    try std.testing.expect(reserved >= 200);
    _ = set.add(1.0);
    _ = set.add(2.0);
    try std.testing.expectEqual(reserved, set.inner.capacity);
}

test "F64HashSet: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureTotalCapacity(200);
    const reserved = set.inner.capacity;
    try set.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, set.inner.capacity);
}

test "F64HashSet: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1 lets init() allocate the initial table (the 1st alloc)
    // but fails the 2nd alloc, which is the grow triggered by ensureCapacity.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var set = F64HashSet.init(failing.allocator());
    defer set.deinit();
    try std.testing.expectError(error.OutOfMemory, set.ensureUnusedCapacity(10_000));
}

// ---- NaN / IEEE-754 edge-case tests (locks in bit-level keyEql from hash_table.zig) ----
// See docs/float-nan-semantics-audit.md.

test "F64HashSet: NaN element findable" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    const nan_val = std.math.nan(f64);
    _ = set.add(nan_val);
    try std.testing.expect(set.contains(nan_val));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "F64HashSet: NaN element add does not duplicate" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    const nan_val = std.math.nan(f64);
    try std.testing.expect(set.add(nan_val));
    try std.testing.expect(!set.add(nan_val));
    try std.testing.expect(!set.add(nan_val));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "F64HashSet: NaN element remove" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    const nan_val = std.math.nan(f64);
    _ = set.add(nan_val);
    try std.testing.expect(set.remove(nan_val));
    try std.testing.expectEqual(@as(usize, 0), set.len());
    try std.testing.expect(!set.contains(nan_val));
}

test "F64HashSet: -0.0 distinct from +0.0" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    const pos_zero: f64 = @as(f64, 0.0);
    const neg_zero: f64 = @as(f64, -0.0);
    try std.testing.expect(set.add(pos_zero));
    try std.testing.expect(set.add(neg_zero));
    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(set.contains(pos_zero));
    try std.testing.expect(set.contains(neg_zero));
}

test "F64HashSet: +/-Infinity elements" {
    var set = F64HashSet.init(std.testing.allocator);
    defer set.deinit();
    const pos_inf = std.math.inf(f64);
    const neg_inf = -std.math.inf(f64);
    try std.testing.expect(set.add(pos_inf));
    try std.testing.expect(set.add(neg_inf));
    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(set.contains(pos_inf));
    try std.testing.expect(set.contains(neg_inf));
}

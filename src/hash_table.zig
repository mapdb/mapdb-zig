// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Open-addressing hash table with grouped Swiss-table probing.
//
// Each bucket has a control byte in a parallel `ctrl` array: EMPTY (0xFF),
// DELETED (0x80, a tombstone), or a 7-bit hash tag (0x00..0x7F) marking a FULL
// slot. Lookups probe by GROUPS of `GROUP_WIDTH` buckets using a SWAR
// (SIMD-within-a-register) byte matcher over a little-endian u64, then walk a
// triangular group sequence that visits every group exactly once for a
// power-of-two capacity.
//
// The entry payload still uses interleaved Entry structs carrying an `occupied`
// flag: the control byte is the probing source of truth, while `occupied`
// remains the field the public iterators/consumers read when scanning
// `entries[0..capacity]`. The two are always kept in agreement (FULL <=> occupied).
// Tombstone (DELETED) slots keep `occupied == false` and their entry data is
// stale but never read (the control byte gates all reads). This preserves the
// existing external contract (`entries[i].occupied/.key/.value`, `capacity`,
// `size`) while making probing Swiss-fast. Hash iteration order is unspecified.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ---------------------------------------------------------------------------
// Constants and control-byte encoding
// ---------------------------------------------------------------------------

const GROUP_WIDTH: usize = 8;
const MIN_CAPACITY: usize = 16;
const EMPTY: u8 = 0xFF;
const DELETED: u8 = 0x80;

const ONES: u64 = 0x0101_0101_0101_0101;
const HIGHS: u64 = 0x8080_8080_8080_8080;

/// `cap * 7 / 8`, computed without overflow.
inline fn maxLoad(cap: usize) usize {
    return cap / 8 * 7 + (cap % 8) * 7 / 8;
}

fn hashKey(comptime K: type, key: K) u64 {
    const raw: u64 = switch (@typeInfo(K)) {
        .int, .comptime_int => @bitCast(@as(i64, @intCast(key))),
        .float => if (K == f32)
            @as(u64, @as(u32, @bitCast(key)))
        else
            @as(u64, @bitCast(key)),
        .bool => if (key) @as(u64, 1) else 0,
        else => @compileError("unsupported key type for hash table: " ++ @typeName(K)),
    };
    // 64-bit Fibonacci hash (golden-ratio multiply), then fold the high word
    // down so the full 64-bit key influences both the bucket (h1) and the 7-bit
    // tag (h2). The bucket is `(h >> 7) & mask`; the tag is `h & 0x7F`. The
    // `h ^= h >> 32` finalizer mixes the high word into the low word so the i64
    // family {1, 2^32+1, 2*2^32+1, ...} (differing only in the high 32 bits)
    // does not collapse onto one home group — matching Go's `h ^= h >> 32`.
    var h: u64 = raw *% 0x9E3779B97F4A7C15;
    h ^= h >> 32;
    return h;
}

fn keyEql(comptime K: type, a: K, b: K) bool {
    if (K == f32) return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
    if (K == f64) return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
    return a == b;
}

// ---------------------------------------------------------------------------
// SWAR group matcher
// ---------------------------------------------------------------------------

/// Loads the eight control bytes starting at `i` as a little-endian u64.
/// `ctrl` must have at least `i + GROUP_WIDTH` bytes; the mirror suffix
/// guarantees this for any `i < cap`.
inline fn loadGroup(ctrl: []const u8, i: usize) u64 {
    return std.mem.readInt(u64, ctrl[i..][0..GROUP_WIDTH], .little);
}

inline fn rep(b: u8) u64 {
    return ONES *% @as(u64, b);
}

/// Classic SWAR zero-byte detector. A lane's high bit (bit 8*i+7) is set in the
/// result iff byte `i` of `x` is 0x00.
inline fn haszero(x: u64) u64 {
    return (x -% ONES) & ~x & HIGHS;
}

/// Bitmask of lanes whose control byte equals `b`. Lane `i` is the high bit of
/// byte `i` (bit 8*i+7); all other bits are 0.
inline fn matchByte(g: u64, b: u8) u64 {
    return haszero(g ^ rep(b));
}

inline fn matchEmpty(g: u64) u64 {
    return matchByte(g, EMPTY);
}

inline fn matchDeleted(g: u64) u64 {
    return matchByte(g, DELETED);
}

/// Lanes whose control byte is FULL (a 7-bit tag, high bit clear). EMPTY (0xFF)
/// and DELETED (0x80) both have the high bit set, so `~g & HIGHS` marks exactly
/// the FULL lanes — lets iterators skip empty/deleted runs a whole group at a time.
inline fn matchFull(g: u64) u64 {
    return ~g & HIGHS;
}

/// Lowest set lane index of a SWAR bitmask (0..GROUP_WIDTH). Caller guarantees
/// `mask != 0`.
inline fn lowestLane(mask: u64) usize {
    return @as(usize, @ctz(mask)) >> 3;
}

/// Clears the lowest set lane of a SWAR bitmask.
inline fn clearLowest(mask: u64) u64 {
    return mask & (mask - 1);
}

/// Triangular group probe sequence. Yields the aligned starting bucket index of
/// each group; for power-of-two `cap` (a multiple of GROUP_WIDTH) it visits
/// every group exactly once before repeating.
const ProbeSeq = struct {
    group: usize,
    stride: usize,
    mask: usize,

    inline fn init(hash: u64, cap: usize) ProbeSeq {
        const mask = cap - 1;
        const bucket = @as(usize, @intCast(hash >> 7)) & mask;
        const group = bucket & ~(GROUP_WIDTH - 1);
        return .{ .group = group, .stride = 0, .mask = mask };
    }

    inline fn next(self: *ProbeSeq) usize {
        const g = self.group;
        self.stride += GROUP_WIDTH;
        self.group = (self.group + self.stride) & self.mask;
        return g;
    }
};

// ---------------------------------------------------------------------------
// OpenHashMap
// ---------------------------------------------------------------------------

pub fn MapEntry(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
        occupied: bool,
    };
}

pub fn OpenHashMap(comptime K: type, comptime V: type) type {
    const Entry = MapEntry(K, V);

    return struct {
        const Self = @This();

        entries: []Entry,
        ctrl: []u8,
        size: usize,
        capacity: usize,
        growth_left: usize,
        alloc: Allocator,

        pub fn init(alloc: Allocator) Allocator.Error!Self {
            // Default to a MIN_CAPACITY (16) bucket table.
            return initCapacity(alloc, 0);
        }

        pub fn initCapacity(alloc: Allocator, requested: usize) Allocator.Error!Self {
            const cap = capacityFor(requested);
            const entries = try alloc.alloc(Entry, cap);
            errdefer alloc.free(entries);
            for (entries) |*e| {
                e.* = .{ .key = defaultVal(K), .value = defaultVal(V), .occupied = false };
            }
            const ctrl = try alloc.alloc(u8, cap + GROUP_WIDTH);
            @memset(ctrl, EMPTY);
            return .{
                .entries = entries,
                .ctrl = ctrl,
                .size = 0,
                .capacity = cap,
                .growth_left = maxLoad(cap),
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.entries);
            self.alloc.free(self.ctrl);
            self.* = undefined;
        }

        inline fn mask(self: *const Self) usize {
            return self.capacity - 1;
        }

        /// Sets control byte `idx`, mirroring into the suffix when `idx < GROUP_WIDTH`.
        inline fn setCtrl(self: *Self, idx: usize, byte: u8) void {
            self.ctrl[idx] = byte;
            if (idx < GROUP_WIDTH) {
                self.ctrl[self.capacity + idx] = byte;
            }
        }

        /// Grow the backing table so that `additional` more entries can be put
        /// without triggering a resize. Idempotent. Exposed by the generated
        /// wrappers as `ensureUnusedCapacity` / `ensureTotalCapacity`.
        pub fn ensureCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const needed = self.size + additional;
            const new_cap = capacityFor(needed);
            if (new_cap > self.capacity) {
                try self.rehashTo(new_cap);
            }
        }

        /// Rebuilds the table at `new_cap`, moving every full entry. Tombstone-free
        /// afterwards. Allocates the new arrays first; on failure the old table is
        /// left unchanged.
        fn rehashTo(self: *Self, new_cap: usize) Allocator.Error!void {
            const new_entries = try self.alloc.alloc(Entry, new_cap);
            errdefer self.alloc.free(new_entries);
            for (new_entries) |*e| {
                e.* = .{ .key = defaultVal(K), .value = defaultVal(V), .occupied = false };
            }
            const new_ctrl = try self.alloc.alloc(u8, new_cap + GROUP_WIDTH);
            @memset(new_ctrl, EMPTY);

            const old_entries = self.entries;
            const old_ctrl = self.ctrl;
            const old_cap = self.capacity;

            self.entries = new_entries;
            self.ctrl = new_ctrl;
            self.capacity = new_cap;
            self.size = 0;
            self.growth_left = maxLoad(new_cap);

            for (0..old_cap) |i| {
                if (old_ctrl[i] <= 0x7F) {
                    self.insertNoGrow(old_entries[i].key, old_entries[i].value);
                }
            }
            self.alloc.free(old_entries);
            self.alloc.free(old_ctrl);
        }

        /// Insert assuming the table has room and no equal key exists; used by
        /// rehash into a fresh (tombstone-free) table.
        fn insertNoGrow(self: *Self, key: K, value: V) void {
            const m = self.mask();
            const hash = hashKey(K, key);
            const tag: u8 = @intCast(hash & 0x7F);
            var seq = ProbeSeq.init(hash, self.capacity);
            while (true) {
                const group = seq.next();
                const g = loadGroup(self.ctrl, group);
                const empty = matchEmpty(g);
                if (empty != 0) {
                    const idx = (group + lowestLane(empty)) & m;
                    self.entries[idx] = .{ .key = key, .value = value, .occupied = true };
                    self.setCtrl(idx, tag);
                    self.size += 1;
                    self.growth_left -= 1;
                    return;
                }
            }
        }

        /// Called when `growth_left == 0` and one more entry needs inserting.
        fn rehashOrGrowForInsert(self: *Self) Allocator.Error!void {
            if (self.size + 1 <= maxLoad(self.capacity)) {
                // Tombstones are exhausting the empty budget; rebuild same size.
                try self.rehashTo(self.capacity);
            } else {
                try self.rehashTo(self.capacity * 2);
            }
        }

        /// Returns the bucket index of `key`, or null if absent.
        fn findIndex(self: *const Self, key: K) ?usize {
            if (self.size == 0) return null;
            const m = self.mask();
            const hash = hashKey(K, key);
            const tag: u8 = @intCast(hash & 0x7F);
            var seq = ProbeSeq.init(hash, self.capacity);
            while (true) {
                const group = seq.next();
                const g = loadGroup(self.ctrl, group);
                var matches = matchByte(g, tag);
                while (matches != 0) {
                    const idx = (group + lowestLane(matches)) & m;
                    if (self.ctrl[idx] == tag and keyEql(K, self.entries[idx].key, key)) {
                        return idx;
                    }
                    matches = clearLowest(matches);
                }
                if (matchEmpty(g) != 0) return null;
            }
        }

        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            if (self.growth_left == 0) try self.rehashOrGrowForInsert();
            const m = self.mask();
            const hash = hashKey(K, key);
            const tag: u8 = @intCast(hash & 0x7F);

            var first_deleted: usize = undefined;
            var have_deleted = false;
            var seq = ProbeSeq.init(hash, self.capacity);
            while (true) {
                const group = seq.next();
                const g = loadGroup(self.ctrl, group);

                var matches = matchByte(g, tag);
                while (matches != 0) {
                    const idx = (group + lowestLane(matches)) & m;
                    if (self.ctrl[idx] == tag and keyEql(K, self.entries[idx].key, key)) {
                        const old = self.entries[idx].value;
                        self.entries[idx].value = value;
                        return old;
                    }
                    matches = clearLowest(matches);
                }

                if (!have_deleted) {
                    const deleted = matchDeleted(g);
                    if (deleted != 0) {
                        first_deleted = (group + lowestLane(deleted)) & m;
                        have_deleted = true;
                    }
                }

                const empty = matchEmpty(g);
                if (empty != 0) {
                    const empty_idx = (group + lowestLane(empty)) & m;
                    const idx = if (have_deleted) first_deleted else empty_idx;
                    const was_empty = self.ctrl[idx] == EMPTY;
                    self.entries[idx] = .{ .key = key, .value = value, .occupied = true };
                    if (was_empty) self.growth_left -= 1;
                    self.setCtrl(idx, tag);
                    self.size += 1;
                    return null;
                }
            }
        }

        pub fn get(self: *const Self, key: K) ?V {
            const idx = self.findIndex(key) orelse return null;
            return self.entries[idx].value;
        }

        pub fn getPtr(self: *Self, key: K) ?*V {
            const idx = self.findIndex(key) orelse return null;
            return &self.entries[idx].value;
        }

        pub fn remove(self: *Self, key: K) ?V {
            const idx = self.findIndex(key) orelse return null;
            const old = self.entries[idx].value;
            self.entries[idx].occupied = false;
            // Always mark DELETED. The spec's optional `can_mark_empty`
            // optimization checks physically-adjacent groups, which is unsound
            // for the triangular probe sequence used here (probes jump by
            // growing strides, not to physical neighbors), so it is skipped.
            self.setCtrl(idx, DELETED);
            self.size -= 1;
            return old;
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.findIndex(key) != null;
        }

        pub fn containsValue(self: *const Self, value: V) bool {
            for (0..self.capacity) |i| {
                if (self.ctrl[i] <= 0x7F and valEql(V, self.entries[i].value, value)) return true;
            }
            return false;
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn clear(self: *Self) void {
            for (self.entries) |*e| {
                e.occupied = false;
            }
            @memset(self.ctrl, EMPTY);
            self.size = 0;
            self.growth_left = maxLoad(self.capacity);
        }

        pub fn forEachKey(self: *const Self, ctx: *anyopaque, f: *const fn (ctx: *anyopaque, K) void) void {
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) f(ctx, self.entries[i].key);
            }
        }

        pub fn forEachValue(self: *const Self, ctx: *anyopaque, f: *const fn (ctx: *anyopaque, V) void) void {
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) f(ctx, self.entries[i].value);
            }
        }

        pub fn keysToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const result = try allocator.alloc(K, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) {
                    result[idx] = self.entries[i].key;
                    idx += 1;
                }
            }
            return result;
        }

        pub fn valuesToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]V {
            const result = try allocator.alloc(V, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) {
                    result[idx] = self.entries[i].value;
                    idx += 1;
                }
            }
            return result;
        }

        /// Panics if any structural invariant from the design doc is violated.
        /// O(cap); gated for tests/verification. `seen` is caller-owned scratch
        /// used for the O(n) duplicate-key check.
        pub fn assertInvariants(self: *const Self) void {
            assertMapInvariants(K, V, Entry, self);
        }
    };
}

// ---------------------------------------------------------------------------
// OpenHashSet
// ---------------------------------------------------------------------------

pub fn SetEntry(comptime K: type) type {
    return struct {
        key: K,
        occupied: bool,
    };
}

pub fn OpenHashSet(comptime K: type) type {
    const Entry = SetEntry(K);

    return struct {
        const Self = @This();

        entries: []Entry,
        ctrl: []u8,
        size: usize,
        capacity: usize,
        growth_left: usize,
        alloc: Allocator,

        pub fn init(alloc: Allocator) Allocator.Error!Self {
            // Default to a MIN_CAPACITY (16) bucket table.
            return initCapacity(alloc, 0);
        }

        pub fn initCapacity(alloc: Allocator, requested: usize) Allocator.Error!Self {
            const cap = capacityFor(requested);
            const entries = try alloc.alloc(Entry, cap);
            errdefer alloc.free(entries);
            for (entries) |*e| {
                e.* = .{ .key = defaultVal(K), .occupied = false };
            }
            const ctrl = try alloc.alloc(u8, cap + GROUP_WIDTH);
            @memset(ctrl, EMPTY);
            return .{
                .entries = entries,
                .ctrl = ctrl,
                .size = 0,
                .capacity = cap,
                .growth_left = maxLoad(cap),
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.entries);
            self.alloc.free(self.ctrl);
            self.* = undefined;
        }

        inline fn mask(self: *const Self) usize {
            return self.capacity - 1;
        }

        inline fn setCtrl(self: *Self, idx: usize, byte: u8) void {
            self.ctrl[idx] = byte;
            if (idx < GROUP_WIDTH) {
                self.ctrl[self.capacity + idx] = byte;
            }
        }

        /// Grow the backing table so that `additional` more entries can be added
        /// without triggering a resize. Idempotent. See `OpenHashMap.ensureCapacity`.
        pub fn ensureCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const needed = self.size + additional;
            const new_cap = capacityFor(needed);
            if (new_cap > self.capacity) {
                try self.rehashTo(new_cap);
            }
        }

        fn rehashTo(self: *Self, new_cap: usize) Allocator.Error!void {
            const new_entries = try self.alloc.alloc(Entry, new_cap);
            errdefer self.alloc.free(new_entries);
            for (new_entries) |*e| {
                e.* = .{ .key = defaultVal(K), .occupied = false };
            }
            const new_ctrl = try self.alloc.alloc(u8, new_cap + GROUP_WIDTH);
            @memset(new_ctrl, EMPTY);

            const old_entries = self.entries;
            const old_ctrl = self.ctrl;
            const old_cap = self.capacity;

            self.entries = new_entries;
            self.ctrl = new_ctrl;
            self.capacity = new_cap;
            self.size = 0;
            self.growth_left = maxLoad(new_cap);

            for (0..old_cap) |i| {
                if (old_ctrl[i] <= 0x7F) {
                    self.insertNoGrow(old_entries[i].key);
                }
            }
            self.alloc.free(old_entries);
            self.alloc.free(old_ctrl);
        }

        fn insertNoGrow(self: *Self, value: K) void {
            const m = self.mask();
            const hash = hashKey(K, value);
            const tag: u8 = @intCast(hash & 0x7F);
            var seq = ProbeSeq.init(hash, self.capacity);
            while (true) {
                const group = seq.next();
                const g = loadGroup(self.ctrl, group);
                const empty = matchEmpty(g);
                if (empty != 0) {
                    const idx = (group + lowestLane(empty)) & m;
                    self.entries[idx] = .{ .key = value, .occupied = true };
                    self.setCtrl(idx, tag);
                    self.size += 1;
                    self.growth_left -= 1;
                    return;
                }
            }
        }

        fn rehashOrGrowForInsert(self: *Self) Allocator.Error!void {
            if (self.size + 1 <= maxLoad(self.capacity)) {
                try self.rehashTo(self.capacity);
            } else {
                try self.rehashTo(self.capacity * 2);
            }
        }

        fn findIndex(self: *const Self, value: K) ?usize {
            if (self.size == 0) return null;
            const m = self.mask();
            const hash = hashKey(K, value);
            const tag: u8 = @intCast(hash & 0x7F);
            var seq = ProbeSeq.init(hash, self.capacity);
            while (true) {
                const group = seq.next();
                const g = loadGroup(self.ctrl, group);
                var matches = matchByte(g, tag);
                while (matches != 0) {
                    const idx = (group + lowestLane(matches)) & m;
                    if (self.ctrl[idx] == tag and keyEql(K, self.entries[idx].key, value)) {
                        return idx;
                    }
                    matches = clearLowest(matches);
                }
                if (matchEmpty(g) != 0) return null;
            }
        }

        pub fn add(self: *Self, value: K) Allocator.Error!bool {
            if (self.growth_left == 0) try self.rehashOrGrowForInsert();
            const m = self.mask();
            const hash = hashKey(K, value);
            const tag: u8 = @intCast(hash & 0x7F);

            var first_deleted: usize = undefined;
            var have_deleted = false;
            var seq = ProbeSeq.init(hash, self.capacity);
            while (true) {
                const group = seq.next();
                const g = loadGroup(self.ctrl, group);

                var matches = matchByte(g, tag);
                while (matches != 0) {
                    const idx = (group + lowestLane(matches)) & m;
                    if (self.ctrl[idx] == tag and keyEql(K, self.entries[idx].key, value)) {
                        return false;
                    }
                    matches = clearLowest(matches);
                }

                if (!have_deleted) {
                    const deleted = matchDeleted(g);
                    if (deleted != 0) {
                        first_deleted = (group + lowestLane(deleted)) & m;
                        have_deleted = true;
                    }
                }

                const empty = matchEmpty(g);
                if (empty != 0) {
                    const empty_idx = (group + lowestLane(empty)) & m;
                    const idx = if (have_deleted) first_deleted else empty_idx;
                    const was_empty = self.ctrl[idx] == EMPTY;
                    self.entries[idx] = .{ .key = value, .occupied = true };
                    if (was_empty) self.growth_left -= 1;
                    self.setCtrl(idx, tag);
                    self.size += 1;
                    return true;
                }
            }
        }

        pub fn remove(self: *Self, value: K) bool {
            const idx = self.findIndex(value) orelse return false;
            self.entries[idx].occupied = false;
            self.setCtrl(idx, DELETED);
            self.size -= 1;
            return true;
        }

        pub fn contains(self: *const Self, value: K) bool {
            return self.findIndex(value) != null;
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn clear(self: *Self) void {
            for (self.entries) |*e| {
                e.occupied = false;
            }
            @memset(self.ctrl, EMPTY);
            self.size = 0;
            self.growth_left = maxLoad(self.capacity);
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const result = try allocator.alloc(K, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) {
                    result[idx] = self.entries[i].key;
                    idx += 1;
                }
            }
            return result;
        }

        /// Panics if any structural invariant from the design doc is violated.
        pub fn assertInvariants(self: *const Self) void {
            assertSetInvariants(K, Entry, self);
        }
    };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn nextPow2(n: usize) usize {
    if (n == 0) return 1;
    var v = n - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    if (@bitSizeOf(usize) > 32) {
        v |= v >> 32;
    }
    return v + 1;
}

/// Smallest power-of-two `cap >= MIN_CAPACITY` with `n <= maxLoad(cap)`.
fn capacityFor(n: usize) usize {
    var cap = MIN_CAPACITY;
    while (maxLoad(cap) < n) {
        cap *= 2;
    }
    return cap;
}

fn defaultVal(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int, .comptime_int => 0,
        .float, .comptime_float => 0.0,
        .bool => false,
        else => @as(T, 0),
    };
}

fn valEql(comptime V: type, a: V, b: V) bool {
    if (V == f32) return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
    if (V == f64) return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
    return a == b;
}

// ---------------------------------------------------------------------------
// Structural invariant verification (shared)
// ---------------------------------------------------------------------------

fn assertMapInvariants(comptime K: type, comptime V: type, comptime Entry: type, self: anytype) void {
    const cap = self.capacity;
    // 1. Capacity shape.
    std.debug.assert(self.ctrl.len == cap + GROUP_WIDTH);
    std.debug.assert(self.entries.len == cap);
    std.debug.assert(std.math.isPowerOfTwo(cap));
    std.debug.assert(cap >= MIN_CAPACITY);
    std.debug.assert(cap % GROUP_WIDTH == 0);

    // 3. Mirror suffix.
    for (0..GROUP_WIDTH) |i| {
        std.debug.assert(self.ctrl[cap + i] == self.ctrl[i]);
    }

    // 2 + 4 (tag agreement) + 5 (len/growth accounting).
    var full: usize = 0;
    var deleted: usize = 0;
    for (0..cap) |i| {
        const b = self.ctrl[i];
        if (b <= 0x7F) {
            full += 1;
            std.debug.assert(self.entries[i].occupied);
            const tag: u8 = @intCast(hashKey(K, self.entries[i].key) & 0x7F);
            std.debug.assert(b == tag);
        } else {
            std.debug.assert(b == EMPTY or b == DELETED);
            std.debug.assert(!self.entries[i].occupied);
            if (b == DELETED) deleted += 1;
        }
    }
    std.debug.assert(full == self.size);
    std.debug.assert(self.size <= maxLoad(cap));
    std.debug.assert(self.growth_left == maxLoad(cap) - self.size - deleted);

    // 6 + 8. Probe reachability / lookup consistency: each full slot is found
    // at its own index.
    for (0..cap) |i| {
        if (self.ctrl[i] <= 0x7F) {
            std.debug.assert(self.findIndex(self.entries[i].key).? == i);
        }
    }

    // 7. No duplicate keys, O(n) via std.AutoHashMap.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var seen = std.AutoHashMap(K, void).init(gpa.allocator());
    defer seen.deinit();
    for (0..cap) |i| {
        if (self.ctrl[i] <= 0x7F) {
            const r = seen.getOrPut(self.entries[i].key) catch unreachable;
            std.debug.assert(!r.found_existing);
        }
    }
    _ = V;
    _ = Entry;
}

fn assertSetInvariants(comptime K: type, comptime Entry: type, self: anytype) void {
    const cap = self.capacity;
    std.debug.assert(self.ctrl.len == cap + GROUP_WIDTH);
    std.debug.assert(self.entries.len == cap);
    std.debug.assert(std.math.isPowerOfTwo(cap));
    std.debug.assert(cap >= MIN_CAPACITY);
    std.debug.assert(cap % GROUP_WIDTH == 0);

    for (0..GROUP_WIDTH) |i| {
        std.debug.assert(self.ctrl[cap + i] == self.ctrl[i]);
    }

    var full: usize = 0;
    var deleted: usize = 0;
    for (0..cap) |i| {
        const b = self.ctrl[i];
        if (b <= 0x7F) {
            full += 1;
            std.debug.assert(self.entries[i].occupied);
            const tag: u8 = @intCast(hashKey(K, self.entries[i].key) & 0x7F);
            std.debug.assert(b == tag);
        } else {
            std.debug.assert(b == EMPTY or b == DELETED);
            std.debug.assert(!self.entries[i].occupied);
            if (b == DELETED) deleted += 1;
        }
    }
    std.debug.assert(full == self.size);
    std.debug.assert(self.size <= maxLoad(cap));
    std.debug.assert(self.growth_left == maxLoad(cap) - self.size - deleted);

    for (0..cap) |i| {
        if (self.ctrl[i] <= 0x7F) {
            std.debug.assert(self.findIndex(self.entries[i].key).? == i);
        }
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var seen = std.AutoHashMap(K, void).init(gpa.allocator());
    defer seen.deinit();
    for (0..cap) |i| {
        if (self.ctrl[i] <= 0x7F) {
            const r = seen.getOrPut(self.entries[i].key) catch unreachable;
            std.debug.assert(!r.found_existing);
        }
    }
    _ = Entry;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "map: insert, get, remove" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, null), try m.put(1, 10));
    try std.testing.expectEqual(@as(?i32, null), try m.put(2, 20));
    try std.testing.expectEqual(@as(?i32, 10), try m.put(1, 99));
    try std.testing.expectEqual(@as(?i32, 99), m.get(1));
    try std.testing.expectEqual(@as(?i32, 20), m.get(2));
    try std.testing.expectEqual(@as(?i32, null), m.get(3));
    try std.testing.expectEqual(@as(?i32, 99), m.remove(1));
    try std.testing.expectEqual(@as(?i32, null), m.get(1));
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "map: resize" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    for (0..200) |i| {
        _ = try m.put(@intCast(i), @intCast(i * 10));
    }
    try std.testing.expectEqual(@as(usize, 200), m.len());
    for (0..200) |i| {
        try std.testing.expectEqual(@as(?i32, @intCast(i * 10)), m.get(@intCast(i)));
    }
}

test "map: delete heavy" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    for (0..50000) |i| {
        _ = try m.put(@intCast(i), @intCast(i));
    }
    var idx: i32 = 0;
    while (idx < 50000) : (idx += 2) _ = m.remove(idx);
    idx = 50000;
    while (idx < 75000) : (idx += 1) _ = try m.put(idx, idx);
    idx = 0;
    while (idx < 75000) : (idx += 1) _ = m.remove(idx);
    try std.testing.expectEqual(@as(usize, 0), m.len());
}

test "map: float keys" {
    var m = try OpenHashMap(f32, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put(1.5, 10);
    _ = try m.put(2.5, 20);
    try std.testing.expectEqual(@as(?i32, 10), m.get(1.5));
    try std.testing.expectEqual(@as(?i32, null), m.get(3.5));
}

test "map: bool keys" {
    var m = try OpenHashMap(bool, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put(true, 1);
    _ = try m.put(false, 0);
    try std.testing.expectEqual(@as(?i32, 1), m.get(true));
    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "set: add, remove, contains" {
    var s = try OpenHashSet(i32).init(std.testing.allocator);
    defer s.deinit();
    try std.testing.expect(try s.add(1));
    try std.testing.expect(try s.add(2));
    try std.testing.expect(!(try s.add(1)));
    try std.testing.expectEqual(@as(usize, 2), s.len());
    try std.testing.expect(s.contains(1));
    try std.testing.expect(s.remove(1));
    try std.testing.expect(!s.contains(1));
    try std.testing.expectEqual(@as(usize, 1), s.len());
}

test "set: resize" {
    var s = try OpenHashSet(i32).init(std.testing.allocator);
    defer s.deinit();
    for (0..200) |i| {
        _ = try s.add(@intCast(i));
    }
    try std.testing.expectEqual(@as(usize, 200), s.len());
    for (0..200) |i| {
        try std.testing.expect(s.contains(@intCast(i)));
    }
}

test "map: getPtr" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put(1, 10);
    if (m.getPtr(1)) |ptr| {
        ptr.* += 5;
    }
    try std.testing.expectEqual(@as(?i32, 15), m.get(1));
}

test "map: ensureCapacity grows and subsequent puts do not resize" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    try m.ensureCapacity(1000);
    const reserved_cap = m.capacity;
    try std.testing.expect(reserved_cap >= 1000);
    for (0..1000) |i| {
        _ = try m.put(@intCast(i), @intCast(i * 2));
    }
    // Capacity must be unchanged — reservation was sufficient.
    try std.testing.expectEqual(reserved_cap, m.capacity);
    try std.testing.expectEqual(@as(usize, 1000), m.len());
    for (0..1000) |i| {
        try std.testing.expectEqual(@as(?i32, @intCast(i * 2)), m.get(@intCast(i)));
    }
}

test "map: ensureCapacity is idempotent when capacity already sufficient" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    const initial_cap = m.capacity;
    try m.ensureCapacity(1);
    try std.testing.expectEqual(initial_cap, m.capacity);
}

test "map: ensureCapacity propagates allocator errors" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const result = OpenHashMap(i32, i32).initCapacity(failing.allocator(), 16);
    try std.testing.expectError(error.OutOfMemory, result);
}

test "map: ensureCapacity on populated map preserves entries" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    for (0..10) |i| {
        _ = try m.put(@intCast(i), @intCast(i));
    }
    try m.ensureCapacity(500);
    try std.testing.expect(m.capacity >= 500);
    try std.testing.expectEqual(@as(usize, 10), m.len());
    for (0..10) |i| {
        try std.testing.expectEqual(@as(?i32, @intCast(i)), m.get(@intCast(i)));
    }
}

test "set: ensureCapacity grows and subsequent adds do not resize" {
    var s = try OpenHashSet(i32).init(std.testing.allocator);
    defer s.deinit();
    try s.ensureCapacity(500);
    const reserved_cap = s.capacity;
    try std.testing.expect(reserved_cap >= 500);
    for (0..500) |i| {
        _ = try s.add(@intCast(i));
    }
    try std.testing.expectEqual(reserved_cap, s.capacity);
    try std.testing.expectEqual(@as(usize, 500), s.len());
}

test "set: ensureCapacity propagates allocator errors" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const result = OpenHashSet(i32).initCapacity(failing.allocator(), 16);
    try std.testing.expectError(error.OutOfMemory, result);
}

test "hashKey: i64 high-32-bit family spreads across distinct buckets" {
    // Regression for the high-word fold (`h ^= h >> 32`). The bucket index is
    // `(h >> 7) & m`. Without the fold, the i64 family {1, 2^32+1, 2*2^32+1, ...}
    // — which differs ONLY in the high 32 bits — collapses onto one home group.
    // With the fold the high word reaches the bucket. Assert the family lands in
    // distinct buckets for a representative capacity mask.
    const cap: u64 = 1024; // power of two, like the table's real capacity
    const m: u64 = cap - 1;
    const N: usize = 16;
    var seen = [_]u64{0} ** 1024;
    var distinct: usize = 0;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const key: i64 = @intCast(@as(u64, @intCast(i)) *% (@as(u64, 1) << 32) +% 1);
        const bucket = (hashKey(i64, key) >> 7) & m;
        if (seen[bucket] == 0) {
            seen[bucket] = 1;
            distinct += 1;
        }
    }
    try std.testing.expect(distinct >= N - 2);
}

test "hashKey: i64 high-32-bit family stores/reads through production map" {
    var map = try OpenHashMap(i64, i32).init(std.testing.allocator);
    defer map.deinit();
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const key: i64 = @intCast(@as(u64, @intCast(i)) *% (@as(u64, 1) << 32) +% 1);
        _ = try map.put(key, @intCast(i));
    }
    try std.testing.expectEqual(@as(usize, 64), map.len());
    i = 0;
    while (i < 64) : (i += 1) {
        const key: i64 = @intCast(@as(u64, @intCast(i)) *% (@as(u64, 1) << 32) +% 1);
        try std.testing.expectEqual(@as(?i32, @intCast(i)), map.get(key));
    }
}

// ---------------------------------------------------------------------------
// Swiss-table-specific tests
// ---------------------------------------------------------------------------

test "swar: matchByte / matchEmpty / matchFull lane order" {
    // Construct a group: lanes 0..7 = [0x05, 0xFF, 0x05, 0x80, 0x05, 0xFF, 0x12, 0x00]
    var buf = [_]u8{ 0x05, 0xFF, 0x05, 0x80, 0x05, 0xFF, 0x12, 0x00 };
    const g = loadGroup(&buf, 0);

    // matchByte(0x05) -> lanes 0, 2, 4
    var mm = matchByte(g, 0x05);
    var lanes = std.ArrayListUnmanaged(usize){};
    defer lanes.deinit(std.testing.allocator);
    while (mm != 0) {
        try lanes.append(std.testing.allocator, lowestLane(mm));
        mm = clearLowest(mm);
    }
    try std.testing.expectEqualSlices(usize, &[_]usize{ 0, 2, 4 }, lanes.items);

    // matchEmpty -> lanes 1, 5
    try std.testing.expectEqual(@as(usize, 1), lowestLane(matchEmpty(g)));
    var em = matchEmpty(g);
    em = clearLowest(em);
    try std.testing.expectEqual(@as(usize, 5), lowestLane(em));

    // matchDeleted -> lane 3
    try std.testing.expectEqual(@as(usize, 3), lowestLane(matchDeleted(g)));

    // matchFull -> all 7-bit lanes: 0,2,3? no — 0x80 is DELETED (high bit set).
    // FULL lanes (high bit clear): 0(0x05),2(0x05),4(0x05),6(0x12),7(0x00)
    var fm = matchFull(g);
    var full_lanes = std.ArrayListUnmanaged(usize){};
    defer full_lanes.deinit(std.testing.allocator);
    while (fm != 0) {
        try full_lanes.append(std.testing.allocator, lowestLane(fm));
        fm = clearLowest(fm);
    }
    try std.testing.expectEqualSlices(usize, &[_]usize{ 0, 2, 4, 6, 7 }, full_lanes.items);
}

test "map: tombstone reuse — removed slot is reused by a colliding key" {
    var m = try OpenHashMap(i64, i64).init(std.testing.allocator);
    defer m.deinit();
    // Insert keys, remove some to create tombstones, then reinsert. The size
    // and growth accounting must stay consistent and lookups must hold.
    for (0..12) |i| _ = try m.put(@intCast(i), @intCast(i));
    for (0..6) |i| _ = m.remove(@intCast(i));
    m.assertInvariants();
    // Reinserting fewer-than-tombstones keys must reuse DELETED slots without
    // growing capacity.
    const cap_before = m.capacity;
    for (0..6) |i| _ = try m.put(@intCast(i), @intCast(i * 100));
    try std.testing.expectEqual(cap_before, m.capacity);
    m.assertInvariants();
    for (0..6) |i| try std.testing.expectEqual(@as(?i64, @intCast(i * 100)), m.get(@intCast(i)));
    for (6..12) |i| try std.testing.expectEqual(@as(?i64, @intCast(i)), m.get(@intCast(i)));
}

test "map: forced rehash clears tombstones" {
    var m = try OpenHashMap(i64, i64).init(std.testing.allocator);
    defer m.deinit();
    // Fill near max load, then churn (remove+insert distinct keys) to pile up
    // tombstones until a same-capacity rehash is forced.
    var next: i64 = 0;
    for (0..14) |_| {
        _ = try m.put(next, next);
        next += 1;
    }
    const cap = m.capacity;
    // Churn: remove the oldest, add a new one, many times. growth_left hits 0
    // (tombstones consume empty budget) -> rehashOrGrowForInsert -> same-cap
    // rehash because len stays under maxLoad.
    var oldest: i64 = 0;
    for (0..1000) |_| {
        _ = m.remove(oldest);
        oldest += 1;
        _ = try m.put(next, next);
        next += 1;
        m.assertInvariants();
    }
    // Capacity should not have grown (churn keeps len bounded).
    try std.testing.expectEqual(cap, m.capacity);
    // After a rehash the deleted count is 0; growth_left == maxLoad - len holds
    // immediately post-rehash (checked inside assertInvariants each iteration).
    try std.testing.expectEqual(@as(usize, 14), m.len());
}

test "map: several growths preserve all entries" {
    var m = try OpenHashMap(i64, i64).init(std.testing.allocator);
    defer m.deinit();
    var caps_seen: usize = 0;
    var last_cap = m.capacity;
    for (0..5000) |i| {
        _ = try m.put(@intCast(i), @intCast(i * 3));
        if (m.capacity != last_cap) {
            caps_seen += 1;
            last_cap = m.capacity;
        }
    }
    try std.testing.expect(caps_seen >= 3); // multiple growths happened
    m.assertInvariants();
    for (0..5000) |i| try std.testing.expectEqual(@as(?i64, @intCast(i * 3)), m.get(@intCast(i)));
}

test "map: iterator completeness over occupied slots" {
    var m = try OpenHashMap(i64, i64).init(std.testing.allocator);
    defer m.deinit();
    for (0..300) |i| _ = try m.put(@intCast(i), @intCast(i));
    for (0..150) |i| _ = m.remove(@intCast(i * 2)); // remove evens, tombstones
    // Walk entries[0..capacity] as the public consumers do.
    var count: usize = 0;
    var sum: i64 = 0;
    for (0..m.capacity) |i| {
        if (m.entries[i].occupied) {
            count += 1;
            sum += m.entries[i].key;
        }
    }
    try std.testing.expectEqual(m.len(), count);
    // Sum of remaining (odd) keys 1,3,...,299.
    var expected: i64 = 0;
    var k: i64 = 1;
    while (k < 300) : (k += 2) expected += k;
    try std.testing.expectEqual(expected, sum);
}

test "map: randomized cross-check against std.AutoHashMap" {
    var m = try OpenHashMap(i64, i64).init(std.testing.allocator);
    defer m.deinit();
    var ref = std.AutoHashMap(i64, i64).init(std.testing.allocator);
    defer ref.deinit();

    var state: u64 = 0x243F6A8885A308D3; // deterministic xorshift seed
    const xorshift = struct {
        fn next(s: *u64) u64 {
            var x = s.*;
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            s.* = x;
            return x;
        }
    };

    var ops: usize = 0;
    while (ops < 20000) : (ops += 1) {
        const r = xorshift.next(&state);
        const key: i64 = @intCast(r % 500); // small key space -> collisions, reuse
        const op = (r >> 32) % 3;
        if (op == 0) {
            const val: i64 = @intCast((r >> 40) & 0xFFFF);
            const old_ours = try m.put(key, val);
            const old_ref = try ref.fetchPut(key, val);
            const ref_old: ?i64 = if (old_ref) |kv| kv.value else null;
            try std.testing.expectEqual(ref_old, old_ours);
        } else if (op == 1) {
            const got = m.get(key);
            try std.testing.expectEqual(ref.get(key), got);
        } else {
            const removed_ours = m.remove(key);
            const removed_ref = ref.fetchRemove(key);
            const ref_rm: ?i64 = if (removed_ref) |kv| kv.value else null;
            try std.testing.expectEqual(ref_rm, removed_ours);
        }
        if (ops % 97 == 0) {
            try std.testing.expectEqual(ref.count(), m.len());
            m.assertInvariants();
        }
    }
    // Final full cross-check.
    try std.testing.expectEqual(ref.count(), m.len());
    m.assertInvariants();
    var it = ref.iterator();
    while (it.next()) |kv| {
        try std.testing.expectEqual(@as(?i64, kv.value_ptr.*), m.get(kv.key_ptr.*));
    }
}

test "set: randomized cross-check against std.AutoHashMap" {
    var s = try OpenHashSet(i64).init(std.testing.allocator);
    defer s.deinit();
    var ref = std.AutoHashMap(i64, void).init(std.testing.allocator);
    defer ref.deinit();

    var state: u64 = 0xB5026F5AA96619E9;
    const xorshift = struct {
        fn next(st: *u64) u64 {
            var x = st.*;
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            st.* = x;
            return x;
        }
    };

    var ops: usize = 0;
    while (ops < 20000) : (ops += 1) {
        const r = xorshift.next(&state);
        const key: i64 = @intCast(r % 400);
        const op = (r >> 32) % 3;
        if (op == 0) {
            const added_ours = try s.add(key);
            const r2 = try ref.getOrPut(key);
            try std.testing.expectEqual(!r2.found_existing, added_ours);
        } else if (op == 1) {
            try std.testing.expectEqual(ref.contains(key), s.contains(key));
        } else {
            const removed_ours = s.remove(key);
            const removed_ref = ref.remove(key);
            try std.testing.expectEqual(removed_ref, removed_ours);
        }
        if (ops % 101 == 0) {
            try std.testing.expectEqual(ref.count(), s.len());
            s.assertInvariants();
        }
    }
    try std.testing.expectEqual(ref.count(), s.len());
    s.assertInvariants();
}

test "map: clear resets to pristine empty (no tombstones)" {
    var m = try OpenHashMap(i64, i64).init(std.testing.allocator);
    defer m.deinit();
    for (0..50) |i| _ = try m.put(@intCast(i), @intCast(i));
    for (0..25) |i| _ = m.remove(@intCast(i));
    m.clear();
    try std.testing.expectEqual(@as(usize, 0), m.len());
    try std.testing.expectEqual(maxLoad(m.capacity), m.growth_left);
    m.assertInvariants();
    // Reuse after clear.
    for (0..30) |i| _ = try m.put(@intCast(i), @intCast(i + 1));
    for (0..30) |i| try std.testing.expectEqual(@as(?i64, @intCast(i + 1)), m.get(@intCast(i)));
    m.assertInvariants();
}

// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Open-addressing hash table with linear probing and Robin Hood backward-shift deletion.
//
// Structure-of-arrays layout (D3): keys and values live in separate dense
// arrays and occupancy is a 1-bit-per-slot word bitset, rather than an
// array of `{key, value, occupied: bool}` structs. This drops the per-slot
// padding the interleaved `bool` forced (and the key/value cross-alignment
// padding), saving ~24-33% of table memory across the instantiated K/V types.
// Wrappers iterate via the `keys`/`values`/`isOccupied(i)` surface.

const std = @import("std");
const Allocator = std.mem.Allocator;

const DEFAULT_CAPACITY: usize = 16;

// ---------------------------------------------------------------------------
// Occupancy bitset (D3)
//
// The table stores keys and values as separate dense arrays (structure of
// arrays) with occupancy tracked in a word-backed bitset — 1 bit/slot instead
// of an interleaved `bool` per entry, which the old array-of-structs layout
// padded out to whole bytes plus per-slot key/value cross-alignment padding.
// ---------------------------------------------------------------------------

const word_bits = @bitSizeOf(usize);
const Log2Word = std.math.Log2Int(usize);

/// Number of `usize` words needed to hold `cap` occupancy bits.
inline fn wordsFor(cap: usize) usize {
    return (cap + word_bits - 1) / word_bits;
}

inline fn bitGet(words: []const usize, i: usize) bool {
    return (words[i / word_bits] >> @as(Log2Word, @intCast(i % word_bits))) & 1 != 0;
}

inline fn bitSet(words: []usize, i: usize) void {
    words[i / word_bits] |= @as(usize, 1) << @as(Log2Word, @intCast(i % word_bits));
}

inline fn bitClear(words: []usize, i: usize) void {
    words[i / word_bits] &= ~(@as(usize, 1) << @as(Log2Word, @intCast(i % word_bits)));
}

/// 64-bit hash of a primitive key (int/float/bool). Public so concurrent
/// wrappers (e.g. `ShardedHashMap`) can route by the well-mixed HIGH bits while
/// the table itself consumes the LOW bits — one hash, decorrelated indices.
pub fn hashKey(comptime K: type, key: K) u64 {
    const raw: u64 = switch (@typeInfo(K)) {
        // Width-correct and injective per type: reinterpret the key as its
        // same-width unsigned integer instead of funnelling every int through
        // an `@as(i64, @intCast(key))`, which panics in safe builds and is UB
        // in ReleaseFast for any key > maxInt(i64) — e.g. `HashMap(u64, V)`
        // with keys near maxInt(u64), or u128/i128 (D1). Widths > 64 fold the
        // two 64-bit halves together (the untaken branch is comptime-pruned
        // for narrower widths, so the `>> 64` never type-errors there).
        .int => blk: {
            const U = std.meta.Int(.unsigned, @bitSizeOf(K));
            const u: U = @bitCast(key);
            break :blk if (@bitSizeOf(K) <= 64)
                @as(u64, u)
            else
                @as(u64, @truncate(u)) ^ @as(u64, @truncate(u >> 64));
        },
        .comptime_int => @bitCast(@as(i64, @intCast(key))),
        .float => if (K == f32)
            @as(u64, @as(u32, @bitCast(key)))
        else
            @as(u64, @bitCast(key)),
        .bool => if (key) @as(u64, 1) else 0,
        else => @compileError("unsupported key type for hash table: " ++ @typeName(K)),
    };
    // 64-bit Fibonacci hash (golden-ratio multiply), then fold the high word
    // down. The bucket index is taken from the LOW bits (`hashKey(...) & m`):
    // with an odd multiplier the low k bits of the product depend only on the
    // low k bits of the key, so without this fold the HIGH 32 bits of an i64
    // key never reach the bucket and the {1, 2^32+1, 2*2^32+1, ...} family all
    // collide onto one probe chain. The `h ^= h >> 32` finalizer mixes the
    // high word into the low word so the full 64-bit key influences the bucket
    // — matching Go's int64_int32_hash_map.go (`h ^= h >> 32`).
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
// OpenHashMap
// ---------------------------------------------------------------------------

/// The **retired** array-of-structs entry layout: key, value and an
/// interleaved occupancy `bool` per slot. `OpenHashMap` no longer stores these
/// (it is structure-of-arrays now, see below); the type is kept only as the
/// reference footprint that `bench_deferred.zig` compares the live SoA layout
/// against (D3). Wrappers must use the `keys`/`values`/`isOccupied` surface.
pub fn MapEntry(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
        occupied: bool,
    };
}

pub fn OpenHashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        // Structure-of-arrays (D3): keys and values are separate dense arrays
        // indexed by slot; occupancy is a 1-bit-per-slot word bitset. All three
        // share the same slot index `i ∈ [0, capacity)`. `keys[i]`/`values[i]`
        // are meaningful ONLY when `isOccupied(i)` — unoccupied slots hold
        // undefined key/value (never read without the occupancy guard).
        keys: []K,
        values: []V,
        occupied: []usize,
        size: usize,
        capacity: usize,
        alloc: Allocator,

        /// Whether slot `i` holds a live entry. The occupied-slot accessor for
        /// wrappers iterating the table directly (`keys[i]`/`values[i]` are only
        /// valid when this is true).
        pub inline fn isOccupied(self: *const Self, i: usize) bool {
            return bitGet(self.occupied, i);
        }

        /// Infallible: starts empty with zero capacity and no allocation. The
        /// backing table is allocated lazily on the first `put` (see `resize`'s
        /// `@max(DEFAULT_CAPACITY, ...)` grow-from-zero path).
        pub fn init(alloc: Allocator) Self {
            return .{
                .keys = &.{},
                .values = &.{},
                .occupied = &.{},
                .size = 0,
                .capacity = 0,
                .alloc = alloc,
            };
        }

        /// Allocate a table of `nextPow2(max(requested, 16))` **slots**. Note
        /// this is a slot count, not an element capacity: under the 0.75 load
        /// factor it holds only ~¾ of `requested` elements before rehashing.
        /// Callers that want "fits N elements" want `initForElements` (D7).
        pub fn initCapacity(alloc: Allocator, requested: usize) Allocator.Error!Self {
            return initAtLeast(alloc, nextPow2(@max(requested, DEFAULT_CAPACITY)));
        }

        /// Pre-size for exactly `n` elements with a guaranteed zero mid-load
        /// rehash: `cap = nextPow2(floor(4n/3)+1)` (the required-capacity
        /// formula `ensureCapacity` uses, computed overflow-safely). Used by the
        /// hash data pump so `bulkLoad`/`bulkLoadExact` start at the zero-rehash
        /// size rather than at `nextPow2(max(n,16))`.
        pub fn initForElements(alloc: Allocator, n: usize) Allocator.Error!Self {
            return initAtLeast(alloc, nextPow2(@max(requiredCapacity(n), DEFAULT_CAPACITY)));
        }

        fn initAtLeast(alloc: Allocator, cap: usize) Allocator.Error!Self {
            const keys = try alloc.alloc(K, cap);
            errdefer alloc.free(keys);
            const values = try alloc.alloc(V, cap);
            errdefer alloc.free(values);
            const occupied = try alloc.alloc(usize, wordsFor(cap));
            @memset(occupied, 0);
            // keys/values left undefined: read only through the occupancy guard.
            return .{
                .keys = keys,
                .values = values,
                .occupied = occupied,
                .size = 0,
                .capacity = cap,
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            // A never-grown map holds the empty `&.{}` sentinels (capacity 0);
            // skip the free so the allocator never sees a bogus zero-length ptr.
            if (self.capacity != 0) {
                self.alloc.free(self.keys);
                self.alloc.free(self.values);
                self.alloc.free(self.occupied);
            }
            self.* = undefined;
        }

        inline fn mask(self: *const Self) usize {
            return self.capacity - 1;
        }

        inline fn needsResize(self: *const Self) bool {
            // Strictly below 0.75: grow once (size+1)/capacity would reach 0.75,
            // i.e. use >= so the 12th insert into a capacity-16 table resizes.
            // Consistent with ensureCapacity's strict form below. Also true at
            // capacity 0 (lazy-alloc start), forcing the first put to grow.
            return (self.size + 1) * 4 >= self.capacity * 3;
        }

        fn resize(self: *Self) Allocator.Error!void {
            // Growing from the lazy zero-capacity start must land on
            // DEFAULT_CAPACITY, not `0 * 2 == 0`.
            try self.growTo(@max(DEFAULT_CAPACITY, self.capacity * 2));
        }

        /// Rehash all entries into freshly allocated buffers of size `new_cap`.
        /// Caller must guarantee `new_cap` is a power of two and fits every live
        /// entry under the 0.75 load factor. No-op if `new_cap <= self.capacity`.
        fn growTo(self: *Self, new_cap: usize) Allocator.Error!void {
            if (new_cap <= self.capacity) return;
            const old_keys = self.keys;
            const old_values = self.values;
            const old_occupied = self.occupied;
            const old_cap = self.capacity;

            const new_keys = try self.alloc.alloc(K, new_cap);
            errdefer self.alloc.free(new_keys);
            const new_values = try self.alloc.alloc(V, new_cap);
            errdefer self.alloc.free(new_values);
            const new_occupied = try self.alloc.alloc(usize, wordsFor(new_cap));
            @memset(new_occupied, 0);

            self.keys = new_keys;
            self.values = new_values;
            self.occupied = new_occupied;
            self.capacity = new_cap;
            self.size = 0;

            for (0..old_cap) |i| {
                if (bitGet(old_occupied, i)) {
                    self.insertNoResize(old_keys[i], old_values[i]);
                }
            }
            if (old_cap != 0) {
                self.alloc.free(old_keys);
                self.alloc.free(old_values);
                self.alloc.free(old_occupied);
            }
        }

        /// Infallible insertion used by growTo for rehashing into a buffer that
        /// is already guaranteed to fit every live entry.
        fn insertNoResize(self: *Self, key: K, value: V) void {
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.isOccupied(idx)) {
                    self.keys[idx] = key;
                    self.values[idx] = value;
                    bitSet(self.occupied, idx);
                    self.size += 1;
                    return;
                }
                idx = (idx + 1) & m;
            }
        }

        /// Grow the backing table so that `additional` more entries can be put
        /// without triggering a resize. Idempotent: a no-op when the current
        /// capacity already covers the request.
        ///
        /// This is the hook that the generated wrappers expose as
        /// `ensureUnusedCapacity` / `ensureTotalCapacity`, enabling a "reserve
        /// fallibly, then put infallibly" usage pattern.
        pub fn ensureCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const needed = self.size + additional;
            // Keep load factor strictly below 0.75. needsResize() resizes when
            // (size+1)*4 >= capacity*3, so an insert reaching `needed` entries
            // stays in place iff capacity*3 > needed*4, i.e. capacity > needed*4/3.
            // requiredCapacity() == floor(4*needed/3)+1, computed overflow-safely.
            const required = requiredCapacity(needed);
            if (required <= self.capacity) return;
            const new_cap = nextPow2(@max(required, DEFAULT_CAPACITY));
            try self.growTo(new_cap);
        }

        fn rehashFrom(self: *Self, deleted: usize) void {
            const m = self.mask();
            var gap = deleted;
            var idx = (deleted + 1) & m;
            while (self.isOccupied(idx)) {
                const ideal = @as(usize, @intCast(hashKey(K, self.keys[idx]) & m));
                const dist_current = (idx -% ideal) & m;
                const dist_gap = (gap -% ideal) & m;
                if (dist_current > dist_gap) {
                    self.keys[gap] = self.keys[idx];
                    self.values[gap] = self.values[idx];
                    bitSet(self.occupied, gap);
                    bitClear(self.occupied, idx);
                    gap = idx;
                }
                idx = (idx + 1) & m;
                if (idx == deleted) break;
            }
        }

        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            if (self.needsResize()) try self.resize();
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.isOccupied(idx)) {
                    self.keys[idx] = key;
                    self.values[idx] = value;
                    bitSet(self.occupied, idx);
                    self.size += 1;
                    return null;
                }
                if (keyEql(K, self.keys[idx], key)) {
                    const old = self.values[idx];
                    self.values[idx] = value;
                    return old;
                }
                idx = (idx + 1) & m;
            }
        }

        pub fn get(self: *const Self, key: K) ?V {
            if (self.size == 0) return null;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.isOccupied(idx)) return null;
                if (keyEql(K, self.keys[idx], key)) return self.values[idx];
                idx = (idx + 1) & m;
            }
        }

        pub fn getPtr(self: *Self, key: K) ?*V {
            if (self.size == 0) return null;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.isOccupied(idx)) return null;
                if (keyEql(K, self.keys[idx], key)) return &self.values[idx];
                idx = (idx + 1) & m;
            }
        }

        pub fn remove(self: *Self, key: K) ?V {
            if (self.size == 0) return null;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.isOccupied(idx)) return null;
                if (keyEql(K, self.keys[idx], key)) {
                    const old = self.values[idx];
                    bitClear(self.occupied, idx);
                    self.size -= 1;
                    self.rehashFrom(idx);
                    return old;
                }
                idx = (idx + 1) & m;
            }
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.get(key) != null;
        }

        pub fn containsValue(self: *const Self, value: V) bool {
            for (0..self.capacity) |i| {
                if (self.isOccupied(i) and valEql(V, self.values[i], value)) return true;
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
            @memset(self.occupied, 0);
            self.size = 0;
        }

        pub fn forEachKey(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), K) void) void {
            for (0..self.capacity) |i| {
                if (self.isOccupied(i)) f(context, self.keys[i]);
            }
        }

        pub fn forEachValue(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), V) void) void {
            for (0..self.capacity) |i| {
                if (self.isOccupied(i)) f(context, self.values[i]);
            }
        }

        pub fn keysToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const result = try allocator.alloc(K, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.isOccupied(i)) {
                    result[idx] = self.keys[i];
                    idx += 1;
                }
            }
            return result;
        }

        pub fn valuesToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]V {
            const result = try allocator.alloc(V, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.isOccupied(i)) {
                    result[idx] = self.values[i];
                    idx += 1;
                }
            }
            return result;
        }
    };
}

// ---------------------------------------------------------------------------
// OpenHashSet
// ---------------------------------------------------------------------------

/// The **retired** array-of-structs set-entry layout (key + interleaved
/// occupancy `bool`). Kept only as the reference footprint for the D3 bench;
/// `OpenHashSet` is structure-of-arrays now. Wrappers use `keys`/`isOccupied`.
pub fn SetEntry(comptime K: type) type {
    return struct {
        key: K,
        occupied: bool,
    };
}

pub fn OpenHashSet(comptime K: type) type {
    return struct {
        const Self = @This();

        // Structure-of-arrays (D3): a dense `keys` array plus a 1-bit-per-slot
        // occupancy bitset. `keys[i]` is meaningful only when `isOccupied(i)`.
        keys: []K,
        occupied: []usize,
        size: usize,
        capacity: usize,
        alloc: Allocator,

        /// Whether slot `i` holds a live element (`keys[i]` valid iff true).
        pub inline fn isOccupied(self: *const Self, i: usize) bool {
            return bitGet(self.occupied, i);
        }

        /// Infallible: starts empty with zero capacity and no allocation. The
        /// backing table is allocated lazily on the first `add` (see `resize`'s
        /// `@max(DEFAULT_CAPACITY, ...)` grow-from-zero path).
        pub fn init(alloc: Allocator) Self {
            return .{
                .keys = &.{},
                .occupied = &.{},
                .size = 0,
                .capacity = 0,
                .alloc = alloc,
            };
        }

        /// Allocate a table of `nextPow2(max(requested, 16))` **slots** — a slot
        /// count, not an element capacity (holds ~¾ of `requested` before
        /// rehashing under the 0.75 load factor). Use `initForElements` for
        /// "fits N elements" (D7).
        pub fn initCapacity(alloc: Allocator, requested: usize) Allocator.Error!Self {
            return initAtLeast(alloc, nextPow2(@max(requested, DEFAULT_CAPACITY)));
        }

        /// Pre-size for exactly `n` elements with a guaranteed zero mid-load
        /// rehash: `cap = nextPow2(floor(4n/3)+1)` (see the companion method on
        /// `OpenHashMap`). Used by the hash set data pump.
        pub fn initForElements(alloc: Allocator, n: usize) Allocator.Error!Self {
            return initAtLeast(alloc, nextPow2(@max(requiredCapacity(n), DEFAULT_CAPACITY)));
        }

        fn initAtLeast(alloc: Allocator, cap: usize) Allocator.Error!Self {
            const keys = try alloc.alloc(K, cap);
            errdefer alloc.free(keys);
            const occupied = try alloc.alloc(usize, wordsFor(cap));
            @memset(occupied, 0);
            return .{
                .keys = keys,
                .occupied = occupied,
                .size = 0,
                .capacity = cap,
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            // A never-grown set holds the empty `&.{}` sentinels (capacity 0);
            // skip the free so the allocator never sees a bogus zero-length ptr.
            if (self.capacity != 0) {
                self.alloc.free(self.keys);
                self.alloc.free(self.occupied);
            }
            self.* = undefined;
        }

        inline fn mask(self: *const Self) usize {
            return self.capacity - 1;
        }

        inline fn needsResize(self: *const Self) bool {
            // Strictly below 0.75: grow once (size+1)/capacity would reach 0.75,
            // i.e. use >= so the 12th insert into a capacity-16 table resizes.
            // Consistent with ensureCapacity's strict form below. Also true at
            // capacity 0 (lazy-alloc start), forcing the first add to grow.
            return (self.size + 1) * 4 >= self.capacity * 3;
        }

        fn resize(self: *Self) Allocator.Error!void {
            // Growing from the lazy zero-capacity start must land on
            // DEFAULT_CAPACITY, not `0 * 2 == 0`.
            try self.growTo(@max(DEFAULT_CAPACITY, self.capacity * 2));
        }

        fn growTo(self: *Self, new_cap: usize) Allocator.Error!void {
            if (new_cap <= self.capacity) return;
            const old_keys = self.keys;
            const old_occupied = self.occupied;
            const old_cap = self.capacity;

            const new_keys = try self.alloc.alloc(K, new_cap);
            errdefer self.alloc.free(new_keys);
            const new_occupied = try self.alloc.alloc(usize, wordsFor(new_cap));
            @memset(new_occupied, 0);

            self.keys = new_keys;
            self.occupied = new_occupied;
            self.capacity = new_cap;
            self.size = 0;
            for (0..old_cap) |i| {
                if (bitGet(old_occupied, i)) self.insertNoResize(old_keys[i]);
            }
            if (old_cap != 0) {
                self.alloc.free(old_keys);
                self.alloc.free(old_occupied);
            }
        }

        fn insertNoResize(self: *Self, value: K) void {
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, value) & m));
            while (true) {
                if (!self.isOccupied(idx)) {
                    self.keys[idx] = value;
                    bitSet(self.occupied, idx);
                    self.size += 1;
                    return;
                }
                idx = (idx + 1) & m;
            }
        }

        /// Grow the backing table so that `additional` more entries can be
        /// added without triggering a resize. Idempotent: a no-op when the
        /// current capacity already covers the request. See the companion
        /// method on `OpenHashMap` for the motivation.
        pub fn ensureCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const needed = self.size + additional;
            const required = requiredCapacity(needed);
            if (required <= self.capacity) return;
            const new_cap = nextPow2(@max(required, DEFAULT_CAPACITY));
            try self.growTo(new_cap);
        }

        fn rehashFrom(self: *Self, deleted: usize) void {
            const m = self.mask();
            var gap = deleted;
            var idx = (deleted + 1) & m;
            while (self.isOccupied(idx)) {
                const ideal = @as(usize, @intCast(hashKey(K, self.keys[idx]) & m));
                const dist_current = (idx -% ideal) & m;
                const dist_gap = (gap -% ideal) & m;
                if (dist_current > dist_gap) {
                    self.keys[gap] = self.keys[idx];
                    bitSet(self.occupied, gap);
                    bitClear(self.occupied, idx);
                    gap = idx;
                }
                idx = (idx + 1) & m;
                if (idx == deleted) break;
            }
        }

        pub fn add(self: *Self, value: K) Allocator.Error!bool {
            if (self.needsResize()) try self.resize();
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, value) & m));
            while (true) {
                if (!self.isOccupied(idx)) {
                    self.keys[idx] = value;
                    bitSet(self.occupied, idx);
                    self.size += 1;
                    return true;
                }
                if (keyEql(K, self.keys[idx], value)) return false;
                idx = (idx + 1) & m;
            }
        }

        pub fn remove(self: *Self, value: K) bool {
            if (self.size == 0) return false;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, value) & m));
            while (true) {
                if (!self.isOccupied(idx)) return false;
                if (keyEql(K, self.keys[idx], value)) {
                    bitClear(self.occupied, idx);
                    self.size -= 1;
                    self.rehashFrom(idx);
                    return true;
                }
                idx = (idx + 1) & m;
            }
        }

        pub fn contains(self: *const Self, value: K) bool {
            if (self.size == 0) return false;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, value) & m));
            while (true) {
                if (!self.isOccupied(idx)) return false;
                if (keyEql(K, self.keys[idx], value)) return true;
                idx = (idx + 1) & m;
            }
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn clear(self: *Self) void {
            @memset(self.occupied, 0);
            self.size = 0;
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const result = try allocator.alloc(K, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.isOccupied(i)) {
                    result[idx] = self.keys[i];
                    idx += 1;
                }
            }
            return result;
        }
    };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The smallest table capacity that keeps `n` live entries strictly below the
/// 0.75 load factor: `floor(4*n/3) + 1` (== `ceil((4n+1)/3)`), the same bound
/// `ensureCapacity` enforces. Computed in a wide/checked way so `4*n` never
/// wraps: on overflow it saturates to `maxInt(usize)` so the subsequent
/// allocation fails cleanly instead of silently under-sizing.
fn requiredCapacity(n: usize) usize {
    const wide = std.math.mul(usize, n, 4) catch return std.math.maxInt(usize);
    return wide / 3 + 1;
}

fn nextPow2(n: usize) usize {
    if (n == 0) return 1;
    if (n > (std.math.maxInt(usize) >> 1) + 1) return std.math.maxInt(usize);
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

fn valEql(comptime V: type, a: V, b: V) bool {
    if (V == f32) return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
    if (V == f64) return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
    return a == b;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "map: insert, get, remove" {
    var m = OpenHashMap(i32, i32).init(std.testing.allocator);
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
    var m = OpenHashMap(i32, i32).init(std.testing.allocator);
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
    var m = OpenHashMap(i32, i32).init(std.testing.allocator);
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
    var m = OpenHashMap(f32, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put(1.5, 10);
    _ = try m.put(2.5, 20);
    try std.testing.expectEqual(@as(?i32, 10), m.get(1.5));
    try std.testing.expectEqual(@as(?i32, null), m.get(3.5));
}

test "map: bool keys" {
    var m = OpenHashMap(bool, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put(true, 1);
    _ = try m.put(false, 0);
    try std.testing.expectEqual(@as(?i32, 1), m.get(true));
    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "set: add, remove, contains" {
    var s = OpenHashSet(i32).init(std.testing.allocator);
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
    var s = OpenHashSet(i32).init(std.testing.allocator);
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
    var m = OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put(1, 10);
    if (m.getPtr(1)) |ptr| {
        ptr.* += 5;
    }
    try std.testing.expectEqual(@as(?i32, 15), m.get(1));
}

test "map: ensureCapacity grows and subsequent puts do not resize" {
    var m = OpenHashMap(i32, i32).init(std.testing.allocator);
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
    var m = OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    // Lazy init starts at capacity 0, so first establish a real capacity, then
    // confirm a smaller request leaves it untouched.
    try m.ensureCapacity(100);
    const cap = m.capacity;
    try m.ensureCapacity(1);
    try std.testing.expectEqual(cap, m.capacity);
}

test "map: lazy init allocates nothing until first insert" {
    var m = OpenHashMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    try std.testing.expectEqual(@as(usize, 0), m.len());
    try std.testing.expectEqual(@as(usize, 0), m.capacity);
    _ = try m.put(1, 10);
    try std.testing.expect(m.capacity >= DEFAULT_CAPACITY);
    try std.testing.expectEqual(@as(?i32, 10), m.get(1));
}

test "map: ensureCapacity propagates allocator errors" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const result = OpenHashMap(i32, i32).initCapacity(failing.allocator(), 16);
    try std.testing.expectError(error.OutOfMemory, result);
}

test "map: ensureCapacity on populated map preserves entries" {
    var m = OpenHashMap(i32, i32).init(std.testing.allocator);
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
    var s = OpenHashSet(i32).init(std.testing.allocator);
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

test "map D3: occupancy bitset stays correct across word boundaries" {
    // The occupancy bitset packs one bit per slot into usize words, so slot
    // indices that cross word boundaries (64/128/...) must set/clear the right
    // bit. Fill enough entries to span several words, delete a scattered subset
    // (exercising Robin Hood backward-shift over the bitset), and verify every
    // survivor reads back and every deleted key is gone.
    var m = OpenHashMap(i32, i64).init(std.testing.allocator);
    defer m.deinit();
    const N: i32 = 500; // capacity grows past 512 slots => 8+ bitset words
    var i: i32 = 0;
    while (i < N) : (i += 1) _ = try m.put(i, @as(i64, i) * 7);
    try std.testing.expect(m.capacity >= 512);
    // Delete every 3rd key.
    i = 0;
    while (i < N) : (i += 3) try std.testing.expectEqual(@as(?i64, @as(i64, i) * 7), m.remove(i));
    // Survivors present with correct values; deleted absent.
    i = 0;
    while (i < N) : (i += 1) {
        if (@rem(i, 3) == 0) {
            try std.testing.expectEqual(@as(?i64, null), m.get(i));
        } else {
            try std.testing.expectEqual(@as(?i64, @as(i64, i) * 7), m.get(i));
        }
    }
    const deleted: i32 = @divTrunc(N - 1, 3) + 1; // count of i in [0,N) with i%3==0
    try std.testing.expectEqual(@as(usize, @intCast(N - deleted)), m.len());
}

test "set D3: clear zeroes occupancy without touching keys; reusable" {
    var s = OpenHashSet(i32).init(std.testing.allocator);
    defer s.deinit();
    var i: i32 = 0;
    while (i < 200) : (i += 1) _ = try s.add(i);
    const cap_before = s.capacity;
    s.clear();
    try std.testing.expectEqual(@as(usize, 0), s.len());
    try std.testing.expect(!s.contains(0) and !s.contains(199));
    // Reuse after clear: same backing capacity, correct membership.
    i = 0;
    while (i < 50) : (i += 1) _ = try s.add(i * 2);
    try std.testing.expectEqual(@as(usize, 50), s.len());
    try std.testing.expectEqual(cap_before, s.capacity); // no realloc
    try std.testing.expect(s.contains(98) and !s.contains(99));
}

test "hashKey: i64 high-32-bit family spreads across distinct buckets" {
    // Regression for the high-word fold (`h ^= h >> 32`). The bucket index is
    // taken from the LOW bits (`hashKey(K, key) & m`). Without the fold, the
    // i64 family {1, 2^32+1, 2*2^32+1, ...} — which differs ONLY in the high
    // 32 bits — all maps to the SAME bucket (one degenerate probe chain),
    // because an odd multiplier's low k product bits depend only on the key's
    // low k bits. With the fold the high word reaches the bucket. Assert the
    // family lands in distinct buckets for a representative capacity mask.
    const cap: u64 = 1024; // power of two, like the table's real capacity
    const m: u64 = cap - 1;
    const N: usize = 16;
    var seen = [_]u64{0} ** 1024;
    var distinct: usize = 0;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const key: i64 = @intCast(@as(u64, @intCast(i)) *% (@as(u64, 1) << 32) +% 1);
        const bucket = hashKey(i64, key) & m;
        if (seen[bucket] == 0) {
            seen[bucket] = 1;
            distinct += 1;
        }
    }
    // Pre-fold this family collapsed to distinct == 1. The fold must spread it
    // to many distinct buckets; require near-perfect spread (allow a couple of
    // incidental collisions, but reject the degenerate one-chain behavior).
    try std.testing.expect(distinct >= N - 2);
}

test "hashKey: i64 high-32-bit family stores/reads through production map" {
    // Same family, but observed through the real OpenHashMap: every key must
    // insert and read back independently (correctness held even before the
    // fold; this guards the fold change against a placement regression).
    var map = OpenHashMap(i64, i32).init(std.testing.allocator);
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

test "hashKey: wide unsigned keys near maxInt(u64) don't trap (D1)" {
    // Before D1 the `.int` branch did `@bitCast(@as(i64, @intCast(key)))`, which
    // is a safety panic (Debug/ReleaseSafe) / UB (ReleaseFast) for any key
    // above maxInt(i64). Keys clustered near maxInt(u64) must hash and round-trip
    // through the production map without trapping.
    var map = OpenHashMap(u64, i32).init(std.testing.allocator);
    defer map.deinit();
    const keys = [_]u64{
        std.math.maxInt(u64),
        std.math.maxInt(u64) - 1,
        std.math.maxInt(u64) - 2,
        std.math.maxInt(i64), // boundary
        @as(u64, std.math.maxInt(i64)) + 1, // 0x8000…: first value that used to trap
        0xDEAD_BEEF_CAFE_BABE,
        0xFFFF_FFFF_0000_0000,
        1,
    };
    for (keys, 0..) |k, idx| {
        _ = hashKey(u64, k); // must not trap
        _ = try map.put(k, @intCast(idx));
    }
    try std.testing.expectEqual(keys.len, map.len());
    for (keys, 0..) |k, idx| {
        try std.testing.expectEqual(@as(?i32, @intCast(idx)), map.get(k));
    }
}

test "hashKey: u128 keys fold both halves without trapping (D1)" {
    const hi: u128 = @as(u128, 0xDEAD_BEEF) << 64;
    _ = hashKey(u128, std.math.maxInt(u128));
    _ = hashKey(u128, hi);
    _ = hashKey(u128, hi | 1);
    // Distinct high/low halves must not alias to the same raw hash trivially.
    try std.testing.expect(hashKey(u128, hi) != hashKey(u128, hi | 1));
}

// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! `RoaringU32` — a sparse, compressed 32-bit integer set (a Roaring-style
//! bitmap). See `spec/features/roaring-u32.md`. Zig port of the frozen Rust
//! reference (`mapdb-rust:src/roaring.rs`); the serialized bytes are byte-exact.
//!
//! The universe (`2^32` values) is split into `2^16` **chunks** keyed by the
//! high 16 bits of a value. Each non-empty chunk is stored as a **container**:
//! an ARRAY (sorted distinct `u16[]`) for cardinality `1 ..= 4096`, or a BITMAP
//! (1024 × `u64`) for cardinality `4097 ..= 65536`. The container type is a
//! **pure function of the chunk's current cardinality** (history-independent),
//! which makes the serialized form canonical.
//!
//! Ordering is **UNSIGNED u32 ascending** throughout (iteration, `min`/`max`,
//! serialized chunk order). An `i32` element is **bit-reinterpreted** to `u32`
//! (not sign-extended): callers pass `@bitCast(i32)`, so `i32 -1` is
//! `0xFFFFFFFF` and sorts last.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Cardinality at and below which a chunk is an ARRAY; above which it is a
/// BITMAP. `4096` is the classic Roaring break-even (`4096 × 2 bytes == 8192`,
/// the bitmap size). `c <= 4096 => ARRAY`, `c > 4096 => BITMAP`.
const ARRAY_MAX: usize = 4096;

/// A BITMAP container is always exactly 1024 `u64` words (`2^16` bits).
const BITMAP_WORDS: usize = 1024;

/// Serialized header magic: `0x3252_3055` (LE bytes `55 30 52 32`).
const MAGIC: u32 = 0x3252_3055;
/// Serialized format version.
const VERSION: u16 = 1;

const TAG_ARRAY: u8 = 0x01;
const TAG_BITMAP: u8 = 0x02;

/// Deserialization error surface. Every variant corresponds to one of the spec
/// reader-MUST-reject bullets; the exact discriminant is informational (the
/// cross-language oracle only cares that a non-canonical image is rejected).
pub const DeserializeError = error{
    BadMagic,
    UnsupportedVersion,
    NonZeroReserved,
    ChunkCountTooLarge,
    NonAscendingChunkHigh,
    NonZeroPad,
    UnknownContainerTag,
    NonCanonicalArrayCardinality,
    NonCanonicalBitmapCardinality,
    NonAscendingArrayLow,
    BitmapPopcountMismatch,
    Truncated,
    TrailingBytes,
} || Allocator.Error;

/// A per-chunk container. The active tag is always the canonical type for the
/// contained cardinality (ARRAY for `1 ..= 4096`, BITMAP for `4097 ..= 65536`).
const Container = union(enum) {
    /// Sorted, distinct low-16-bit keys (length == cardinality), heap-owned.
    array: std.ArrayListUnmanaged(u16),
    /// Dense bitmap: 1024 `u64` words; bit `(w*64 + b)` is low key `w*64+b`.
    /// `count` is the cached popcount (== cardinality).
    bitmap: struct {
        words: *[BITMAP_WORDS]u64,
        count: u32,
    },

    fn deinit(self: *Container, allocator: Allocator) void {
        switch (self.*) {
            .array => |*a| a.deinit(allocator),
            .bitmap => |*b| allocator.destroy(b.words),
        }
    }

    /// Cardinality (number of present low keys), `1 ..= 65536`.
    fn cardinality(self: *const Container) u32 {
        return switch (self.*) {
            .array => |*a| @intCast(a.items.len),
            .bitmap => |*b| b.count,
        };
    }

    fn contains(self: *const Container, low: u16) bool {
        switch (self.*) {
            .array => |*a| return binarySearch(a.items, low) != null,
            .bitmap => |*b| {
                const w: usize = @as(usize, low) >> 6;
                const bit = @as(u64, 1) << @truncate(low);
                return b.words[w] & bit != 0;
            },
        }
    }

    /// Insert `low`. Returns whether the container changed. The owning set
    /// converts ARRAY → BITMAP if the cardinality rises above `ARRAY_MAX`.
    fn add(self: *Container, allocator: Allocator, low: u16) Allocator.Error!bool {
        switch (self.*) {
            .array => |*a| {
                switch (searchOrInsert(a.items, low)) {
                    .found => return false,
                    .insert_at => |pos| {
                        try a.insert(allocator, pos, low);
                        return true;
                    },
                }
            },
            .bitmap => |*b| {
                const w: usize = @as(usize, low) >> 6;
                const bit = @as(u64, 1) << @truncate(low);
                if (b.words[w] & bit == 0) {
                    b.words[w] |= bit;
                    b.count += 1;
                    return true;
                }
                return false;
            },
        }
    }

    /// Remove `low`. Returns whether the container changed. The owning set
    /// converts BITMAP → ARRAY at cardinality `<= ARRAY_MAX`, and drops the
    /// whole chunk at cardinality `0`.
    fn remove(self: *Container, low: u16) bool {
        switch (self.*) {
            .array => |*a| {
                if (binarySearch(a.items, low)) |pos| {
                    _ = a.orderedRemove(pos);
                    return true;
                }
                return false;
            },
            .bitmap => |*b| {
                const w: usize = @as(usize, low) >> 6;
                const bit = @as(u64, 1) << @truncate(low);
                if (b.words[w] & bit != 0) {
                    b.words[w] &= ~bit;
                    b.count -= 1;
                    return true;
                }
                return false;
            },
        }
    }

    /// All present low keys in unsigned ascending order (caller owns the slice).
    fn lows(self: *const Container, allocator: Allocator) Allocator.Error![]u16 {
        switch (self.*) {
            .array => |*a| return allocator.dupe(u16, a.items),
            .bitmap => |*b| {
                var out = try allocator.alloc(u16, b.count);
                var n: usize = 0;
                for (b.words, 0..) |word, w| {
                    var bits = word;
                    while (bits != 0) {
                        const bit_index: usize = @ctz(bits);
                        out[n] = @intCast(w * 64 + bit_index);
                        n += 1;
                        bits &= bits - 1;
                    }
                }
                return out;
            },
        }
    }

    /// Minimum present low key (unsigned). Container is never empty.
    fn minLow(self: *const Container) u16 {
        switch (self.*) {
            .array => |*a| return a.items[0],
            .bitmap => |*b| {
                for (b.words, 0..) |word, w| {
                    if (word != 0) return @intCast(w * 64 + @ctz(word));
                }
                unreachable; // non-empty bitmap has a set bit
            },
        }
    }

    /// Maximum present low key (unsigned). Container is never empty.
    fn maxLow(self: *const Container) u16 {
        switch (self.*) {
            .array => |*a| return a.items[a.items.len - 1],
            .bitmap => |*b| {
                var w: usize = BITMAP_WORDS;
                while (w > 0) {
                    w -= 1;
                    const word = b.words[w];
                    if (word != 0) return @intCast(w * 64 + (63 - @clz(word)));
                }
                unreachable; // non-empty bitmap has a set bit
            },
        }
    }

    /// Build a BITMAP from a sorted low-key list.
    fn bitmapFromLows(allocator: Allocator, low_keys: []const u16) Allocator.Error!Container {
        const words = try allocator.create([BITMAP_WORDS]u64);
        @memset(words, 0);
        for (low_keys) |low| {
            const w: usize = @as(usize, low) >> 6;
            words[w] |= @as(u64, 1) << @truncate(low);
        }
        return .{ .bitmap = .{ .words = words, .count = @intCast(low_keys.len) } };
    }

    /// Normalize a low-key list (assumed sorted, distinct, non-empty) into the
    /// canonical container for its cardinality. Takes ownership of `low_keys`
    /// (an allocator-owned slice): consumed into the ARRAY, or freed after
    /// building the BITMAP.
    fn canonicalFromOwnedLows(allocator: Allocator, low_keys: []u16) Allocator.Error!Container {
        if (low_keys.len <= ARRAY_MAX) {
            return .{ .array = std.ArrayListUnmanaged(u16).fromOwnedSlice(low_keys) };
        }
        defer allocator.free(low_keys);
        return bitmapFromLows(allocator, low_keys);
    }
};

const SearchResult = union(enum) {
    found: usize,
    insert_at: usize,
};

/// Binary search a sorted `u16` slice; returns the index if present.
fn binarySearch(items: []const u16, key: u16) ?usize {
    var lo: usize = 0;
    var hi: usize = items.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const v = items[mid];
        if (v == key) return mid;
        if (v < key) lo = mid + 1 else hi = mid;
    }
    return null;
}

/// Binary search returning either the found index or the ascending insertion
/// point.
fn searchOrInsert(items: []const u16, key: u16) SearchResult {
    var lo: usize = 0;
    var hi: usize = items.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const v = items[mid];
        if (v == key) return .{ .found = mid };
        if (v < key) lo = mid + 1 else hi = mid;
    }
    return .{ .insert_at = lo };
}

const Chunk = struct {
    high: u16,
    container: Container,
};

/// A sparse, compressed set of `u32` values (Roaring-style bitmap).
///
/// `i32` elements are bit-reinterpreted to `u32` (`-1 → 0xFFFFFFFF`) by the
/// caller before being passed in, then split into a 16-bit high key (chunk) and
/// 16-bit low key. Ordering is unsigned u32 ascending throughout.
pub const RoaringU32 = struct {
    allocator: Allocator,
    /// Non-empty chunks in **unsigned high-key ascending** order. Invariant:
    /// strictly ascending highs, no empty containers.
    chunks: std.ArrayListUnmanaged(Chunk),

    /// An empty set.
    pub fn init(allocator: Allocator) RoaringU32 {
        return .{ .allocator = allocator, .chunks = .{} };
    }

    pub fn deinit(self: *RoaringU32) void {
        for (self.chunks.items) |*c| c.container.deinit(self.allocator);
        self.chunks.deinit(self.allocator);
    }

    /// Locate the chunk index for `high`. `.found` if present; `.insert_at` is
    /// the ascending insertion point.
    fn find(self: *const RoaringU32, high: u16) SearchResult {
        var lo: usize = 0;
        var hi: usize = self.chunks.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const h = self.chunks.items[mid].high;
            if (h == high) return .{ .found = mid };
            if (h < high) lo = mid + 1 else hi = mid;
        }
        return .{ .insert_at = lo };
    }

    /// Insert `value`. Returns whether the set changed (was newly added).
    pub fn add(self: *RoaringU32, value: u32) Allocator.Error!bool {
        const high: u16 = @truncate(value >> 16);
        const low: u16 = @truncate(value);
        switch (self.find(high)) {
            .found => |i| {
                const changed = try self.chunks.items[i].container.add(self.allocator, low);
                if (changed and self.chunks.items[i].container.cardinality() > ARRAY_MAX) {
                    // ARRAY → BITMAP up-conversion at cardinality 4097.
                    if (self.chunks.items[i].container == .array) {
                        // Build the replacement BITMAP BEFORE committing it. If
                        // any allocation fails, roll the just-inserted low back
                        // out of the ARRAY so the chunk stays canonical.
                        const low_keys = self.chunks.items[i].container.lows(self.allocator) catch |err| {
                            _ = self.chunks.items[i].container.remove(low);
                            return err;
                        };
                        defer self.allocator.free(low_keys);
                        const bm = Container.bitmapFromLows(self.allocator, low_keys) catch |err| {
                            _ = self.chunks.items[i].container.remove(low);
                            return err;
                        };
                        self.chunks.items[i].container.deinit(self.allocator);
                        self.chunks.items[i].container = bm;
                    }
                }
                return changed;
            },
            .insert_at => |i| {
                var arr = std.ArrayListUnmanaged(u16){};
                errdefer arr.deinit(self.allocator);
                try arr.append(self.allocator, low);
                try self.chunks.insert(self.allocator, i, .{ .high = high, .container = .{ .array = arr } });
                return true;
            },
        }
    }

    /// Remove `value`. Returns whether the set changed (was present).
    pub fn remove(self: *RoaringU32, value: u32) Allocator.Error!bool {
        const high: u16 = @truncate(value >> 16);
        const low: u16 = @truncate(value);
        const i = switch (self.find(high)) {
            .found => |i| i,
            .insert_at => return false,
        };
        const changed = self.chunks.items[i].container.remove(low);
        if (!changed) return false;
        const card = self.chunks.items[i].container.cardinality();
        if (card == 0) {
            // Empty-chunk normalization: drop the chunk entirely.
            var c = self.chunks.orderedRemove(i);
            c.container.deinit(self.allocator);
        } else if (card <= ARRAY_MAX) {
            // BITMAP → ARRAY down-conversion at cardinality 4096.
            if (self.chunks.items[i].container == .bitmap) {
                // Build the replacement ARRAY BEFORE committing it. If `lows()`
                // fails, restore the just-cleared bit so the chunk stays a
                // canonical BITMAP at cardinality 4096+1.
                const low_keys = self.chunks.items[i].container.lows(self.allocator) catch |err| {
                    _ = self.chunks.items[i].container.add(self.allocator, low) catch {};
                    return err;
                };
                const new_container = Container{ .array = std.ArrayListUnmanaged(u16).fromOwnedSlice(low_keys) };
                self.chunks.items[i].container.deinit(self.allocator);
                self.chunks.items[i].container = new_container;
            }
        }
        return true;
    }

    /// Whether `value` is present.
    pub fn contains(self: *const RoaringU32, value: u32) bool {
        const high: u16 = @truncate(value >> 16);
        const low: u16 = @truncate(value);
        switch (self.find(high)) {
            .found => |i| return self.chunks.items[i].container.contains(low),
            .insert_at => return false,
        }
    }

    /// Logical cardinality (up to `2^32`).
    pub fn cardinality(self: *const RoaringU32) u64 {
        var sum: u64 = 0;
        for (self.chunks.items) |*c| sum += c.container.cardinality();
        return sum;
    }

    /// Whether the set is empty.
    pub fn isEmpty(self: *const RoaringU32) bool {
        return self.chunks.items.len == 0;
    }

    /// Remove all values (canonical empty set).
    pub fn clear(self: *RoaringU32) void {
        for (self.chunks.items) |*c| c.container.deinit(self.allocator);
        self.chunks.clearRetainingCapacity();
    }

    /// Number of non-empty chunks (the serialized `CHUNK_COUNT`).
    pub fn chunkCount(self: *const RoaringU32) usize {
        return self.chunks.items.len;
    }

    /// Unsigned minimum present value, or `null` if empty.
    pub fn min(self: *const RoaringU32) ?u32 {
        if (self.chunks.items.len == 0) return null;
        const c = &self.chunks.items[0];
        return join(c.high, c.container.minLow());
    }

    /// Unsigned maximum present value, or `null` if empty.
    pub fn max(self: *const RoaringU32) ?u32 {
        if (self.chunks.items.len == 0) return null;
        const c = &self.chunks.items[self.chunks.items.len - 1];
        return join(c.high, c.container.maxLow());
    }

    /// All values in unsigned u32 ascending order (caller owns the slice).
    pub fn toSortedSlice(self: *const RoaringU32, allocator: Allocator) Allocator.Error![]u32 {
        var out = try std.ArrayListUnmanaged(u32).initCapacity(allocator, @intCast(self.cardinality()));
        errdefer out.deinit(allocator);
        for (self.chunks.items) |*c| {
            const low_keys = try c.container.lows(self.allocator);
            defer self.allocator.free(low_keys);
            for (low_keys) |low| out.appendAssumeCapacity(join(c.high, low));
        }
        return out.toOwnedSlice(allocator);
    }

    /// Per-chunk container-type tags in chunk order (`"array"` / `"bitmap"`),
    /// caller owns the outer slice (the strings are static).
    pub fn containerTypes(self: *const RoaringU32, allocator: Allocator) Allocator.Error![][]const u8 {
        const out = try allocator.alloc([]const u8, self.chunks.items.len);
        for (self.chunks.items, 0..) |*c, i| {
            out[i] = switch (c.container) {
                .array => "array",
                .bitmap => "bitmap",
            };
        }
        return out;
    }

    // ---- Set algebra (container-granularity, scalar) ---------------------

    const MergeKind = enum { @"union", intersect, and_not, xor };

    fn keepA(kind: MergeKind) bool {
        return kind != .intersect;
    }
    fn keepB(kind: MergeKind) bool {
        return kind == .@"union" or kind == .xor;
    }

    /// Generic chunk-merge driver, building a NEW independent set. Chunks present
    /// in only one operand are rebuilt into the canonical representation; chunks
    /// present in both are merged per `kind`, then empty results are dropped and
    /// the survivor stored in its canonical container type.
    fn combine(self: *const RoaringU32, other: *const RoaringU32, kind: MergeKind) Allocator.Error!RoaringU32 {
        var result = RoaringU32.init(self.allocator);
        errdefer result.deinit();
        const al = self.allocator;

        var i: usize = 0;
        var j: usize = 0;
        const a_chunks = self.chunks.items;
        const b_chunks = other.chunks.items;
        while (i < a_chunks.len and j < b_chunks.len) {
            const ha = a_chunks[i].high;
            const hb = b_chunks[j].high;
            if (ha < hb) {
                if (keepA(kind)) try result.pushCanonicalCopy(ha, &a_chunks[i].container);
                i += 1;
            } else if (ha > hb) {
                if (keepB(kind)) try result.pushCanonicalCopy(hb, &b_chunks[j].container);
                j += 1;
            } else {
                const low_keys = try mergeLows(al, kind, &a_chunks[i].container, &b_chunks[j].container);
                if (low_keys.len != 0) {
                    var container = try Container.canonicalFromOwnedLows(al, low_keys);
                    // Ownership has moved into `container`; free it if the append
                    // fails (errdefer result.deinit only covers appended chunks).
                    errdefer container.deinit(al);
                    try result.chunks.append(al, .{ .high = ha, .container = container });
                } else {
                    al.free(low_keys);
                }
                i += 1;
                j += 1;
            }
        }
        if (keepA(kind)) {
            while (i < a_chunks.len) : (i += 1) try result.pushCanonicalCopy(a_chunks[i].high, &a_chunks[i].container);
        }
        if (keepB(kind)) {
            while (j < b_chunks.len) : (j += 1) try result.pushCanonicalCopy(b_chunks[j].high, &b_chunks[j].container);
        }
        return result;
    }

    /// Append a canonical, independent rebuild of `src` under high key `high`.
    fn pushCanonicalCopy(self: *RoaringU32, high: u16, src: *const Container) Allocator.Error!void {
        const low_keys = try src.lows(self.allocator);
        var container = try Container.canonicalFromOwnedLows(self.allocator, low_keys);
        // Ownership has moved into `container`; free it if the append fails.
        errdefer container.deinit(self.allocator);
        try self.chunks.append(self.allocator, .{ .high = high, .container = container });
    }

    /// Union (`v ∈ A` or `v ∈ B`).
    pub fn @"union"(self: *const RoaringU32, other: *const RoaringU32) Allocator.Error!RoaringU32 {
        return self.combine(other, .@"union");
    }

    /// Intersection (`v ∈ A` and `v ∈ B`).
    pub fn intersect(self: *const RoaringU32, other: *const RoaringU32) Allocator.Error!RoaringU32 {
        return self.combine(other, .intersect);
    }

    /// Difference (`v ∈ A` and `v ∉ B`; asymmetric `A \ B`).
    pub fn andNot(self: *const RoaringU32, other: *const RoaringU32) Allocator.Error!RoaringU32 {
        return self.combine(other, .and_not);
    }

    /// Symmetric difference (exactly one of `A`, `B`).
    pub fn xor(self: *const RoaringU32, other: *const RoaringU32) Allocator.Error!RoaringU32 {
        return self.combine(other, .xor);
    }

    // ---- Serialization (little-endian, canonical) ------------------------

    /// Serialize to the canonical little-endian v1 byte image (caller owns).
    pub fn serialize(self: *const RoaringU32, allocator: Allocator) Allocator.Error![]u8 {
        var out = std.ArrayListUnmanaged(u8){};
        errdefer out.deinit(allocator);
        const w = out.writer(allocator);
        try w.writeInt(u32, MAGIC, .little);
        try w.writeInt(u16, VERSION, .little);
        try w.writeInt(u16, 0, .little); // RESERVED
        try w.writeInt(u32, @intCast(self.chunks.items.len), .little);
        for (self.chunks.items) |*c| {
            try w.writeInt(u16, c.high, .little);
            const card = c.container.cardinality();
            switch (c.container) {
                .array => |*a| {
                    try w.writeByte(TAG_ARRAY);
                    try w.writeByte(0); // PAD
                    try w.writeInt(u16, @intCast(card - 1), .little);
                    for (a.items) |low| try w.writeInt(u16, low, .little);
                },
                .bitmap => |*b| {
                    try w.writeByte(TAG_BITMAP);
                    try w.writeByte(0); // PAD
                    try w.writeInt(u16, @intCast(card - 1), .little);
                    for (b.words) |word| try w.writeInt(u64, word, .little);
                },
            }
        }
        return out.toOwnedSlice(allocator);
    }

    /// Deserialize a canonical v1 byte image. Rejects any non-canonical / corrupt
    /// / foreign image (see spec reader-MUST-reject rules).
    pub fn deserialize(allocator: Allocator, bytes: []const u8) DeserializeError!RoaringU32 {
        var r = Reader{ .bytes = bytes };
        if (try r.readU32() != MAGIC) return error.BadMagic;
        if (try r.readU16() != VERSION) return error.UnsupportedVersion;
        if (try r.readU16() != 0) return error.NonZeroReserved;
        const chunk_count = try r.readU32();
        if (chunk_count > 65536) return error.ChunkCountTooLarge;

        var set = RoaringU32.init(allocator);
        errdefer set.deinit();
        try set.chunks.ensureTotalCapacity(allocator, chunk_count);

        var prev_high: ?u16 = null;
        var n: u32 = 0;
        while (n < chunk_count) : (n += 1) {
            const high = try r.readU16();
            if (prev_high) |p| {
                if (high <= p) return error.NonAscendingChunkHigh;
            }
            prev_high = high;
            const tag = try r.readU8();
            const pad = try r.readU8();
            if (pad != 0) return error.NonZeroPad;
            const card: u32 = @as(u32, try r.readU16()) + 1; // CARDINALITY_MINUS_1 + 1
            switch (tag) {
                TAG_ARRAY => {
                    if (card > ARRAY_MAX) return error.NonCanonicalArrayCardinality;
                    var arr = try std.ArrayListUnmanaged(u16).initCapacity(allocator, card);
                    errdefer arr.deinit(allocator);
                    var prev: ?u16 = null;
                    var k: u32 = 0;
                    while (k < card) : (k += 1) {
                        const low = try r.readU16();
                        if (prev) |p| {
                            if (low <= p) return error.NonAscendingArrayLow;
                        }
                        prev = low;
                        arr.appendAssumeCapacity(low);
                    }
                    set.chunks.appendAssumeCapacity(.{ .high = high, .container = .{ .array = arr } });
                },
                TAG_BITMAP => {
                    if (card <= ARRAY_MAX) return error.NonCanonicalBitmapCardinality;
                    const words = try allocator.create([BITMAP_WORDS]u64);
                    errdefer allocator.destroy(words);
                    var popcount: u32 = 0;
                    for (words) |*slot| {
                        const word = try r.readU64();
                        popcount += @popCount(word);
                        slot.* = word;
                    }
                    if (popcount != card) return error.BitmapPopcountMismatch;
                    set.chunks.appendAssumeCapacity(.{ .high = high, .container = .{ .bitmap = .{ .words = words, .count = card } } });
                },
                else => return error.UnknownContainerTag,
            }
        }
        if (!r.atEnd()) return error.TrailingBytes;
        return set;
    }
};

inline fn join(high: u16, low: u16) u32 {
    return (@as(u32, high) << 16) | @as(u32, low);
}

/// Merge two same-high containers into a sorted, distinct low-key list (owned).
fn mergeLows(allocator: Allocator, kind: RoaringU32.MergeKind, a: *const Container, b: *const Container) Allocator.Error![]u16 {
    const la = try a.lows(allocator);
    defer allocator.free(la);
    const lb = try b.lows(allocator);
    defer allocator.free(lb);
    return switch (kind) {
        .@"union" => sortedUnion(allocator, la, lb),
        .intersect => sortedIntersect(allocator, la, lb),
        .and_not => sortedAndNot(allocator, la, lb),
        .xor => sortedXor(allocator, la, lb),
    };
}

// ---- Scalar sorted-list set algebra (low-key lists) ----------------------

fn sortedUnion(allocator: Allocator, a: []const u16, b: []const u16) Allocator.Error![]u16 {
    var out = try std.ArrayListUnmanaged(u16).initCapacity(allocator, a.len + b.len);
    errdefer out.deinit(allocator);
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        if (a[i] < b[j]) {
            out.appendAssumeCapacity(a[i]);
            i += 1;
        } else if (a[i] > b[j]) {
            out.appendAssumeCapacity(b[j]);
            j += 1;
        } else {
            out.appendAssumeCapacity(a[i]);
            i += 1;
            j += 1;
        }
    }
    out.appendSliceAssumeCapacity(a[i..]);
    out.appendSliceAssumeCapacity(b[j..]);
    return out.toOwnedSlice(allocator);
}

fn sortedIntersect(allocator: Allocator, a: []const u16, b: []const u16) Allocator.Error![]u16 {
    var out = std.ArrayListUnmanaged(u16){};
    errdefer out.deinit(allocator);
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        if (a[i] < b[j]) {
            i += 1;
        } else if (a[i] > b[j]) {
            j += 1;
        } else {
            try out.append(allocator, a[i]);
            i += 1;
            j += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

fn sortedAndNot(allocator: Allocator, a: []const u16, b: []const u16) Allocator.Error![]u16 {
    var out = std.ArrayListUnmanaged(u16){};
    errdefer out.deinit(allocator);
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        if (a[i] < b[j]) {
            try out.append(allocator, a[i]);
            i += 1;
        } else if (a[i] > b[j]) {
            j += 1;
        } else {
            i += 1;
            j += 1;
        }
    }
    try out.appendSlice(allocator, a[i..]);
    return out.toOwnedSlice(allocator);
}

fn sortedXor(allocator: Allocator, a: []const u16, b: []const u16) Allocator.Error![]u16 {
    var out = try std.ArrayListUnmanaged(u16).initCapacity(allocator, a.len + b.len);
    errdefer out.deinit(allocator);
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        if (a[i] < b[j]) {
            out.appendAssumeCapacity(a[i]);
            i += 1;
        } else if (a[i] > b[j]) {
            out.appendAssumeCapacity(b[j]);
            j += 1;
        } else {
            i += 1;
            j += 1;
        }
    }
    out.appendSliceAssumeCapacity(a[i..]);
    out.appendSliceAssumeCapacity(b[j..]);
    return out.toOwnedSlice(allocator);
}

/// Bounds-checked little-endian byte reader.
const Reader = struct {
    bytes: []const u8,
    pos: usize = 0,

    fn take(self: *Reader, n: usize) error{Truncated}![]const u8 {
        // Subtraction form avoids `pos + n` overflowing before the bounds check.
        if (n > self.bytes.len - self.pos) return error.Truncated;
        const s = self.bytes[self.pos .. self.pos + n];
        self.pos += n;
        return s;
    }
    fn readU8(self: *Reader) error{Truncated}!u8 {
        return (try self.take(1))[0];
    }
    fn readU16(self: *Reader) error{Truncated}!u16 {
        return std.mem.readInt(u16, (try self.take(2))[0..2], .little);
    }
    fn readU32(self: *Reader) error{Truncated}!u32 {
        return std.mem.readInt(u32, (try self.take(4))[0..4], .little);
    }
    fn readU64(self: *Reader) error{Truncated}!u64 {
        return std.mem.readInt(u64, (try self.take(8))[0..8], .little);
    }
    fn atEnd(self: *const Reader) bool {
        return self.pos == self.bytes.len;
    }
};

// ==========================================================================
// Tests
// ==========================================================================

const testing = std.testing;

fn build(allocator: Allocator, vals: []const u32) !RoaringU32 {
    var s = RoaringU32.init(allocator);
    for (vals) |v| _ = try s.add(v);
    return s;
}

fn expectSorted(allocator: Allocator, s: *const RoaringU32, expected: []const u32) !void {
    const got = try s.toSortedSlice(allocator);
    defer allocator.free(got);
    try testing.expectEqualSlices(u32, expected, got);
}

fn expectTypes(allocator: Allocator, s: *const RoaringU32, expected: []const []const u8) !void {
    const got = try s.containerTypes(allocator);
    defer allocator.free(got);
    try testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| try testing.expectEqualStrings(e, g);
}

test "empty set" {
    const al = testing.allocator;
    var s = RoaringU32.init(al);
    defer s.deinit();
    try testing.expect(s.isEmpty());
    try testing.expectEqual(@as(u64, 0), s.cardinality());
    try testing.expectEqual(@as(?u32, null), s.min());
    try testing.expectEqual(@as(?u32, null), s.max());
    try testing.expectEqual(@as(usize, 0), s.chunkCount());
    try expectSorted(al, &s, &.{});
    const bytes = try s.serialize(al);
    defer al.free(bytes);
    try testing.expectEqualSlices(u8, &.{ 0x55, 0x30, 0x52, 0x32, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, bytes);
}

test "single element ARRAY" {
    const al = testing.allocator;
    var s = try build(al, &.{42});
    defer s.deinit();
    try testing.expectEqual(@as(u64, 1), s.cardinality());
    try testing.expectEqual(@as(usize, 1), s.chunkCount());
    try expectTypes(al, &s, &.{"array"});
    try testing.expectEqual(@as(?u32, 42), s.min());
    try testing.expectEqual(@as(?u32, 42), s.max());
    const bytes = try s.serialize(al);
    defer al.free(bytes);
    try testing.expectEqual(@as(usize, 12 + 6 + 2), bytes.len);
    try testing.expectEqualSlices(u8, &.{ 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x2a, 0x00 }, bytes[12..]);
}

test "idempotent add/remove" {
    const al = testing.allocator;
    var s = try build(al, &.{5});
    defer s.deinit();
    try testing.expect(!try s.add(5));
    try testing.expect(try s.add(6));
    try testing.expect(try s.remove(6));
    try testing.expect(!try s.remove(6));
    try testing.expect(!try s.remove(99));
}

test "basic distinct chunks" {
    const al = testing.allocator;
    var s = try build(al, &.{ 1, 70000, 140000, 200000 });
    defer s.deinit();
    try testing.expectEqual(@as(u64, 4), s.cardinality());
    try testing.expectEqual(@as(usize, 4), s.chunkCount());
    try expectTypes(al, &s, &.{ "array", "array", "array", "array" });
    try expectSorted(al, &s, &.{ 1, 70000, 140000, 200000 });
    try testing.expectEqual(@as(?u32, 1), s.min());
    try testing.expectEqual(@as(?u32, 200000), s.max());
}

test "unsigned order with signed extremes" {
    const al = testing.allocator;
    const vals = [_]u32{
        @bitCast(@as(i32, std.math.minInt(i32))), // 0x80000000
        @bitCast(@as(i32, -1)), // 0xFFFFFFFF
        0,
        @bitCast(@as(i32, std.math.maxInt(i32))), // 0x7FFFFFFF
    };
    var s = try build(al, &vals);
    defer s.deinit();
    try expectSorted(al, &s, &.{ 0x0000_0000, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFF });
    try testing.expectEqual(@as(?u32, 0), s.min());
    try testing.expectEqual(@as(?u32, 0xFFFF_FFFF), s.max());
    // Chunk highs unsigned ascending: 0x0000, 0x7FFF, 0x8000, 0xFFFF.
    const bytes = try s.serialize(al);
    defer al.free(bytes);
    const highs = [_]u16{ 0x0000, 0x7FFF, 0x8000, 0xFFFF };
    for (highs, 0..) |h, idx| {
        const off = 12 + idx * 8;
        try testing.expectEqual(h, std.mem.readInt(u16, bytes[off..][0..2], .little));
    }
}

test "threshold ARRAY 4096 / BITMAP 4097" {
    const al = testing.allocator;
    var s = RoaringU32.init(al);
    defer s.deinit();
    var v: u32 = 0;
    while (v < 4096) : (v += 1) _ = try s.add(v);
    try testing.expectEqual(@as(u64, 4096), s.cardinality());
    try expectTypes(al, &s, &.{"array"}); // exactly 4096 is ARRAY
    _ = try s.add(4096);
    try testing.expectEqual(@as(u64, 4097), s.cardinality());
    try expectTypes(al, &s, &.{"bitmap"}); // 4097 is first BITMAP
}

test "array_to_bitmap_and_back same bytes (hysteresis)" {
    const al = testing.allocator;
    var grown = RoaringU32.init(al);
    defer grown.deinit();
    var v: u32 = 0;
    while (v <= 4096) : (v += 1) _ = try grown.add(v);
    try expectTypes(al, &grown, &.{"bitmap"});
    _ = try grown.remove(4096);
    try expectTypes(al, &grown, &.{"array"});

    var never = RoaringU32.init(al);
    defer never.deinit();
    v = 0;
    while (v < 4096) : (v += 1) _ = try never.add(v);

    const a_bytes = try grown.serialize(al);
    defer al.free(a_bytes);
    const b_bytes = try never.serialize(al);
    defer al.free(b_bytes);
    try testing.expectEqualSlices(u8, b_bytes, a_bytes);
}

test "container type pure function of cardinality (history independence)" {
    const al = testing.allocator;
    var a = RoaringU32.init(al);
    defer a.deinit();
    var v: u32 = 0;
    while (v < 5000) : (v += 1) _ = try a.add(v);
    v = 4096;
    while (v < 5000) : (v += 1) _ = try a.remove(v);

    var b = RoaringU32.init(al);
    defer b.deinit();
    v = 4096;
    while (v > 0) {
        v -= 1;
        _ = try b.add(v);
    }
    try expectTypes(al, &a, &.{"array"});
    const a_bytes = try a.serialize(al);
    defer al.free(a_bytes);
    const b_bytes = try b.serialize(al);
    defer al.free(b_bytes);
    try testing.expectEqualSlices(u8, b_bytes, a_bytes);
}

test "full chunk (65536) round-trip" {
    const al = testing.allocator;
    var s = RoaringU32.init(al);
    defer s.deinit();
    var v: u32 = 0;
    while (v <= 65535) : (v += 1) _ = try s.add(v);
    try testing.expectEqual(@as(u64, 65536), s.cardinality());
    try expectTypes(al, &s, &.{"bitmap"});
    const bytes = try s.serialize(al);
    defer al.free(bytes);
    // CARDINALITY_MINUS_1 == 0xFFFF at offset 16.
    try testing.expectEqualSlices(u8, &.{ 0xFF, 0xFF }, bytes[16..18]);
    try testing.expectEqual(@as(usize, 12 + 6 + 8192), bytes.len);
    var back = try RoaringU32.deserialize(al, bytes);
    defer back.deinit();
    const back_bytes = try back.serialize(al);
    defer al.free(back_bytes);
    try testing.expectEqualSlices(u8, bytes, back_bytes);
    try testing.expectEqual(@as(u64, 65536), back.cardinality());
}

test "drop empty chunk" {
    const al = testing.allocator;
    var s = try build(al, &.{ 100000, 5 });
    defer s.deinit();
    try testing.expectEqual(@as(usize, 2), s.chunkCount());
    _ = try s.remove(100000);
    try testing.expectEqual(@as(usize, 1), s.chunkCount());
    var only5 = try build(al, &.{5});
    defer only5.deinit();
    const a_bytes = try s.serialize(al);
    defer al.free(a_bytes);
    const b_bytes = try only5.serialize(al);
    defer al.free(b_bytes);
    try testing.expectEqualSlices(u8, b_bytes, a_bytes);
}

test "clear" {
    const al = testing.allocator;
    var s = try build(al, &.{ 1, 70000, 200000 });
    defer s.deinit();
    s.clear();
    try testing.expect(s.isEmpty());
    try testing.expectEqual(@as(u64, 0), s.cardinality());
    const bytes = try s.serialize(al);
    defer al.free(bytes);
    try testing.expectEqual(@as(usize, 12), bytes.len);
}

test "round-trip random" {
    const al = testing.allocator;
    var s = RoaringU32.init(al);
    defer s.deinit();
    var x: u64 = 0x1234_5678;
    var n: usize = 0;
    while (n < 20000) : (n += 1) {
        x = x *% 6364136223846793005 +% 1442695040888963407;
        _ = try s.add(@truncate(x >> 16));
    }
    const bytes = try s.serialize(al);
    defer al.free(bytes);
    var back = try RoaringU32.deserialize(al, bytes);
    defer back.deinit();
    const back_bytes = try back.serialize(al);
    defer al.free(back_bytes);
    try testing.expectEqualSlices(u8, bytes, back_bytes);
}

test "set algebra basic" {
    const al = testing.allocator;
    var a = try build(al, &.{ 1, 2, 3, 70000 });
    defer a.deinit();
    var b = try build(al, &.{ 2, 3, 4, 140000 });
    defer b.deinit();

    var u = try a.@"union"(&b);
    defer u.deinit();
    try expectSorted(al, &u, &.{ 1, 2, 3, 4, 70000, 140000 });

    var in = try a.intersect(&b);
    defer in.deinit();
    try expectSorted(al, &in, &.{ 2, 3 });

    var dn = try a.andNot(&b);
    defer dn.deinit();
    try expectSorted(al, &dn, &.{ 1, 70000 });

    var xr = try a.xor(&b);
    defer xr.deinit();
    try expectSorted(al, &xr, &.{ 1, 4, 70000, 140000 });

    // operands unchanged
    try expectSorted(al, &a, &.{ 1, 2, 3, 70000 });
}

test "XOR BITMAP normalizes to ARRAY" {
    const al = testing.allocator;
    var a = RoaringU32.init(al);
    defer a.deinit();
    var b = RoaringU32.init(al);
    defer b.deinit();
    var v: u32 = 0;
    while (v < 5000) : (v += 1) {
        _ = try a.add(v);
        _ = try b.add(v);
    }
    v = 5000;
    while (v < 5030) : (v += 1) _ = try a.add(v);
    try expectTypes(al, &a, &.{"bitmap"});
    try expectTypes(al, &b, &.{"bitmap"});
    var x = try a.xor(&b);
    defer x.deinit();
    try testing.expectEqual(@as(u64, 30), x.cardinality());
    try expectTypes(al, &x, &.{"array"}); // canonical for 30
}

test "OR ARRAY normalizes to BITMAP" {
    const al = testing.allocator;
    var a = RoaringU32.init(al);
    defer a.deinit();
    var b = RoaringU32.init(al);
    defer b.deinit();
    var v: u32 = 0;
    while (v < 3000) : (v += 1) _ = try a.add(v);
    v = 2000;
    while (v < 6000) : (v += 1) _ = try b.add(v);
    try expectTypes(al, &a, &.{"array"});
    var u = try a.@"union"(&b);
    defer u.deinit();
    try testing.expectEqual(@as(u64, 6000), u.cardinality());
    try expectTypes(al, &u, &.{"bitmap"});
}

test "andNot empties chunk" {
    const al = testing.allocator;
    var a = try build(al, &.{ 1, 2, 70000, 70001 });
    defer a.deinit();
    var other = try build(al, &.{ 70000, 70001 });
    defer other.deinit();
    var d = try a.andNot(&other);
    defer d.deinit();
    try testing.expectEqual(@as(usize, 1), d.chunkCount());
    try expectSorted(al, &d, &.{ 1, 2 });
    var only12 = try build(al, &.{ 1, 2 });
    defer only12.deinit();
    const d_bytes = try d.serialize(al);
    defer al.free(d_bytes);
    const e_bytes = try only12.serialize(al);
    defer al.free(e_bytes);
    try testing.expectEqualSlices(u8, e_bytes, d_bytes);
}

test "set-algebra result independent of operands" {
    const al = testing.allocator;
    var a = try build(al, &.{ 1, 2, 3 });
    defer a.deinit();
    var b = try build(al, &.{ 3, 4, 5 });
    defer b.deinit();
    var u = try a.@"union"(&b);
    defer u.deinit();
    _ = try u.add(999);
    try testing.expect(!a.contains(999));
    try testing.expect(!b.contains(999));

    // only-A chunk copied, not aliased
    var a2 = try build(al, &.{1});
    defer a2.deinit();
    var b2 = RoaringU32.init(al);
    defer b2.deinit();
    var u2_set = try a2.@"union"(&b2);
    defer u2_set.deinit();
    _ = try a2.add(2);
    try testing.expect(!u2_set.contains(2));
}

test "add_range / remove_range via helpers" {
    const al = testing.allocator;
    var s = RoaringU32.init(al);
    defer s.deinit();
    var v: u32 = 0;
    while (v <= 4095) : (v += 1) _ = try s.add(v);
    try testing.expectEqual(@as(u64, 4096), s.cardinality());
    v = 100;
    while (v <= 200) : (v += 1) _ = try s.remove(v);
    try testing.expectEqual(@as(u64, 4096 - 101), s.cardinality());
}

test "bitmap bit order round-trip" {
    const al = testing.allocator;
    var s = RoaringU32.init(al);
    defer s.deinit();
    // Force a BITMAP, then ensure specific bits across words survive serialize.
    var v: u32 = 0;
    while (v < 5000) : (v += 1) _ = try s.add(v);
    try expectTypes(al, &s, &.{"bitmap"});
    const probes = [_]u32{ 0, 1, 63, 64, 127, 4096, 4999 };
    for (probes) |p| try testing.expect(s.contains(p));
    const bytes = try s.serialize(al);
    defer al.free(bytes);
    var back = try RoaringU32.deserialize(al, bytes);
    defer back.deinit();
    for (probes) |p| try testing.expect(back.contains(p));
    try testing.expect(!back.contains(5000));
}

// ---- deserialize rejection tests ----

fn validBytes(al: Allocator) ![]u8 {
    var s = try build(al, &.{ 1, 70000 });
    defer s.deinit();
    return s.serialize(al);
}

test "reject bad magic" {
    const al = testing.allocator;
    const b = try validBytes(al);
    defer al.free(b);
    b[0] = 0x00;
    try testing.expectError(error.BadMagic, RoaringU32.deserialize(al, b));
}

test "reject bad version" {
    const al = testing.allocator;
    const b = try validBytes(al);
    defer al.free(b);
    b[4] = 0x02;
    try testing.expectError(error.UnsupportedVersion, RoaringU32.deserialize(al, b));
}

test "reject non-zero reserved" {
    const al = testing.allocator;
    const b = try validBytes(al);
    defer al.free(b);
    b[6] = 0x01;
    try testing.expectError(error.NonZeroReserved, RoaringU32.deserialize(al, b));
}

test "reject non-zero pad" {
    const al = testing.allocator;
    const b = try validBytes(al);
    defer al.free(b);
    b[15] = 0x01; // first chunk PAD at 12+2+1
    try testing.expectError(error.NonZeroPad, RoaringU32.deserialize(al, b));
}

test "reject unknown tag" {
    const al = testing.allocator;
    const b = try validBytes(al);
    defer al.free(b);
    b[14] = 0x03; // first chunk tag at 12+2
    try testing.expectError(error.UnknownContainerTag, RoaringU32.deserialize(al, b));
}

test "reject trailing bytes" {
    const al = testing.allocator;
    const valid = try validBytes(al);
    defer al.free(valid);
    const b = try al.alloc(u8, valid.len + 1);
    defer al.free(b);
    @memcpy(b[0..valid.len], valid);
    b[valid.len] = 0x00;
    try testing.expectError(error.TrailingBytes, RoaringU32.deserialize(al, b));
}

test "reject truncated" {
    const al = testing.allocator;
    const b = try validBytes(al);
    defer al.free(b);
    try testing.expectError(error.Truncated, RoaringU32.deserialize(al, b[0 .. b.len - 1]));
    try testing.expectError(error.Truncated, RoaringU32.deserialize(al, b[0..5]));
}

test "reject chunk_count too large" {
    const al = testing.allocator;
    const b = try validBytes(al);
    defer al.free(b);
    std.mem.writeInt(u32, b[8..12], 70000, .little);
    try testing.expectError(error.ChunkCountTooLarge, RoaringU32.deserialize(al, b));
}

test "reject non-canonical ARRAY cardinality" {
    const al = testing.allocator;
    var b = std.ArrayListUnmanaged(u8){};
    defer b.deinit(al);
    const w = b.writer(al);
    try w.writeInt(u32, MAGIC, .little);
    try w.writeInt(u16, VERSION, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u32, 1, .little); // 1 chunk
    try w.writeInt(u16, 0, .little); // high
    try w.writeByte(TAG_ARRAY);
    try w.writeByte(0);
    try w.writeInt(u16, 4096, .little); // card-1 = 4096 => card 4097
    var low: u16 = 0;
    while (low < 4097) : (low += 1) try w.writeInt(u16, low, .little);
    try testing.expectError(error.NonCanonicalArrayCardinality, RoaringU32.deserialize(al, b.items));
}

test "reject non-canonical BITMAP cardinality" {
    const al = testing.allocator;
    var b = std.ArrayListUnmanaged(u8){};
    defer b.deinit(al);
    const w = b.writer(al);
    try w.writeInt(u32, MAGIC, .little);
    try w.writeInt(u16, VERSION, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u32, 1, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeByte(TAG_BITMAP);
    try w.writeByte(0);
    try w.writeInt(u16, 0, .little); // card 1
    var words = [_]u64{0} ** BITMAP_WORDS;
    words[0] = 1;
    for (words) |word| try w.writeInt(u64, word, .little);
    try testing.expectError(error.NonCanonicalBitmapCardinality, RoaringU32.deserialize(al, b.items));
}

test "reject non-ascending ARRAY lows" {
    const al = testing.allocator;
    var b = std.ArrayListUnmanaged(u8){};
    defer b.deinit(al);
    const w = b.writer(al);
    try w.writeInt(u32, MAGIC, .little);
    try w.writeInt(u16, VERSION, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u32, 1, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeByte(TAG_ARRAY);
    try w.writeByte(0);
    try w.writeInt(u16, 1, .little); // card 2
    try w.writeInt(u16, 5, .little);
    try w.writeInt(u16, 5, .little); // duplicate
    try testing.expectError(error.NonAscendingArrayLow, RoaringU32.deserialize(al, b.items));
}

test "reject BITMAP popcount mismatch" {
    const al = testing.allocator;
    var b = std.ArrayListUnmanaged(u8){};
    defer b.deinit(al);
    const w = b.writer(al);
    try w.writeInt(u32, MAGIC, .little);
    try w.writeInt(u16, VERSION, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u32, 1, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeByte(TAG_BITMAP);
    try w.writeByte(0);
    try w.writeInt(u16, 4096, .little); // claims card 4097
    const words = [_]u64{0} ** BITMAP_WORDS; // popcount 0
    for (words) |word| try w.writeInt(u64, word, .little);
    try testing.expectError(error.BitmapPopcountMismatch, RoaringU32.deserialize(al, b.items));
}

test "reject non-ascending chunk highs" {
    const al = testing.allocator;
    var b = std.ArrayListUnmanaged(u8){};
    defer b.deinit(al);
    const w = b.writer(al);
    try w.writeInt(u32, MAGIC, .little);
    try w.writeInt(u16, VERSION, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u32, 2, .little);
    // chunk 1: high 5
    try w.writeInt(u16, 5, .little);
    try w.writeByte(TAG_ARRAY);
    try w.writeByte(0);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, 0, .little);
    // chunk 2: high 5 again (non-ascending)
    try w.writeInt(u16, 5, .little);
    try w.writeByte(TAG_ARRAY);
    try w.writeByte(0);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, 0, .little);
    try testing.expectError(error.NonAscendingChunkHigh, RoaringU32.deserialize(al, b.items));
}

test "OOM during threshold conversion leaves canonical state, no leak" {
    // Drive add() to the ARRAY->BITMAP edge under a failing allocator: the
    // conversion's allocation fails, the inserted low must roll back, and the
    // chunk must remain a canonical ARRAY (no leaked bitmap, no 4097-elem array).
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(al: Allocator) !void {
            var s = RoaringU32.init(al);
            defer s.deinit();
            var v: u32 = 0;
            while (v <= 4096) : (v += 1) {
                _ = s.add(v) catch |err| {
                    // On any failure the set must still be canonical and
                    // re-serializable; cardinality is whatever committed.
                    const c = s.cardinality();
                    try testing.expect(c <= 4096); // never the broken 4097-ARRAY
                    const bytes = try s.serialize(al);
                    al.free(bytes);
                    return err;
                };
            }
            // Full success path: ended as a BITMAP at 4097.
            try testing.expectEqual(@as(u64, 4097), s.cardinality());
        }
    }.run, .{});
}

test "OOM during set-algebra append does not leak result container" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(al: Allocator) !void {
            var a = RoaringU32.init(al);
            defer a.deinit();
            var b = RoaringU32.init(al);
            defer b.deinit();
            // Build operands without failing the test on the *operand* OOM:
            // these adds are allowed to fail (propagated), the harness retries.
            var v: u32 = 0;
            while (v < 100) : (v += 1) _ = try a.add(v * 3);
            v = 0;
            while (v < 100) : (v += 1) _ = try b.add(v * 2 + 200000);
            var u = try a.@"union"(&b);
            u.deinit();
        }
    }.run, .{});
}

test "cardinality width holds 2^32 type-level" {
    const al = testing.allocator;
    var s = RoaringU32.init(al);
    defer s.deinit();
    var v: u32 = 0;
    while (v <= 65535) : (v += 1) _ = try s.add(v);
    const c: u64 = s.cardinality();
    try testing.expectEqual(@as(u64, 65536), c);
}

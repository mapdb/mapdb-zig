// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Cross-language validation runner for Eclipse Collections Zig port.
// Reads a JSON scenario file, executes operations against Zig collection types,
// and outputs assertion results in canonical text format.

const std = @import("std");
const Allocator = std.mem.Allocator;

const float_order = @import("float_order.zig");

const I32I32HashMap = @import("hashmap/hashmap.zig").I32I32HashMap;
const I32ArrayList = @import("arraylist/arraylist.zig").I32ArrayList;
const I32HashSet = @import("hashset/hashset.zig").I32HashSet;
const I32HashBag = @import("bag/bag.zig").I32HashBag;
const I32TreeSet = @import("treeset/treeset.zig").I32TreeSet;
const I32I32TreeMap = @import("treemap/treemap.zig").I32I32TreeMap;
const I32ArrayStack = @import("stack/stack.zig").I32ArrayStack;
const F32I32HashMap = @import("hashmap/hashmap.zig").F32I32HashMap;
const F32HashSet = @import("hashset/hashset.zig").F32HashSet;
const F32TreeSet = @import("treeset/treeset.zig").F32TreeSet;
const F32ArrayList = @import("arraylist/arraylist.zig").F32ArrayList;
const I64I32HashMap = @import("hashmap/hashmap.zig").I64I32HashMap;
const I64I32ListMultimap = @import("multimap/multimap.zig").I64I32ListMultimap;
const I64I32SetMultimap = @import("multimap/multimap.zig").I64I32SetMultimap;
const range_mod = @import("range.zig");
const I32Range = range_mod.I32Range;
const BoundType = range_mod.BoundType;
const immutable_sorted = @import("immutable_sorted/immutable_sorted.zig");
const ImmutableI32I32SortedMap = immutable_sorted.ImmutableI32I32SortedMap;
const ImmutableI32SortedSet = immutable_sorted.ImmutableI32SortedSet;
const hash = @import("hash.zig");

const CollectionKind = enum {
    hash_map,
    array_list,
    hash_set,
    hash_bag,
    tree_set,
    tree_map,
    array_stack,
};

const Collection = union(CollectionKind) {
    hash_map: I32I32HashMap,
    array_list: I32ArrayList,
    hash_set: I32HashSet,
    hash_bag: I32HashBag,
    tree_set: I32TreeSet,
    tree_map: I32I32TreeMap,
    array_stack: I32ArrayStack,
};

const I32Pairs = struct { keys: []i32, vals: []i32 };
const I64Pairs = struct { keys: []i64, vals: []i32 };

fn allocI32Pairs(allocator: Allocator, operations: std.json.Array) !I32Pairs {
    const keys = try allocator.alloc(i32, operations.items.len);
    errdefer allocator.free(keys);
    const vals = try allocator.alloc(i32, operations.items.len);
    errdefer allocator.free(vals);
    for (operations.items, 0..) |op, i| {
        const obj = op.object;
        keys[i] = jsonToI32(obj.get("key").?).?;
        vals[i] = jsonToI32(obj.get("value").?).?;
    }
    return .{ .keys = keys, .vals = vals };
}

fn allocI64Pairs(allocator: Allocator, operations: std.json.Array) !I64Pairs {
    const keys = try allocator.alloc(i64, operations.items.len);
    errdefer allocator.free(keys);
    const vals = try allocator.alloc(i32, operations.items.len);
    errdefer allocator.free(vals);
    for (operations.items, 0..) |op, i| {
        const obj = op.object;
        keys[i] = parseI64Operand(obj.get("key").?);
        vals[i] = @as(i32, @intCast(obj.get("value").?.integer));
    }
    return .{ .keys = keys, .vals = vals };
}

fn parseCollectionKind(name: []const u8) ?CollectionKind {
    if (std.mem.eql(u8, name, "HashMap<i32, i32>")) return .hash_map;
    if (std.mem.eql(u8, name, "ArrayList<i32>")) return .array_list;
    if (std.mem.eql(u8, name, "HashSet<i32>")) return .hash_set;
    if (std.mem.eql(u8, name, "HashBag<i32>")) return .hash_bag;
    if (std.mem.eql(u8, name, "TreeSet<i32>")) return .tree_set;
    if (std.mem.eql(u8, name, "TreeMap<i32, i32>")) return .tree_map;
    if (std.mem.eql(u8, name, "ArrayStack<i32>")) return .array_stack;
    return null;
}

fn initCollection(kind: CollectionKind, allocator: Allocator) !Collection {
    return switch (kind) {
        .hash_map => .{ .hash_map = try I32I32HashMap.init(allocator) },
        .array_list => .{ .array_list = I32ArrayList.init(allocator) },
        .hash_set => .{ .hash_set = try I32HashSet.init(allocator) },
        .hash_bag => .{ .hash_bag = try I32HashBag.init(allocator) },
        .tree_set => .{ .tree_set = I32TreeSet.init(allocator) },
        .tree_map => .{ .tree_map = I32I32TreeMap.init(allocator) },
        .array_stack => .{ .array_stack = I32ArrayStack.init(allocator) },
    };
}

fn deinitCollection(coll: *Collection) void {
    switch (coll.*) {
        .hash_map => |*m| m.deinit(),
        .array_list => |*l| l.deinit(),
        .hash_set => |*s| s.deinit(),
        .hash_bag => |*b| b.deinit(),
        .tree_set => |*s| s.deinit(),
        .tree_map => |*m| m.deinit(),
        .array_stack => |*s| s.deinit(),
    }
}

fn jsonToI32(val: std.json.Value) ?i32 {
    return switch (val) {
        .integer => |i| @as(i32, @intCast(i)),
        else => null,
    };
}

// NavigableMap/Set result-log: the runner records each poll/remove_range
// return value in execution order while applying operations, then exposes
// them through the poll_*/remove_range_counts assertion keys (see README
// §NavigableMap). A null poll key/value marks an absent poll on an empty
// collection.
const NavLog = struct {
    poll_first_keys: std.ArrayList(?i32) = .{},
    poll_last_keys: std.ArrayList(?i32) = .{},
    poll_first_values: std.ArrayList(?i32) = .{},
    poll_last_values: std.ArrayList(?i32) = .{},
    remove_range_counts: std.ArrayList(i32) = .{},

    fn deinit(self: *NavLog, allocator: Allocator) void {
        self.poll_first_keys.deinit(allocator);
        self.poll_last_keys.deinit(allocator);
        self.poll_first_values.deinit(allocator);
        self.poll_last_values.deinit(allocator);
        self.remove_range_counts.deinit(allocator);
    }
};

// Build a Range<i32> from a single range-builder object (the 10-range op
// shape). Shared by the `remove_range` op's `range` field and the scenario
// `query` field; routed through the production I32Range.
fn buildRangeFromObj(op: std.json.ObjectMap) I32Range {
    const op_name = op.get("op").?.string;
    if (std.mem.eql(u8, op_name, "closed")) {
        return I32Range.closed(jsonToI32(op.get("lower").?).?, jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "open")) {
        return I32Range.open(jsonToI32(op.get("lower").?).?, jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "closed_open")) {
        return I32Range.closedOpen(jsonToI32(op.get("lower").?).?, jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "open_closed")) {
        return I32Range.openClosed(jsonToI32(op.get("lower").?).?, jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "at_least")) {
        return I32Range.atLeast(jsonToI32(op.get("lower").?).?);
    } else if (std.mem.eql(u8, op_name, "greater_than")) {
        return I32Range.greaterThan(jsonToI32(op.get("lower").?).?);
    } else if (std.mem.eql(u8, op_name, "at_most")) {
        return I32Range.atMost(jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "less_than")) {
        return I32Range.lessThan(jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "all")) {
        return I32Range.all();
    } else if (std.mem.eql(u8, op_name, "singleton")) {
        return I32Range.singleton(jsonToI32(op.get("value").?).?);
    }
    @panic("unknown range op");
}

fn applyOperation(coll: *Collection, op: std.json.Value, log: *NavLog, allocator: Allocator) !void {
    const obj = op.object;
    const op_name = obj.get("op").?.string;

    if (std.mem.eql(u8, op_name, "put")) {
        const key = jsonToI32(obj.get("key").?).?;
        const value = jsonToI32(obj.get("value").?).?;
        switch (coll.*) {
            .hash_map => |*m| _ = try m.put(key, value),
            .tree_map => |*m| _ = try m.put(key, value),
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "add")) {
        const value = jsonToI32(obj.get("value").?).?;
        switch (coll.*) {
            .array_list => |*l| try l.add(value),
            .hash_set => |*s| _ = try s.add(value),
            .hash_bag => |*b| try b.add(value),
            .tree_set => |*s| _ = try s.add(value),
            .array_stack => |*s| try s.push(value),
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "add_at")) {
        const index: usize = @intCast(obj.get("index").?.integer);
        const value = jsonToI32(obj.get("value").?).?;
        switch (coll.*) {
            .array_list => |*l| {
                try l.items.insert(l.allocator, index, value);
            },
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "addToValue")) {
        // Exercise the production addToValue, which now wraps at the value
        // width (+%=) per the spec Integer overflow contract. The runner must
        // drive production code so conformance is actually proved here.
        const key = jsonToI32(obj.get("key").?).?;
        const delta = jsonToI32(obj.get("delta").?).?;
        switch (coll.*) {
            .hash_map => |*m| {
                _ = try m.addToValue(key, delta);
            },
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "remove")) {
        switch (coll.*) {
            .hash_map => |*m| {
                const key = jsonToI32(obj.get("key").?).?;
                _ = m.remove(key);
            },
            .tree_map => |*m| {
                const key = jsonToI32(obj.get("key").?).?;
                _ = m.remove(key);
            },
            .array_list => |*l| {
                const value = jsonToI32(obj.get("value").?).?;
                _ = l.remove(value);
            },
            .hash_set => |*s| {
                const value = jsonToI32(obj.get("value").?).?;
                _ = s.remove(value);
            },
            .hash_bag => |*b| {
                const value = jsonToI32(obj.get("value").?).?;
                _ = b.remove(value);
            },
            .tree_set => |*s| {
                const value = jsonToI32(obj.get("value").?).?;
                _ = s.remove(value);
            },
            .array_stack => |*s| {
                _ = s.pop();
            },
        }
    } else if (std.mem.eql(u8, op_name, "clear")) {
        switch (coll.*) {
            .hash_map => |*m| m.clear(),
            .array_list => |*l| l.clear(),
            .hash_set => |*s| s.clear(),
            .hash_bag => |*b| b.clear(),
            .tree_set => |*s| s.clear(),
            .tree_map => |*m| m.clear(),
            .array_stack => |*s| s.clear(),
        }
    } else if (std.mem.eql(u8, op_name, "push")) {
        const value = jsonToI32(obj.get("value").?).?;
        switch (coll.*) {
            .array_stack => |*s| try s.push(value),
            .array_list => |*l| try l.push(value),
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "pop")) {
        switch (coll.*) {
            .array_stack => |*s| _ = s.pop(),
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "poll_first")) {
        // Map: record key + value; set: record element as the key (no value).
        switch (coll.*) {
            .tree_map => |*m| {
                if (m.pollFirstEntry()) |e| {
                    try log.poll_first_keys.append(allocator, e.key);
                    try log.poll_first_values.append(allocator, e.value);
                } else {
                    try log.poll_first_keys.append(allocator, null);
                    try log.poll_first_values.append(allocator, null);
                }
            },
            .tree_set => |*s| {
                try log.poll_first_keys.append(allocator, s.pollFirst());
            },
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "poll_last")) {
        switch (coll.*) {
            .tree_map => |*m| {
                if (m.pollLastEntry()) |e| {
                    try log.poll_last_keys.append(allocator, e.key);
                    try log.poll_last_values.append(allocator, e.value);
                } else {
                    try log.poll_last_keys.append(allocator, null);
                    try log.poll_last_values.append(allocator, null);
                }
            },
            .tree_set => |*s| {
                try log.poll_last_keys.append(allocator, s.pollLast());
            },
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "remove_range")) {
        const range = buildRangeFromObj(obj.get("range").?.object);
        switch (coll.*) {
            .tree_map => |*m| try log.remove_range_counts.append(allocator, @intCast(m.removeRange(range))),
            .tree_set => |*s| try log.remove_range_counts.append(allocator, @intCast(try s.removeRange(range))),
            else => {},
        }
    } else {
        // Forward-compat (README + spec/features/navigable-map.md): on the
        // ordered tree collections an unknown op is SKIPPED so a newer scenario
        // never breaks an older runner. Other collections silently ignore too
        // (this runner has always tolerated unrecognised ops in the if-chain).
    }
}

/// Get a sorted slice of values from an element-based collection.
/// Caller owns the returned slice.
fn getItemSlice(coll: *Collection, allocator: Allocator) ![]i32 {
    switch (coll.*) {
        .array_list => |*l| {
            const src = l.toSlice();
            const copy = try allocator.alloc(i32, src.len);
            @memcpy(copy, src);
            return copy;
        },
        .hash_set => |*s| {
            return try s.toSlice(allocator);
        },
        .hash_bag => |*b| {
            return try b.toSlice(allocator);
        },
        .tree_set => |*s| {
            // toSlice(allocator) now owns the return — no extra copy needed.
            return try s.toSlice(allocator);
        },
        .array_stack => |*s| {
            const src = s.toSlice();
            const copy = try allocator.alloc(i32, src.len);
            @memcpy(copy, src);
            return copy;
        },
        else => {
            return try allocator.alloc(i32, 0);
        },
    }
}

/// Parse a threshold from an assertion key like "select_gt_8" -> 8
fn parseThreshold(key: []const u8, prefix: []const u8) ?i32 {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const rest = key[prefix.len..];
    // Handle negative numbers
    if (rest.len > 0 and rest[0] == 'n') {
        // n prefix means negative, e.g. "n5" means -5 (not used in practice but safe)
        const num = std.fmt.parseInt(i32, rest[1..], 10) catch return null;
        return -num;
    }
    return std.fmt.parseInt(i32, rest, 10) catch null;
}

fn writeI32(writer: anytype, val: i32) !void {
    try writer.print("{d}", .{val});
}

// Wrapping i32 reductions passed to the production I32ArrayList.injectInto, so
// the harness exercises the production fold path with i32-seed-width wrapping
// (algorithms.md "Integer overflow contract").
fn injectAddWrapI32(_: *anyopaque, acc: i32, v: i32) i32 {
    return acc +% v;
}
fn injectMulWrapI32(_: *anyopaque, acc: i32, v: i32) i32 {
    return acc *% v;
}

fn writeI64(writer: anytype, val: i64) !void {
    try writer.print("{d}", .{val});
}

fn writeBool(writer: anytype, val: bool) !void {
    if (val) {
        try writer.writeAll("true");
    } else {
        try writer.writeAll("false");
    }
}

fn writeNull(writer: anytype) !void {
    try writer.writeAll("null");
}

// Canonical array format across all ports is "[1,2,3]" (no spaces after the
// comma) — Rust validate.rs and Go cmd/validate use this; harness diffs
// require an exact byte match.
fn writeSortedArray(writer: anytype, items: []i32) !void {
    std.mem.sort(i32, items, {}, struct {
        pub fn f(_: void, a: i32, b: i32) bool {
            return a < b;
        }
    }.f);
    try writer.writeAll("[");
    for (items, 0..) |item, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{d}", .{item});
    }
    try writer.writeAll("]");
}

fn writeArray(writer: anytype, items: []const i32) !void {
    try writer.writeAll("[");
    for (items, 0..) |item, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{d}", .{item});
    }
    try writer.writeAll("]");
}

// Set whenever any assertion mismatches; the process exits non-zero at the
// end so the harness treats assertion failures as the primary pass/fail.
var any_fail: bool = false;

// Controls how an expected JSON value renders into the canonical computed
// string, so float comparisons are by bit pattern (NaN == NaN, +0 != -0).
const FloatMode = enum {
    none, // i32 collections
    f32_keyed, // f32 map/set: only arrays are float-labelled
    f32_list, // f32 list: sum/min/max scalars + arrays are floats
};

fn elementToF32(e: std.json.Value) f32 {
    return switch (e) {
        .string => |s| parseF32Label(s),
        .float => |f| @as(f32, @floatCast(f)),
        .integer => |i| @as(f32, @floatFromInt(i)),
        .number_string => |s| std.fmt.parseFloat(f32, s) catch @panic("bad float"),
        // {"bits":"0x.."} escape inside an assertion array.
        .object => parseF32Value(e),
        else => @panic("unexpected float array element"),
    };
}

// A numeric (bare-JSON-number) scalar expected value is an f32 (and must use
// the f32 formatter, matching TS) when: under f32_list any non-`size` scalar
// (sum/min/max); or under f32_keyed the key-typed scalars min/max. Other
// f32_keyed scalars (size, get_N, contains_N) stay i32.
fn isF32Scalar(mode: FloatMode, key: []const u8) bool {
    if (mode == .f32_list and !std.mem.eql(u8, key, "size")) return true;
    if (mode == .f32_keyed and
        (std.mem.eql(u8, key, "min") or std.mem.eql(u8, key, "max"))) return true;
    return false;
}

// Render an expected JSON assertion value into the same canonical string the
// runner emits for its computed value.
fn renderExpected(writer: anytype, v: std.json.Value, key: []const u8, mode: FloatMode) !void {
    switch (v) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| {
            if (isF32Scalar(mode, key)) {
                try writeF32(writer, @as(f32, @floatFromInt(i)));
            } else {
                try writer.print("{d}", .{i});
            }
        },
        .float => |f| {
            // JSON numbers with a fractional part decode as .float.
            if (isF32Scalar(mode, key)) {
                try writeF32(writer, @as(f32, @floatCast(f)));
            } else {
                try writer.print("{d}", .{@as(i64, @intFromFloat(f))});
            }
        },
        .number_string => |s| try writer.writeAll(s),
        // A string expected value is either a plain string scalar (mode .none,
        // e.g. Range lower_bound_type: "closed") or a float label ("NaN", "max":
        // "NaN") under a float mode. Mirrors the Rust runner's render_expected.
        .string => |s| {
            if (mode == .none) {
                try writer.writeAll(s);
            } else {
                try writeF32(writer, parseF32Label(s));
            }
        },
        // Bits-escape float scalar (e.g. sum: {"bits":"0xffc00000"}).
        .object => {
            if (mode != .none) {
                try writeF32(writer, parseF32Value(v));
            } else {
                try writer.writeAll("{object}");
            }
        },
        .array => |arr| {
            try writer.writeAll("[");
            for (arr.items, 0..) |e, i| {
                if (i > 0) try writer.writeAll(",");
                switch (mode) {
                    .f32_keyed => {
                        try writer.writeAll("\"");
                        try writeF32(writer, elementToF32(e));
                        try writer.writeAll("\"");
                    },
                    .f32_list => try writeF32(writer, elementToF32(e)),
                    // i32 arrays may carry null elements (NavigableMap poll
                    // logs: e.g. poll_first_keys [7, null]).
                    .none => switch (e) {
                        .null => try writer.writeAll("null"),
                        .integer => |n| try writer.print("{d}", .{n}),
                        else => try writer.print("{d}", .{e.integer}),
                    },
                }
            }
            try writer.writeAll("]");
        },
    }
}

// Compute one assertion, print the canonical `key: value` line, and compare
// against the expected JSON value. Unrecognised keys (UNKNOWN_ASSERTION:*)
// are skipped silently per the README unknown-assertion-skip rule.
fn emitAssertion(
    scenario_name: []const u8,
    key: []const u8,
    expected: std.json.Value,
    coll: *Collection,
    other_coll: ?*Collection,
    mode: FloatMode,
    log: *const NavLog,
    query: ?I32Range,
    allocator: Allocator,
    stdout: anytype,
) !void {
    var cbuf = std.array_list.Managed(u8).init(allocator);
    defer cbuf.deinit();
    try evaluateAssertion(key, coll, other_coll, log, query, allocator, cbuf.writer());
    const computed = cbuf.items;
    if (std.mem.startsWith(u8, computed, "UNKNOWN_ASSERTION:")) return;

    try stdout.print("{s}: {s}\n", .{ key, computed });

    var ebuf = std.array_list.Managed(u8).init(allocator);
    defer ebuf.deinit();
    try renderExpected(ebuf.writer(), expected, key, mode);
    if (!std.mem.eql(u8, computed, ebuf.items) and !looseNanMatch(expected, mode, computed)) {
        try stdout.print("FAIL {s} {s}: expected={s} got={s}\n", .{ scenario_name, key, ebuf.items, computed });
        any_fail = true;
    }
}

// Parse a signed base-10 i32 suffix after `prefix` (e.g. "floor_-2147483648").
// Leading `-` and the full i32 range are accepted. Returns null if the key
// does not start with `prefix` or the suffix is not a valid i32.
fn parseSignedSuffix(key: []const u8, prefix: []const u8) ?i32 {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    return std.fmt.parseInt(i32, key[prefix.len..], 10) catch null;
}

// rank_<k>: matches EXACTLY ^rank_(-?[0-9]+)$. The suffix is a signed base-10
// i32 (leading `-` allowed and the full i32 range); a leading `+` or any other
// non-digit is rejected (returns null → skip). std.fmt.parseInt already rejects
// a `+`-prefixed suffix here because we only admit an optional leading `-`.
fn parseRankSuffix(key: []const u8) ?i32 {
    const prefix = "rank_";
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const rest = key[prefix.len..];
    if (rest.len == 0) return null;
    // Reject a leading `+` explicitly (parseInt would otherwise accept it).
    if (rest[0] == '+') return null;
    return std.fmt.parseInt(i32, rest, 10) catch null;
}

// select_<i>: matches EXACTLY ^select_([0-9]+)$. The suffix is a NON-NEGATIVE
// decimal index — a `-`, `+`, or any non-digit is rejected so the functional
// select_<pred> keys (select_gt_N, select_even) are never misclassified.
fn parseSelectIndex(key: []const u8) ?usize {
    const prefix = "select_";
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const rest = key[prefix.len..];
    if (rest.len == 0) return null;
    for (rest) |c| {
        if (c < '0' or c > '9') return null;
    }
    return std.fmt.parseInt(usize, rest, 10) catch null;
}

fn writeOptArray(writer: anytype, items: []const ?i32) !void {
    try writer.writeAll("[");
    for (items, 0..) |item, i| {
        if (i > 0) try writer.writeAll(",");
        if (item) |x| try writer.print("{d}", .{x}) else try writer.writeAll("null");
    }
    try writer.writeAll("]");
}

// NavigableMap/Set assertion keys. Returns true when `key` is a nav-specific
// key this function fully handled (writing the canonical value into `writer`);
// false when `key` is not nav-specific, so the caller falls through to the
// generic assertion handler (size/is_empty/contains_/sorted_keys/...).
// Descending arrays are emitted DESCENDING (never re-sorted). Unknown nav-shape
// keys whose range data is missing are reported via the false return (skip).
fn evalNavAssertion(
    key: []const u8,
    coll: *Collection,
    log: *const NavLog,
    query: ?I32Range,
    allocator: Allocator,
    writer: anytype,
) !bool {
    // floor_<k> / ceiling_<k> / lower_<k> / higher_<k>: signed i32 suffix.
    inline for (.{ "floor_", "ceiling_", "lower_", "higher_" }) |prefix| {
        if (parseSignedSuffix(key, prefix)) |k| {
            const r: ?i32 = switch (coll.*) {
                .tree_map => |*m| if (std.mem.eql(u8, prefix, "floor_"))
                    m.floorKey(k)
                else if (std.mem.eql(u8, prefix, "ceiling_"))
                    m.ceilingKey(k)
                else if (std.mem.eql(u8, prefix, "lower_"))
                    m.lowerKey(k)
                else
                    m.higherKey(k),
                .tree_set => |*s| if (std.mem.eql(u8, prefix, "floor_"))
                    s.floor(k)
                else if (std.mem.eql(u8, prefix, "ceiling_"))
                    s.ceiling(k)
                else if (std.mem.eql(u8, prefix, "lower_"))
                    s.lower(k)
                else
                    s.higher(k),
                else => null,
            };
            try writeOptI32(writer, r);
            return true;
        }
    }

    // Order statistics (rank / select; see spec/features/rank-select.md).
    //
    // rank_<k> matches EXACTLY ^rank_(-?[0-9]+)$ (signed i32 suffix, leading
    // `+` rejected); select_<i> matches EXACTLY ^select_([0-9]+)$ (non-negative
    // decimal index). The strict parse keeps the functional select_<pred> keys
    // (select_gt_N, select_even, …) — handled by the generic dispatcher — from
    // being misclassified as the order-statistic select.
    if (parseRankSuffix(key)) |k| {
        const r: usize = switch (coll.*) {
            .tree_map => |*m| m.rank(k),
            .tree_set => |*s| s.rank(k),
            else => return false,
        };
        try writeI64(writer, @intCast(r));
        return true;
    }
    if (parseSelectIndex(key)) |i| {
        const r: ?i32 = switch (coll.*) {
            .tree_map => |*m| m.selectKey(i),
            .tree_set => |*s| s.select(i),
            else => return false,
        };
        try writeOptI32(writer, r);
        return true;
    }

    // first/last (map: first_key/last_key; set: first/last).
    if (std.mem.eql(u8, key, "first_key")) {
        switch (coll.*) {
            .tree_map => |*m| try writeOptI32(writer, m.firstKey()),
            else => return false,
        }
        return true;
    }
    if (std.mem.eql(u8, key, "last_key")) {
        switch (coll.*) {
            .tree_map => |*m| try writeOptI32(writer, m.lastKey()),
            else => return false,
        }
        return true;
    }
    if (std.mem.eql(u8, key, "first")) {
        switch (coll.*) {
            .tree_set => |*s| try writeOptI32(writer, s.first()),
            else => return false,
        }
        return true;
    }
    if (std.mem.eql(u8, key, "last")) {
        switch (coll.*) {
            .tree_set => |*s| try writeOptI32(writer, s.last()),
            else => return false,
        }
        return true;
    }

    // Full descending iteration over ALL keys/elements (emitted DESCENDING).
    if (std.mem.eql(u8, key, "descending_keys")) {
        switch (coll.*) {
            .tree_map => |*m| {
                const d = try m.descendingKeys(allocator);
                defer allocator.free(d);
                try writeArray(writer, d);
            },
            else => return false,
        }
        return true;
    }
    if (std.mem.eql(u8, key, "descending_elements")) {
        switch (coll.*) {
            .tree_set => |*s| {
                const d = try s.descending(allocator);
                defer allocator.free(d);
                try writeArray(writer, d);
            },
            else => return false,
        }
        return true;
    }

    // range_* assertions reference the scenario-level `query` range. With no
    // query the key is unknown for this scenario -> not handled (skip).
    if (std.mem.eql(u8, key, "range_keys") or std.mem.eql(u8, key, "range_elements") or
        std.mem.eql(u8, key, "range_keys_desc") or std.mem.eql(u8, key, "range_elements_desc") or
        std.mem.eql(u8, key, "range_size"))
    {
        const q = query orelse return false;
        if (std.mem.eql(u8, key, "range_keys")) {
            switch (coll.*) {
                .tree_map => |*m| {
                    const r = try m.rangeKeysIn(q, allocator);
                    defer allocator.free(r);
                    try writeArray(writer, r);
                },
                else => return false,
            }
        } else if (std.mem.eql(u8, key, "range_elements")) {
            switch (coll.*) {
                .tree_set => |*s| {
                    const r = try s.rangeElements(q, allocator);
                    defer allocator.free(r);
                    try writeArray(writer, r);
                },
                else => return false,
            }
        } else if (std.mem.eql(u8, key, "range_keys_desc")) {
            switch (coll.*) {
                .tree_map => |*m| {
                    const r = try m.descendingRangeKeys(q, allocator);
                    defer allocator.free(r);
                    try writeArray(writer, r);
                },
                else => return false,
            }
        } else if (std.mem.eql(u8, key, "range_elements_desc")) {
            switch (coll.*) {
                .tree_set => |*s| {
                    const r = try s.descendingRangeElements(q, allocator);
                    defer allocator.free(r);
                    try writeArray(writer, r);
                },
                else => return false,
            }
        } else { // range_size
            const n: i64 = switch (coll.*) {
                .tree_map => |*m| blk: {
                    const r = try m.rangeKeysIn(q, allocator);
                    defer allocator.free(r);
                    break :blk @intCast(r.len);
                },
                .tree_set => |*s| blk: {
                    const r = try s.rangeElements(q, allocator);
                    defer allocator.free(r);
                    break :blk @intCast(r.len);
                },
                else => return false,
            };
            try writeI64(writer, n);
        }
        return true;
    }

    // Result-log keys (replayed from execution order).
    if (std.mem.eql(u8, key, "poll_first_keys")) {
        try writeOptArray(writer, log.poll_first_keys.items);
        return true;
    }
    if (std.mem.eql(u8, key, "poll_last_keys")) {
        try writeOptArray(writer, log.poll_last_keys.items);
        return true;
    }
    if (std.mem.eql(u8, key, "poll_first_values")) {
        switch (coll.*) {
            .tree_map => try writeOptArray(writer, log.poll_first_values.items),
            else => return false, // sets have no values
        }
        return true;
    }
    if (std.mem.eql(u8, key, "poll_last_values")) {
        switch (coll.*) {
            .tree_map => try writeOptArray(writer, log.poll_last_values.items),
            else => return false,
        }
        return true;
    }
    if (std.mem.eql(u8, key, "remove_range_counts")) {
        try writeArray(writer, log.remove_range_counts.items);
        return true;
    }

    return false;
}

// Writes ONLY the canonical computed value for `key` into `writer` (no
// "key: " prefix, no trailing newline). Unknown keys write the sentinel
// "UNKNOWN_ASSERTION:<key>" which the caller treats as skip.
fn evaluateAssertion(
    key: []const u8,
    coll: *Collection,
    other_coll: ?*Collection,
    log: *const NavLog,
    query: ?I32Range,
    allocator: Allocator,
    writer: anytype,
) !void {
    // --- NavigableMap / NavigableSet (ordered tree navigation) ---
    // Point-nav and range_*/*descending assertions reflect the POST-operation
    // state (the harness applies all ops, then evaluates). Result-log keys
    // (poll_*, remove_range_counts) replay values recorded during execution.
    // Handled before the generic keys so the signed floor_/ceiling_/... suffix
    // does not collide with other prefix parses.
    {
        const is_tree = switch (coll.*) {
            .tree_map, .tree_set => true,
            else => false,
        };
        if (is_tree) {
            if (try evalNavAssertion(key, coll, log, query, allocator, writer)) return;
        }
    }

    // --- size ---
    if (std.mem.eql(u8, key, "size")) {
        const sz: i64 = @intCast(getCollectionSize(coll));
        try writeI64(writer, sz);
    }
    // --- is_empty ---
    else if (std.mem.eql(u8, key, "is_empty")) {
        try writeBool(writer, getCollectionSize(coll) == 0);
    }
    // --- other_size ---
    else if (std.mem.eql(u8, key, "other_size")) {
        if (other_coll) |oc| {
            const sz: i64 = @intCast(getCollectionSize(oc));
            try writeI64(writer, sz);
        } else {
            try writeNull(writer);
        }
    }
    // --- size_distinct (bag) ---
    else if (std.mem.eql(u8, key, "size_distinct")) {
        switch (coll.*) {
            .hash_bag => |*b| {
                const sz: i64 = @intCast(b.sizeDistinct());
                try writeI64(writer, sz);
            },
            else => try writeNull(writer),
        }
    }
    // --- sum (widened i64, via the production I32ArrayList.sum()) ---
    // List sum() widens into an i64 accumulator (IntList.sum(): long parity)
    // and does NOT wrap at i32 — see algorithms.md "Integer overflow contract"
    // and scenarios/06-overflow/i32_sum_overflow.json.
    else if (std.mem.eql(u8, key, "sum")) {
        switch (coll.*) {
            .array_list => |*l| try writeI64(writer, l.sum()),
            else => try writeNull(writer),
        }
    }
    // --- min ---
    else if (std.mem.eql(u8, key, "min")) {
        switch (coll.*) {
            .array_list => |*l| {
                if (l.min()) |v| try writeI32(writer, v) else try writeNull(writer);
            },
            .tree_set => |*s| {
                if (s.min()) |v| try writeI32(writer, v) else try writeNull(writer);
            },
            .tree_map => |*m| {
                if (m.min()) |entry| try writeI32(writer, entry.key) else try writeNull(writer);
            },
            else => try writeNull(writer),
        }
    }
    // --- max ---
    else if (std.mem.eql(u8, key, "max")) {
        switch (coll.*) {
            .array_list => |*l| {
                if (l.max()) |v| try writeI32(writer, v) else try writeNull(writer);
            },
            .tree_set => |*s| {
                if (s.max()) |v| try writeI32(writer, v) else try writeNull(writer);
            },
            .tree_map => |*m| {
                if (m.max()) |entry| try writeI32(writer, entry.key) else try writeNull(writer);
            },
            else => try writeNull(writer),
        }
    }
    // --- get_N (map) ---
    else if (parseThreshold(key, "get_") != null and !std.mem.startsWith(u8, key, "get_at_")) {
        const k = parseThreshold(key, "get_").?;
        switch (coll.*) {
            .hash_map => |*m| {
                if (m.get(k)) |v| try writeI32(writer, v) else try writeNull(writer);
            },
            .tree_map => |*m| {
                if (m.get(k)) |v| try writeI32(writer, v) else try writeNull(writer);
            },
            else => try writeNull(writer),
        }
    }
    // --- get_at_N (list) ---
    else if (parseThreshold(key, "get_at_") != null) {
        const idx: usize = @intCast(parseThreshold(key, "get_at_").?);
        switch (coll.*) {
            .array_list => |*l| {
                if (l.get(idx)) |v| try writeI32(writer, v) else try writeNull(writer);
            },
            else => try writeNull(writer),
        }
    }
    // --- contains_N ---
    else if (parseThreshold(key, "contains_") != null) {
        const val = parseThreshold(key, "contains_").?;
        switch (coll.*) {
            .hash_map => |*m| try writeBool(writer, m.containsKey(val)),
            .tree_map => |*m| try writeBool(writer, m.containsKey(val)),
            .array_list => |*l| try writeBool(writer, l.contains(val)),
            .hash_set => |*s| try writeBool(writer, s.contains(val)),
            .hash_bag => |*b| try writeBool(writer, b.contains(val)),
            .tree_set => |*s| try writeBool(writer, s.contains(val)),
            .array_stack => |*s| try writeBool(writer, s.contains(val)),
        }
    }
    // --- occurrences_N (bag) ---
    else if (parseThreshold(key, "occurrences_") != null) {
        const val = parseThreshold(key, "occurrences_").?;
        switch (coll.*) {
            .hash_bag => |*b| {
                const occ: i64 = @intCast(b.occurrencesOf(val));
                try writeI64(writer, occ);
            },
            else => try writeNull(writer),
        }
    }
    // --- sorted_keys (map) ---
    else if (std.mem.eql(u8, key, "sorted_keys")) {
        switch (coll.*) {
            .hash_map => |*m| {
                const keys = try m.keysToSlice(allocator);
                defer allocator.free(keys);
                try writeSortedArray(writer, keys);
            },
            .tree_map => |*m| {
                // TreeMap keys are already sorted
                try writeArray(writer, m.keysSlice());
            },
            else => try writeNull(writer),
        }
    }
    // --- sorted_values (map) ---
    else if (std.mem.eql(u8, key, "sorted_values")) {
        switch (coll.*) {
            .hash_map => |*m| {
                const vals = try m.valuesToSlice(allocator);
                defer allocator.free(vals);
                try writeSortedArray(writer, vals);
            },
            .tree_map => |*m| {
                // TreeMap values are sorted by key order, which is what we want
                try writeArray(writer, m.valuesSlice());
            },
            else => try writeNull(writer),
        }
    }
    // --- to_sorted_array ---
    else if (std.mem.eql(u8, key, "to_sorted_array")) {
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        try writeSortedArray(writer, items);
    }
    // --- inject_into_sum (i32 wrapping fold, via production injectInto) ---
    // injectInto with a + reduction accumulates in the i32 seed type and
    // wraps two's-complement at i32 (algorithms.md "Integer overflow
    // contract"). Routed through the production I32ArrayList.injectInto.
    else if (std.mem.eql(u8, key, "inject_into_sum")) {
        switch (coll.*) {
            .array_list => |*l| try writeI32(writer, l.injectInto(undefined, 0, injectAddWrapI32)),
            .array_stack => |*s| {
                var acc: i32 = 0;
                for (s.toSlice()) |item| acc = injectAddWrapI32(undefined, acc, item);
                try writeI32(writer, acc);
            },
            else => try writeNull(writer),
        }
    }
    // --- inject_into_product (i32 wrapping fold, via production injectInto) ---
    else if (std.mem.eql(u8, key, "inject_into_product")) {
        switch (coll.*) {
            .array_list => |*l| try writeI32(writer, l.injectInto(undefined, 1, injectMulWrapI32)),
            .array_stack => |*s| {
                var acc: i32 = 1;
                for (s.toSlice()) |item| acc = injectMulWrapI32(undefined, acc, item);
                try writeI32(writer, acc);
            },
            else => try writeNull(writer),
        }
    }
    // --- product / inject_into_wrapping_product (wrapping i32) ---
    // scenarios/06-overflow/i32_multiply_overflow.json keys this as
    // "product"; Rust's validate also handles "inject_into_wrapping_product"
    // as the same wrapping form. Mirror that here.
    else if (std.mem.eql(u8, key, "product") or std.mem.eql(u8, key, "inject_into_wrapping_product")) {
        switch (coll.*) {
            .array_list => |*l| {
                var acc: i32 = 1;
                for (l.toSlice()) |item| acc *%= item;
                try writeI32(writer, acc);
            },
            .array_stack => |*s| {
                var acc: i32 = 1;
                for (s.toSlice()) |item| acc *%= item;
                try writeI32(writer, acc);
            },
            else => try writeNull(writer),
        }
    }
    // --- select_gt_N ---
    else if (std.mem.startsWith(u8, key, "select_gt_")) {
        const threshold = parseThreshold(key, "select_gt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        // Zig 0.15 split ArrayList into Unmanaged (std.ArrayList) and Managed
        // (std.array_list.Managed). The allocator-carrying init(alloc) form
        // now lives on Managed; unmanaged uses .empty / append(alloc, item).
        var result = std.array_list.Managed(i32).init(allocator);
        defer result.deinit();
        for (items) |item| {
            if (item > threshold) try result.append(item);
        }
        const slice = result.items;
        const copy = try allocator.alloc(i32, slice.len);
        defer allocator.free(copy);
        @memcpy(copy, slice);
        try writeSortedArray(writer, copy);
    }
    // --- reject_gt_N ---
    else if (std.mem.startsWith(u8, key, "reject_gt_")) {
        const threshold = parseThreshold(key, "reject_gt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        // Zig 0.15 split ArrayList into Unmanaged (std.ArrayList) and Managed
        // (std.array_list.Managed). The allocator-carrying init(alloc) form
        // now lives on Managed; unmanaged uses .empty / append(alloc, item).
        var result = std.array_list.Managed(i32).init(allocator);
        defer result.deinit();
        for (items) |item| {
            if (item <= threshold) try result.append(item);
        }
        const slice = result.items;
        const copy = try allocator.alloc(i32, slice.len);
        defer allocator.free(copy);
        @memcpy(copy, slice);
        try writeSortedArray(writer, copy);
    }
    // --- detect_gt_N ---
    else if (std.mem.startsWith(u8, key, "detect_gt_")) {
        const threshold = parseThreshold(key, "detect_gt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var found: ?i32 = null;
        for (items) |item| {
            if (item > threshold) {
                found = item;
                break;
            }
        }
        if (found) |v| try writeI32(writer, v) else try writeNull(writer);
    }
    // --- count_gt_N ---
    else if (std.mem.startsWith(u8, key, "count_gt_")) {
        const threshold = parseThreshold(key, "count_gt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var c: i64 = 0;
        for (items) |item| {
            if (item > threshold) c += 1;
        }
        try writeI64(writer, c);
    }
    // --- count_lt_N ---
    else if (std.mem.startsWith(u8, key, "count_lt_")) {
        const threshold = parseThreshold(key, "count_lt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var c: i64 = 0;
        for (items) |item| {
            if (item < threshold) c += 1;
        }
        try writeI64(writer, c);
    }
    // --- count_even ---
    else if (std.mem.eql(u8, key, "count_even")) {
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var c: i64 = 0;
        for (items) |item| {
            if (@rem(item, 2) == 0) c += 1;
        }
        try writeI64(writer, c);
    }
    // --- count_odd ---
    else if (std.mem.eql(u8, key, "count_odd")) {
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var c: i64 = 0;
        for (items) |item| {
            if (@rem(item, 2) != 0) c += 1;
        }
        try writeI64(writer, c);
    }
    // --- any_satisfy_even ---
    else if (std.mem.eql(u8, key, "any_satisfy_even")) {
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var found = false;
        for (items) |item| {
            if (@rem(item, 2) == 0) {
                found = true;
                break;
            }
        }
        try writeBool(writer, found);
    }
    // --- all_satisfy_even ---
    else if (std.mem.eql(u8, key, "all_satisfy_even")) {
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var all = true;
        for (items) |item| {
            if (@rem(item, 2) != 0) {
                all = false;
                break;
            }
        }
        try writeBool(writer, all);
    }
    // --- none_satisfy_odd ---
    else if (std.mem.eql(u8, key, "none_satisfy_odd")) {
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var none = true;
        for (items) |item| {
            if (@rem(item, 2) != 0) {
                none = false;
                break;
            }
        }
        try writeBool(writer, none);
    }
    // --- any_satisfy_gt_N ---
    else if (std.mem.startsWith(u8, key, "any_satisfy_gt_")) {
        const threshold = parseThreshold(key, "any_satisfy_gt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var found = false;
        for (items) |item| {
            if (item > threshold) {
                found = true;
                break;
            }
        }
        try writeBool(writer, found);
    }
    // --- all_satisfy_gt_N ---
    else if (std.mem.startsWith(u8, key, "all_satisfy_gt_")) {
        const threshold = parseThreshold(key, "all_satisfy_gt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var all = true;
        for (items) |item| {
            if (item <= threshold) {
                all = false;
                break;
            }
        }
        try writeBool(writer, all);
    }
    // --- none_satisfy_gt_N ---
    else if (std.mem.startsWith(u8, key, "none_satisfy_gt_")) {
        const threshold = parseThreshold(key, "none_satisfy_gt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var none = true;
        for (items) |item| {
            if (item > threshold) {
                none = false;
                break;
            }
        }
        try writeBool(writer, none);
    }
    // --- none_satisfy_lt_N ---
    else if (std.mem.startsWith(u8, key, "none_satisfy_lt_")) {
        const threshold = parseThreshold(key, "none_satisfy_lt_").?;
        const items = try getItemSlice(coll, allocator);
        defer allocator.free(items);
        var none = true;
        for (items) |item| {
            if (item < threshold) {
                none = false;
                break;
            }
        }
        try writeBool(writer, none);
    }
    // --- Set operations: union_sorted, union_size ---
    else if (std.mem.eql(u8, key, "union_sorted") or std.mem.eql(u8, key, "union_size")) {
        if (other_coll) |oc| {
            switch (coll.*) {
                .hash_set => |*s| {
                    switch (oc.*) {
                        .hash_set => |*os| {
                            var result = try s.setUnion(os);
                            defer result.deinit();
                            if (std.mem.eql(u8, key, "union_size")) {
                                const sz: i64 = @intCast(result.len());
                                try writeI64(writer, sz);
                            } else {
                                const slice = try result.toSlice(allocator);
                                defer allocator.free(slice);
                                try writeSortedArray(writer, slice);
                            }
                        },
                        else => try writeNull(writer),
                    }
                },
                else => try writeNull(writer),
            }
        } else {
            try writeNull(writer);
        }
    }
    // --- intersect_sorted, intersect_size ---
    else if (std.mem.eql(u8, key, "intersect_sorted") or std.mem.eql(u8, key, "intersect_size")) {
        if (other_coll) |oc| {
            switch (coll.*) {
                .hash_set => |*s| {
                    switch (oc.*) {
                        .hash_set => |*os| {
                            var result = try s.intersect(os);
                            defer result.deinit();
                            if (std.mem.eql(u8, key, "intersect_size")) {
                                const sz: i64 = @intCast(result.len());
                                try writeI64(writer, sz);
                            } else {
                                const slice = try result.toSlice(allocator);
                                defer allocator.free(slice);
                                try writeSortedArray(writer, slice);
                            }
                        },
                        else => try writeNull(writer),
                    }
                },
                else => try writeNull(writer),
            }
        } else {
            try writeNull(writer);
        }
    }
    // --- difference_sorted, difference_size ---
    else if (std.mem.eql(u8, key, "difference_sorted") or std.mem.eql(u8, key, "difference_size")) {
        if (other_coll) |oc| {
            switch (coll.*) {
                .hash_set => |*s| {
                    switch (oc.*) {
                        .hash_set => |*os| {
                            var result = try s.difference(os);
                            defer result.deinit();
                            if (std.mem.eql(u8, key, "difference_size")) {
                                const sz: i64 = @intCast(result.len());
                                try writeI64(writer, sz);
                            } else {
                                const slice = try result.toSlice(allocator);
                                defer allocator.free(slice);
                                try writeSortedArray(writer, slice);
                            }
                        },
                        else => try writeNull(writer),
                    }
                },
                else => try writeNull(writer),
            }
        } else {
            try writeNull(writer);
        }
    }
    // --- symmetric_difference_sorted, symmetric_difference_size ---
    else if (std.mem.eql(u8, key, "symmetric_difference_sorted") or std.mem.eql(u8, key, "symmetric_difference_size")) {
        if (other_coll) |oc| {
            switch (coll.*) {
                .hash_set => |*s| {
                    switch (oc.*) {
                        .hash_set => |*os| {
                            var result = try s.symmetricDifference(os);
                            defer result.deinit();
                            if (std.mem.eql(u8, key, "symmetric_difference_size")) {
                                const sz: i64 = @intCast(result.len());
                                try writeI64(writer, sz);
                            } else {
                                const slice = try result.toSlice(allocator);
                                defer allocator.free(slice);
                                try writeSortedArray(writer, slice);
                            }
                        },
                        else => try writeNull(writer),
                    }
                },
                else => try writeNull(writer),
            }
        } else {
            try writeNull(writer);
        }
    }
    // --- unknown key ---
    else {
        try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
    }
}

fn getCollectionSize(coll: *Collection) usize {
    return switch (coll.*) {
        .hash_map => |*m| m.len(),
        .array_list => |*l| l.len(),
        .hash_set => |*s| s.len(),
        .hash_bag => |*b| b.len(),
        .tree_set => |*s| s.len(),
        .tree_map => |*m| m.len(),
        .array_stack => |*s| s.len(),
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: validate <scenario.json>\n", .{});
        std.process.exit(1);
    }

    const file_path = args[1];
    const file_data = try std.fs.cwd().readFileAlloc(allocator, file_path, 100 * 1024 * 1024);
    defer allocator.free(file_data);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, file_data, .{});
    defer parsed.deinit();
    const root = parsed.value.object;

    const name = root.get("name").?.string;
    const collection_type = root.get("collection").?.string;
    const construction = if (root.get("construction")) |c| c.string else "";
    const operations = root.get("operations").?.array;

    // f32 collections take a separate dispatch path: the Collection union
    // above is i32-only and the API surface differs (bit-pattern eq, total
    // ordering for sort) enough that mixing them in is uglier than two
    // sibling paths.
    var stdout_buf: [16 * 1024]u8 = undefined;
    var stdout_w = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_w.interface;
    if (std.mem.eql(u8, collection_type, "HashMap<f32, i32>")) {
        try runF32HashMap(name, operations, root.get("assertions").?.object, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "HashSet<f32>")) {
        try runF32HashSet(name, operations, root.get("assertions").?.object, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "TreeSet<f32>")) {
        try runF32TreeSet(name, operations, root.get("assertions").?.object, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "ArrayList<f32>")) {
        try runF32ArrayList(name, operations, root.get("assertions").?.object, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "HashMap<i64, i32>")) {
        try runI64HashMap(name, operations, root.get("assertions").?.object, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "ListMultimap<i64, i32>")) {
        var m = if (std.mem.eql(u8, construction, "fromSortedKeyValues")) blk: {
            const pairs = try allocI64Pairs(allocator, operations);
            defer allocator.free(pairs.keys);
            defer allocator.free(pairs.vals);
            break :blk try I64I32ListMultimap.fromSortedKeyValues(allocator, pairs.keys, pairs.vals);
        } else I64I32ListMultimap.init(allocator);
        defer m.deinit();
        try runI64Multimap(@TypeOf(m), &m, name, operations, root.get("assertions").?.object, allocator, stdout, !std.mem.eql(u8, construction, "fromSortedKeyValues"));
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "SetMultimap<i64, i32>")) {
        var m = if (std.mem.eql(u8, construction, "fromSortedKeyValues")) blk: {
            const pairs = try allocI64Pairs(allocator, operations);
            defer allocator.free(pairs.keys);
            defer allocator.free(pairs.vals);
            break :blk try I64I32SetMultimap.fromSortedKeyValues(allocator, pairs.keys, pairs.vals);
        } else I64I32SetMultimap.init(allocator);
        defer m.deinit();
        try runI64Multimap(@TypeOf(m), &m, name, operations, root.get("assertions").?.object, allocator, stdout, !std.mem.eql(u8, construction, "fromSortedKeyValues"));
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "Range<i32>")) {
        try runRange(name, operations, root.get("assertions").?.object, root, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "ImmutableSortedMap<i32, i32>")) {
        try runImmutableSortedMap(name, operations, root.get("assertions").?.object, root, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "ImmutableSortedSet<i32>")) {
        try runImmutableSortedSet(name, operations, root.get("assertions").?.object, root, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, collection_type, "HashPipeline")) {
        try runHashPipeline(name, operations, root.get("assertions").?.object, allocator, stdout);
        try stdout.flush();
        if (any_fail) std.process.exit(1);
        return;
    }

    const kind = parseCollectionKind(collection_type) orelse {
        // Forward-compat (README "unknown collection kinds skip"): a runner that
        // does not understand a collection kind must SKIP, not fail, so newer
        // scenarios never break an older runner. Mirrors the unknown-assertion
        // skip in emitAssertion / the Rust runner's run() match arm.
        std.debug.print("skip: unsupported collection kind (forward-compat): {s}\n", .{collection_type});
        return;
    };

    // Initialize main collection
    var coll: Collection = if (std.mem.eql(u8, collection_type, "HashMap<i32, i32>") and std.mem.eql(u8, construction, "bulkLoadExact")) blk: {
        const pairs = try allocI32Pairs(allocator, operations);
        defer allocator.free(pairs.keys);
        defer allocator.free(pairs.vals);
        break :blk .{ .hash_map = try I32I32HashMap.bulkLoadExact(allocator, pairs.keys, pairs.vals, pairs.keys.len, .err) };
    } else if (std.mem.eql(u8, collection_type, "TreeMap<i32, i32>") and std.mem.eql(u8, construction, "fromSorted")) blk: {
        const pairs = try allocI32Pairs(allocator, operations);
        defer allocator.free(pairs.keys);
        defer allocator.free(pairs.vals);
        break :blk .{ .tree_map = try I32I32TreeMap.fromSorted(allocator, pairs.keys, pairs.vals, .err) };
    } else try initCollection(kind, allocator);
    defer deinitCollection(&coll);

    // Apply operations. The NavLog records poll/remove_range return values in
    // execution order for the NavigableMap/Set result-log assertion keys.
    var log: NavLog = .{};
    defer log.deinit(allocator);
    if (construction.len == 0) {
        for (operations.items) |op| {
            try applyOperation(&coll, op, &log, allocator);
        }
    }

    // The optional scenario-level `query` range names the range that range_*
    // assertions refer to (same builder-op shape as 10-range / remove_range).
    const query: ?I32Range = if (root.get("query")) |q| buildRangeFromObj(q.object) else null;

    // Initialize "other" collection if present (for set operations). Its own
    // NavLog is discarded — `other` is never the assertion subject for nav.
    var other_coll: ?Collection = null;
    if (root.get("other")) |other_json| {
        const other_obj = other_json.object;
        const other_type = other_obj.get("collection").?.string;
        const other_kind = parseCollectionKind(other_type) orelse {
            std.debug.print("Unknown other collection type: {s}\n", .{other_type});
            std.process.exit(1);
        };
        other_coll = try initCollection(other_kind, allocator);
        var other_log: NavLog = .{};
        defer other_log.deinit(allocator);
        const other_ops = other_obj.get("operations").?.array;
        for (other_ops.items) |op| {
            try applyOperation(&other_coll.?, op, &other_log, allocator);
        }
    }
    defer {
        if (other_coll != null) deinitCollection(&other_coll.?);
    }

    // Output header (reusing the stdout writer set up above for the f32
    // dispatch path).
    defer stdout.flush() catch {};
    try stdout.print("=== scenario: {s} ===\n", .{name});

    // Process assertions in order
    const assertions = root.get("assertions").?.object;
    // std.json.ObjectMap preserves insertion order
    for (assertions.keys(), assertions.values()) |key, expected| {
        // Scenario authors use "comment" as a doc string; the other ports
        // (Rust, Go) skip it. Treat it the same way here so harness diffs
        // line up.
        if (std.mem.eql(u8, key, "comment")) continue;
        const other_ptr: ?*Collection = if (other_coll != null) &other_coll.? else null;
        try emitAssertion(name, key, expected, &coll, other_ptr, .none, &log, query, allocator, stdout);
    }

    if (any_fail) {
        try stdout.flush();
        std.process.exit(1);
    }
}

// ── Range<i32> runner ────────────────────────────────────────────────────────
//
// The Bound/Range value model (spec/features/bound-range.md). Exactly ONE
// constructor op builds the range under test; an optional "other" block (same
// single-builder shape) supplies the second range for binary ops. Routed
// through the production I32Range — every assertion is proved against the real
// cut algebra, not re-derived here. Direct translation of the Rust runner's
// run_range / eval_range_assertion (mapdb-rust/src/bin/validate.rs).

fn buildRange(ops: std.json.Array) I32Range {
    if (ops.items.len != 1) {
        @panic("Range<i32> scenario must have exactly one constructor op");
    }
    const op = ops.items[0].object;
    const op_name = op.get("op").?.string;
    if (std.mem.eql(u8, op_name, "closed")) {
        return I32Range.closed(jsonToI32(op.get("lower").?).?, jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "open")) {
        return I32Range.open(jsonToI32(op.get("lower").?).?, jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "closed_open")) {
        return I32Range.closedOpen(jsonToI32(op.get("lower").?).?, jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "open_closed")) {
        return I32Range.openClosed(jsonToI32(op.get("lower").?).?, jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "at_least")) {
        return I32Range.atLeast(jsonToI32(op.get("lower").?).?);
    } else if (std.mem.eql(u8, op_name, "greater_than")) {
        return I32Range.greaterThan(jsonToI32(op.get("lower").?).?);
    } else if (std.mem.eql(u8, op_name, "at_most")) {
        return I32Range.atMost(jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "less_than")) {
        return I32Range.lessThan(jsonToI32(op.get("upper").?).?);
    } else if (std.mem.eql(u8, op_name, "all")) {
        return I32Range.all();
    } else if (std.mem.eql(u8, op_name, "singleton")) {
        return I32Range.singleton(jsonToI32(op.get("value").?).?);
    }
    @panic("unknown range op");
}

fn writeBoundType(writer: anytype, bt: ?BoundType) !void {
    if (bt) |b| {
        switch (b) {
            .open => try writer.writeAll("open"),
            .closed => try writer.writeAll("closed"),
        }
    } else {
        try writeNull(writer);
    }
}

fn writeOptI32(writer: anytype, v: ?i32) !void {
    if (v) |x| try writeI32(writer, x) else try writeNull(writer);
}

fn runRange(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    root: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});

    const range = buildRange(operations);
    var other: ?I32Range = null;
    if (root.get("other")) |other_json| {
        const other_ops = other_json.object.get("operations").?.array;
        other = buildRange(other_ops);
    }

    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var cbuf = std.array_list.Managed(u8).init(allocator);
        defer cbuf.deinit();
        try evalRangeAssertion(key, range, other, cbuf.writer());
        const computed = cbuf.items;
        // Unknown assertion key -> skip silently (README forward-compat).
        if (std.mem.startsWith(u8, computed, "UNKNOWN_ASSERTION:")) continue;

        try writer.print("{s}: {s}\n", .{ key, computed });

        var ebuf = std.array_list.Managed(u8).init(allocator);
        defer ebuf.deinit();
        try renderExpected(ebuf.writer(), expected, key, .none);
        if (!std.mem.eql(u8, computed, ebuf.items)) {
            try writer.print("FAIL {s} {s}: expected={s} got={s}\n", .{ name, key, ebuf.items, computed });
            any_fail = true;
        }
    }
}

fn evalRangeAssertion(
    key: []const u8,
    range: I32Range,
    other: ?I32Range,
    writer: anytype,
) !void {
    // --- unary ---
    if (std.mem.eql(u8, key, "is_empty")) {
        try writeBool(writer, range.isEmpty());
    } else if (std.mem.eql(u8, key, "has_lower_bound")) {
        try writeBool(writer, range.hasLowerBound());
    } else if (std.mem.eql(u8, key, "has_upper_bound")) {
        try writeBool(writer, range.hasUpperBound());
    } else if (std.mem.eql(u8, key, "lower_bound_type")) {
        try writeBoundType(writer, range.lowerBoundType());
    } else if (std.mem.eql(u8, key, "upper_bound_type")) {
        try writeBoundType(writer, range.upperBoundType());
    } else if (std.mem.eql(u8, key, "lower_endpoint")) {
        try writeOptI32(writer, range.lowerEndpoint());
    } else if (std.mem.eql(u8, key, "upper_endpoint")) {
        try writeOptI32(writer, range.upperEndpoint());
    } else if (parseThreshold(key, "contains_") != null) {
        const n = parseThreshold(key, "contains_").?;
        try writeBool(writer, range.contains(n));
    }
    // --- binary ops: require "other" ---
    else if (std.mem.eql(u8, key, "encloses_other") and other != null) {
        try writeBool(writer, range.encloses(other.?));
    } else if (std.mem.eql(u8, key, "is_connected_other") and other != null) {
        try writeBool(writer, range.isConnected(other.?));
    } else if (std.mem.eql(u8, key, "span_lower") and other != null) {
        try writeOptI32(writer, range.span(other.?).lowerEndpoint());
    } else if (std.mem.eql(u8, key, "span_upper") and other != null) {
        try writeOptI32(writer, range.span(other.?).upperEndpoint());
    } else if (std.mem.eql(u8, key, "span_lower_type") and other != null) {
        try writeBoundType(writer, range.span(other.?).lowerBoundType());
    } else if (std.mem.eql(u8, key, "span_upper_type") and other != null) {
        try writeBoundType(writer, range.span(other.?).upperBoundType());
    } else if (std.mem.eql(u8, key, "intersection_is_none") and other != null) {
        try writeBool(writer, range.intersection(other.?) == null);
    } else if (std.mem.eql(u8, key, "intersection_is_empty") and other != null) {
        const v = if (range.intersection(other.?)) |i| i.isEmpty() else false;
        try writeBool(writer, v);
    } else if (std.mem.eql(u8, key, "intersection_lower") and other != null) {
        const v: ?i32 = if (range.intersection(other.?)) |i| i.lowerEndpoint() else null;
        try writeOptI32(writer, v);
    } else if (std.mem.eql(u8, key, "intersection_upper") and other != null) {
        const v: ?i32 = if (range.intersection(other.?)) |i| i.upperEndpoint() else null;
        try writeOptI32(writer, v);
    } else if (std.mem.eql(u8, key, "intersection_lower_type") and other != null) {
        const v: ?BoundType = if (range.intersection(other.?)) |i| i.lowerBoundType() else null;
        try writeBoundType(writer, v);
    } else if (std.mem.eql(u8, key, "intersection_upper_type") and other != null) {
        const v: ?BoundType = if (range.intersection(other.?)) |i| i.upperBoundType() else null;
        try writeBoundType(writer, v);
    } else if (std.mem.eql(u8, key, "intersection_has_lower_bound") and other != null) {
        const v = if (range.intersection(other.?)) |i| i.hasLowerBound() else false;
        try writeBool(writer, v);
    } else if (std.mem.eql(u8, key, "intersection_has_upper_bound") and other != null) {
        const v = if (range.intersection(other.?)) |i| i.hasUpperBound() else false;
        try writeBool(writer, v);
    }
    // --- unknown key ---
    else {
        try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
    }
}

// ── ImmutableSortedMap<i32,i32> / ImmutableSortedSet<i32> runners ───────────
//
// The compact immutable sorted map/set (spec/features/sorted-table-map.md).
// Routed through the PRODUCTION ImmutableI32I32SortedMap / ImmutableI32SortedSet
// — every assertion is proved against the real packed-array binary-search code,
// not re-derived here. Direct translation of the Rust runner's
// run_immutable_sorted_map / run_immutable_sorted_set (mapdb-rust/src/bin/validate.rs).
//
// Construction is a SINGLE `from_sorted` bulk op (no incremental put/add):
//   map: {"op":"from_sorted","keys":[...],"values":[...]}  (strictly ascending)
//   set: {"op":"from_sorted","elements":[...]}             (strictly ascending)
// Authoring rule (spec §"Cross-language test scenarios"): exactly ONE
// `from_sorted` op. Zero or multiple is a MALFORMED scenario -> SKIP it (do not
// silently apply the first, do not fail), pinning the behaviour so runner
// authors do not each invent their own. Scenarios in the suite are authored
// strictly-ascending, so production never traps here.

/// The single `from_sorted` op from a well-formed sorted-table scenario, or
/// `null` (malformed) -> the caller SKIPs. A sorted-table collection is built
/// by EXACTLY ONE bulk `from_sorted` op: the `operations` array must be that
/// one op and nothing else.
fn singleFromSorted(operations: std.json.Array) ?std.json.ObjectMap {
    if (operations.items.len != 1) return null;
    const obj = operations.items[0].object;
    const op_name = obj.get("op") orelse return null;
    if (op_name != .string) return null;
    if (!std.mem.eql(u8, op_name.string, "from_sorted")) return null;
    return obj;
}

/// Parse a JSON array of i32 into a caller-owned slice.
fn jsonI32Array(arr: std.json.Array, allocator: Allocator) ![]i32 {
    const out = try allocator.alloc(i32, arr.items.len);
    for (arr.items, 0..) |e, i| out[i] = jsonToI32(e).?;
    return out;
}

fn runImmutableSortedMap(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    root: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});
    const op = singleFromSorted(operations) orelse {
        // Malformed (zero or multiple from_sorted) -> SKIP, do not fail.
        std.debug.print("skip: malformed sorted-table scenario (expected exactly one from_sorted)\n", .{});
        return;
    };
    const keys = try jsonI32Array(op.get("keys").?.array, allocator);
    defer allocator.free(keys);
    const values = try jsonI32Array(op.get("values").?.array, allocator);
    defer allocator.free(values);
    var map = try ImmutableI32I32SortedMap.fromSorted(allocator, keys, values);
    defer map.deinit();

    const query: ?I32Range = if (root.get("query")) |q| buildRangeFromObj(q.object) else null;

    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var cbuf = std.array_list.Managed(u8).init(allocator);
        defer cbuf.deinit();
        try evalSortedMapAssertion(key, &map, query, allocator, cbuf.writer());
        const computed = cbuf.items;
        if (std.mem.startsWith(u8, computed, "UNKNOWN_ASSERTION:")) continue;

        try writer.print("{s}: {s}\n", .{ key, computed });
        var ebuf = std.array_list.Managed(u8).init(allocator);
        defer ebuf.deinit();
        try renderExpected(ebuf.writer(), expected, key, .none);
        if (!std.mem.eql(u8, computed, ebuf.items)) {
            try writer.print("FAIL {s} {s}: expected={s} got={s}\n", .{ name, key, ebuf.items, computed });
            any_fail = true;
        }
    }
}

fn evalSortedMapAssertion(
    key: []const u8,
    map: *const ImmutableI32I32SortedMap,
    query: ?I32Range,
    allocator: Allocator,
    writer: anytype,
) !void {
    // floor_/ceiling_/lower_/higher_<k>: signed i32 suffix.
    inline for (.{ "floor_", "ceiling_", "lower_", "higher_" }) |prefix| {
        if (parseSignedSuffix(key, prefix)) |k| {
            const r: ?i32 = if (std.mem.eql(u8, prefix, "floor_"))
                map.floorKey(k)
            else if (std.mem.eql(u8, prefix, "ceiling_"))
                map.ceilingKey(k)
            else if (std.mem.eql(u8, prefix, "lower_"))
                map.lowerKey(k)
            else
                map.higherKey(k);
            try writeOptI32(writer, r);
            return;
        }
    }
    if (parseRankSuffix(key)) |k| {
        try writeI64(writer, @intCast(map.rank(k)));
        return;
    }
    if (parseSelectIndex(key)) |i| {
        try writeOptI32(writer, map.selectKey(i));
        return;
    }

    if (std.mem.eql(u8, key, "size")) {
        try writeI64(writer, @intCast(map.len()));
    } else if (std.mem.eql(u8, key, "is_empty")) {
        try writeBool(writer, map.isEmpty());
    } else if (std.mem.eql(u8, key, "min") or std.mem.eql(u8, key, "first_key")) {
        try writeOptI32(writer, map.firstKey());
    } else if (std.mem.eql(u8, key, "max") or std.mem.eql(u8, key, "last_key")) {
        try writeOptI32(writer, map.lastKey());
    } else if (std.mem.eql(u8, key, "sorted_keys")) {
        // Stored keys are already strictly ascending; emit verbatim.
        try writeArray(writer, map.keysSlice());
    } else if (std.mem.eql(u8, key, "sorted_values")) {
        // values() iterates in ascending-KEY order; the suite's sorted_values
        // means "all values sorted ascending" (it cannot pin key-order
        // pairing — that is a native test), so sort a copy.
        const copy = try allocator.dupe(i32, map.valuesSlice());
        defer allocator.free(copy);
        try writeSortedArray(writer, copy);
    } else if (std.mem.eql(u8, key, "descending_keys")) {
        const d = try map.descendingKeys(allocator);
        defer allocator.free(d);
        try writeArray(writer, d);
    } else if (std.mem.eql(u8, key, "range_keys")) {
        const q = query orelse {
            try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
            return;
        };
        const r = try map.rangeKeys(q, allocator);
        defer allocator.free(r);
        try writeArray(writer, r);
    } else if (std.mem.eql(u8, key, "range_keys_desc")) {
        const q = query orelse {
            try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
            return;
        };
        const r = try map.descendingRangeKeys(q, allocator);
        defer allocator.free(r);
        try writeArray(writer, r);
    } else if (std.mem.eql(u8, key, "range_size")) {
        const q = query orelse {
            try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
            return;
        };
        const r = try map.rangeKeys(q, allocator);
        defer allocator.free(r);
        try writeI64(writer, @intCast(r.len));
    } else if (parseThreshold(key, "get_") != null and !std.mem.startsWith(u8, key, "get_at_")) {
        try writeOptI32(writer, map.get(parseThreshold(key, "get_").?));
    } else if (parseThreshold(key, "contains_") != null) {
        try writeBool(writer, map.containsKey(parseThreshold(key, "contains_").?));
    } else {
        try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
    }
}

fn runImmutableSortedSet(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    root: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});
    const op = singleFromSorted(operations) orelse {
        std.debug.print("skip: malformed sorted-table scenario (expected exactly one from_sorted)\n", .{});
        return;
    };
    const elements = try jsonI32Array(op.get("elements").?.array, allocator);
    defer allocator.free(elements);
    var set = try ImmutableI32SortedSet.fromSorted(allocator, elements);
    defer set.deinit();

    const query: ?I32Range = if (root.get("query")) |q| buildRangeFromObj(q.object) else null;

    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var cbuf = std.array_list.Managed(u8).init(allocator);
        defer cbuf.deinit();
        try evalSortedSetAssertion(key, &set, query, allocator, cbuf.writer());
        const computed = cbuf.items;
        if (std.mem.startsWith(u8, computed, "UNKNOWN_ASSERTION:")) continue;

        try writer.print("{s}: {s}\n", .{ key, computed });
        var ebuf = std.array_list.Managed(u8).init(allocator);
        defer ebuf.deinit();
        try renderExpected(ebuf.writer(), expected, key, .none);
        if (!std.mem.eql(u8, computed, ebuf.items)) {
            try writer.print("FAIL {s} {s}: expected={s} got={s}\n", .{ name, key, ebuf.items, computed });
            any_fail = true;
        }
    }
}

fn evalSortedSetAssertion(
    key: []const u8,
    set: *const ImmutableI32SortedSet,
    query: ?I32Range,
    allocator: Allocator,
    writer: anytype,
) !void {
    inline for (.{ "floor_", "ceiling_", "lower_", "higher_" }) |prefix| {
        if (parseSignedSuffix(key, prefix)) |k| {
            const r: ?i32 = if (std.mem.eql(u8, prefix, "floor_"))
                set.floor(k)
            else if (std.mem.eql(u8, prefix, "ceiling_"))
                set.ceiling(k)
            else if (std.mem.eql(u8, prefix, "lower_"))
                set.lower(k)
            else
                set.higher(k);
            try writeOptI32(writer, r);
            return;
        }
    }
    if (parseRankSuffix(key)) |k| {
        try writeI64(writer, @intCast(set.rank(k)));
        return;
    }
    if (parseSelectIndex(key)) |i| {
        try writeOptI32(writer, set.select(i));
        return;
    }

    if (std.mem.eql(u8, key, "size")) {
        try writeI64(writer, @intCast(set.len()));
    } else if (std.mem.eql(u8, key, "is_empty")) {
        try writeBool(writer, set.isEmpty());
    } else if (std.mem.eql(u8, key, "min") or std.mem.eql(u8, key, "first")) {
        try writeOptI32(writer, set.first());
    } else if (std.mem.eql(u8, key, "max") or std.mem.eql(u8, key, "last")) {
        try writeOptI32(writer, set.last());
    } else if (std.mem.eql(u8, key, "to_sorted_array")) {
        // Stored elements are already strictly ascending; emit verbatim.
        try writeArray(writer, set.elementsSlice());
    } else if (std.mem.eql(u8, key, "descending_elements")) {
        const d = try set.descendingElements(allocator);
        defer allocator.free(d);
        try writeArray(writer, d);
    } else if (std.mem.eql(u8, key, "range_elements")) {
        const q = query orelse {
            try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
            return;
        };
        const r = try set.rangeElements(q, allocator);
        defer allocator.free(r);
        try writeArray(writer, r);
    } else if (std.mem.eql(u8, key, "range_elements_desc")) {
        const q = query orelse {
            try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
            return;
        };
        const r = try set.descendingRangeElements(q, allocator);
        defer allocator.free(r);
        try writeArray(writer, r);
    } else if (std.mem.eql(u8, key, "range_size")) {
        const q = query orelse {
            try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
            return;
        };
        const r = try set.rangeElements(q, allocator);
        defer allocator.free(r);
        try writeI64(writer, @intCast(r.len));
    } else if (parseThreshold(key, "contains_") != null) {
        try writeBool(writer, set.contains(parseThreshold(key, "contains_").?));
    } else {
        try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
    }
}

// ── HashPipeline runner (spec/features/hash-pipeline.md) ─────────────────────
//
// A STATELESS probe (not a stored collection): exactly ONE hash op carries the
// input + seed under test; the assertions read the deterministic hash output.
// Routed through the PRODUCTION src/hash.zig — every assertion is proved against
// the real fmix32/fmix64/double-hashing code, not re-derived here. Outputs are
// serialized as fixed-width, lower-case, `0x`-prefixed hex strings (8 digits for
// a u32, 16 for a u64) so a 64-bit hash survives the JSON 2^53 ceiling and every
// port's consensus diff is byte-identical; `positions` is an int[] in DERIVATION
// order (NOT sorted). Unknown ops/keys SKIP (forward-compat). Direct translation
// of the Rust runner's run_hash_pipeline (mapdb-rust/src/bin/validate.rs).

/// Parse a `0x`-prefixed hex `word` operand to a u64 (the caller narrows to u32
/// where the op needs a 32-bit word). NEVER via f64.
fn parseHexWord(v: std.json.Value) u64 {
    const s = v.string;
    const body = if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X")) s[2..] else @panic("hash-pipeline word must start with 0x");
    return std.fmt.parseInt(u64, body, 16) catch @panic("invalid hex word");
}

/// Parse a `seed` operand: a DECIMAL STRING parsed straight to u64 (never via
/// f64), reusing the i64-suite's decimal-string discipline. A bare JSON number
/// is also accepted for small seeds.
fn parseSeed(v: std.json.Value) u64 {
    return switch (v) {
        .string => |s| std.fmt.parseInt(u64, s, 10) catch @panic("invalid u64 decimal-string seed"),
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch @panic("invalid u64 number_string seed"),
        .integer => |i| @as(u64, @intCast(i)),
        else => @panic("expected u64 seed (decimal string or number)"),
    };
}

/// Parse a `0x`-hex byte string (e.g. "0x01020304") into a caller-owned byte
/// slice.
fn parseHexBytes(v: std.json.Value, allocator: Allocator) ![]u8 {
    const s = v.string;
    const body = if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X")) s[2..] else @panic("hash-pipeline bytes must start with 0x");
    if (body.len % 2 != 0) @panic("hash-pipeline bytes must have an even hex-digit count");
    const out = try allocator.alloc(u8, body.len / 2);
    for (0..out.len) |i| {
        out[i] = std.fmt.parseInt(u8, body[2 * i .. 2 * i + 2], 16) catch @panic("invalid hex byte");
    }
    return out;
}

const HashProbe = union(enum) {
    word32: u32,
    word64: u64,
    i32_in: struct { value: i32, seed: u64 },
    bytes_in: struct { bytes: []const u8, seed: u64 },
    positions: []const u32,
};

// Format a u32 as 8-digit lower-case 0x hex.
fn writeHash32(writer: anytype, h: u32) !void {
    try writer.print("0x{x:0>8}", .{h});
}
// Format a u64 as 16-digit lower-case 0x hex.
fn writeHash64(writer: anytype, h: u64) !void {
    try writer.print("0x{x:0>16}", .{h});
}

fn evalHashProbe(probe: HashProbe, key: []const u8, writer: anytype) !void {
    switch (probe) {
        .word32 => |h| {
            if (std.mem.eql(u8, key, "hash32")) {
                try writeHash32(writer, h);
            } else try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
        },
        .word64 => |h| {
            if (std.mem.eql(u8, key, "hash64")) {
                try writeHash64(writer, h);
            } else if (std.mem.eql(u8, key, "hash64_hi")) {
                try writeHash32(writer, @truncate(h >> 32));
            } else if (std.mem.eql(u8, key, "hash64_lo")) {
                try writeHash32(writer, @truncate(h));
            } else try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
        },
        .i32_in => |p| {
            if (std.mem.eql(u8, key, "hash32")) {
                try writeHash32(writer, hash.hash32I32(p.value, p.seed));
            } else if (std.mem.eql(u8, key, "hash64")) {
                try writeHash64(writer, hash.hash64I32(p.value, p.seed));
            } else if (std.mem.eql(u8, key, "hash64_hi")) {
                try writeHash32(writer, @truncate(hash.hash64I32(p.value, p.seed) >> 32));
            } else if (std.mem.eql(u8, key, "hash64_lo")) {
                try writeHash32(writer, @truncate(hash.hash64I32(p.value, p.seed)));
            } else try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
        },
        .bytes_in => |p| {
            if (std.mem.eql(u8, key, "hash32")) {
                try writeHash32(writer, hash.hash32Bytes(p.bytes, p.seed));
            } else if (std.mem.eql(u8, key, "hash64")) {
                try writeHash64(writer, hash.hash64Bytes(p.bytes, p.seed));
            } else if (std.mem.eql(u8, key, "hash64_hi")) {
                try writeHash32(writer, @truncate(hash.hash64Bytes(p.bytes, p.seed) >> 32));
            } else if (std.mem.eql(u8, key, "hash64_lo")) {
                try writeHash32(writer, @truncate(hash.hash64Bytes(p.bytes, p.seed)));
            } else try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
        },
        .positions => |p| {
            if (std.mem.eql(u8, key, "positions")) {
                // Emitted in DERIVATION order (p_0 … p_{k-1}), NOT sorted.
                try writer.writeAll("[");
                for (p, 0..) |x, i| {
                    if (i > 0) try writer.writeAll(",");
                    try writer.print("{d}", .{x});
                }
                try writer.writeAll("]");
            } else try writer.print("UNKNOWN_ASSERTION:{s}", .{key});
        },
    }
}

fn runHashPipeline(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});

    // Authoring rule: exactly ONE hash op. Zero or multiple => malformed =>
    // SKIP (like the sorted-table `from_sorted` rule). Forward-compat: an
    // unrecognised op kind also makes the scenario un-runnable here => SKIP.
    if (operations.items.len != 1) {
        std.debug.print("skip: hash-pipeline scenario must have exactly one op (forward-compat): got {d}\n", .{operations.items.len});
        return;
    }
    const op = operations.items[0].object;
    const op_name = op.get("op").?.string;

    // Owned byte/positions buffers freed after the assertion loop.
    var owned_bytes: ?[]u8 = null;
    defer if (owned_bytes) |b| allocator.free(b);
    var owned_positions: ?[]u32 = null;
    defer if (owned_positions) |p| allocator.free(p);

    var probe: HashProbe = undefined;
    if (std.mem.eql(u8, op_name, "hash_word32")) {
        const raw = parseHexWord(op.get("word").?);
        if (raw > std.math.maxInt(u32)) @panic("hash_word32 `word` exceeds 32 bits");
        probe = .{ .word32 = hash.hash32(@truncate(raw), parseSeed(op.get("seed").?)) };
    } else if (std.mem.eql(u8, op_name, "hash_word64")) {
        probe = .{ .word64 = hash.hash64(parseHexWord(op.get("word").?), parseSeed(op.get("seed").?)) };
    } else if (std.mem.eql(u8, op_name, "hash_i32")) {
        const value: i32 = @intCast(op.get("value").?.integer);
        probe = .{ .i32_in = .{ .value = value, .seed = parseSeed(op.get("seed").?) } };
    } else if (std.mem.eql(u8, op_name, "hash_bytes")) {
        owned_bytes = try parseHexBytes(op.get("bytes").?, allocator);
        probe = .{ .bytes_in = .{ .bytes = owned_bytes.?, .seed = parseSeed(op.get("seed").?) } };
    } else if (std.mem.eql(u8, op_name, "positions")) {
        const value: i32 = @intCast(op.get("value").?.integer);
        const m: u32 = @intCast(op.get("m").?.integer);
        const k: u32 = @intCast(op.get("k").?.integer);
        // The byte encoding of an i32 element drives positions: encode the i32
        // to its little-endian 4-byte form (the byte path the sketches use),
        // then derive. No op-level seed (the scheme fixes 0 / SALT2).
        var le: [4]u8 = undefined;
        std.mem.writeInt(u32, &le, @bitCast(value), .little);
        owned_positions = try allocator.alloc(u32, k);
        hash.positions(&le, m, k, owned_positions.?);
        probe = .{ .positions = owned_positions.? };
    } else {
        std.debug.print("skip: unknown hash-pipeline op (forward-compat): {s}\n", .{op_name});
        return;
    }

    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var cbuf = std.array_list.Managed(u8).init(allocator);
        defer cbuf.deinit();
        try evalHashProbe(probe, key, cbuf.writer());
        const computed = cbuf.items;
        if (std.mem.startsWith(u8, computed, "UNKNOWN_ASSERTION:")) continue;

        try writer.print("{s}: {s}\n", .{ key, computed });
        var ebuf = std.array_list.Managed(u8).init(allocator);
        defer ebuf.deinit();
        try renderExpected(ebuf.writer(), expected, key, .none);
        if (!std.mem.eql(u8, computed, ebuf.items)) {
            try writer.print("FAIL {s} {s}: expected={s} got={s}\n", .{ name, key, ebuf.items, computed });
            any_fail = true;
        }
    }
}

// ── f32 runners ────────────────────────────────────────────────────────────
//
// Float collections live on a separate dispatch path; the Collection union
// above is i32-only. These three runners (HashMap<f32,i32>, HashSet<f32>,
// ArrayList<f32>) are direct translations of the equivalent runners in
// mapdb-rust/src/bin/validate.rs and mapdb-golang/cmd/validate/main.go.
// Required by `cross-language-validation/scenarios/05-float-edge-cases/*`.

// Q4 float operand encoding (see cross-language-validation/README.md
// §"Float operand encoding"): JSON number, human-label string, or a
// {"bits":"0x........"} object reinterpreting 32 IEEE-754 bits.
fn parseF32Value(v: std.json.Value) f32 {
    return switch (v) {
        .string => |s| parseF32Label(s),
        .float => |f| @as(f32, @floatCast(f)),
        .integer => |i| @as(f32, @floatFromInt(i)),
        .number_string => |s| std.fmt.parseFloat(f32, s) catch @panic("invalid f32 literal"),
        .object => |obj| blk: {
            const bits_val = obj.get("bits") orelse @panic("expected {\"bits\":\"0x..\"} float object");
            const hex = switch (bits_val) {
                .string => |s| s,
                else => @panic("bits must be a string"),
            };
            break :blk @bitCast(parseF32Bits(hex));
        },
        else => @panic("expected f32 value"),
    };
}

// Parse a 0x-prefixed, 8-hex-digit (case-insensitive) string into a raw
// 32-bit IEEE-754 pattern (NaN-payload / signed-bit escape).
fn parseF32Bits(hex: []const u8) u32 {
    if (hex.len != 10 or hex[0] != '0' or (hex[1] != 'x' and hex[1] != 'X')) {
        @panic("f32 bits literal must be 0x + 8 hex digits");
    }
    return std.fmt.parseInt(u32, hex[2..], 16) catch @panic("invalid f32 bits literal");
}

// Parse a human-label / decimal / hex-bits float string. Used for string
// operands and assertion-key suffixes (get_-NaN, contains_0.0,
// contains_0x7fc00001). Canonical NaN bits: +NaN=0x7FC00000, -NaN=0xFFC00000.
fn parseF32Label(s: []const u8) f32 {
    if (std.mem.eql(u8, s, "NaN") or std.mem.eql(u8, s, "+NaN")) return @bitCast(@as(u32, 0x7FC00000));
    if (std.mem.eql(u8, s, "-NaN")) return @bitCast(@as(u32, 0xFFC00000));
    if (std.mem.eql(u8, s, "Infinity") or std.mem.eql(u8, s, "+Infinity")) return std.math.inf(f32);
    if (std.mem.eql(u8, s, "-Infinity")) return -std.math.inf(f32);
    if (std.mem.eql(u8, s, "0.0") or std.mem.eql(u8, s, "+0.0")) return 0.0;
    if (std.mem.eql(u8, s, "-0.0")) return -0.0;
    if (std.mem.eql(u8, s, "pos_zero")) return 0.0;
    if (std.mem.eql(u8, s, "neg_zero")) return -0.0;
    if (s.len >= 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) {
        return @bitCast(parseF32Bits(s));
    }
    return std.fmt.parseFloat(f32, s) catch @panic("invalid f32 literal in key");
}

// Loose-NaN scalar match. When the EXPECTED operand is a bare NaN *label*
// ("NaN"/"+NaN"/"-NaN") — NOT a {"bits":"0x.."} object and NOT an array
// element — the assertion passes against ANY NaN the runner computed,
// regardless of sign/payload. This covers impl/arch-defined arithmetic NaNs
// such as (+Inf)+(-Inf), whose bits differ across x86 vs ARM. {"bits"}
// operands stay bitwise-exact and array elements stay exact/positional
// (renderExpected is unchanged for both). See cross-language-validation/README.md
// §"Float operand encoding".
fn looseNanMatch(expected: std.json.Value, mode: FloatMode, computed: []const u8) bool {
    if (mode == .none) return false;
    const s = switch (expected) {
        .string => |str| str,
        else => return false,
    };
    if (!std.math.isNan(parseF32Label(s))) return false;
    // Computed must itself be a NaN bit pattern (canonical "0x........").
    if (computed.len != 10 or computed[0] != '0' or (computed[1] != 'x' and computed[1] != 'X')) return false;
    const bits = std.fmt.parseInt(u32, computed[2..], 16) catch return false;
    return std.math.isNan(@as(f32, @bitCast(bits)));
}

// Canonical, bit-faithful serialization, matching Rust/Go/TS. NaN (any
// sign/payload) and ±0.0 render as their 0x-hex bit pattern so distinct
// payloads and signed zeros stay distinguishable and every port emits the
// identical string; finite/inf values keep their human-readable label.
fn writeF32(writer: anytype, v: f32) !void {
    if (std.math.isNan(v) or v == 0) {
        const bits: u32 = @bitCast(v);
        try writer.print("0x{x:0>8}", .{bits});
        return;
    }
    if (std.math.isInf(v)) {
        if (v > 0) try writer.writeAll("Infinity") else try writer.writeAll("-Infinity");
        return;
    }
    const trunc = @trunc(v);
    if (v == trunc and @abs(v) < 1e16) {
        const as_int: i64 = @intFromFloat(v);
        try writer.print("{d}.0", .{as_int});
        return;
    }
    try writer.print("{d}", .{v});
}

/// IEEE total order comparator on f32, reused from the shared production
/// helper. Used here only on the *harness* side to order the unordered output
/// of hash-based f32 collections for assertion comparison — not to model any
/// collection's own ordering (those now call float_order directly).
const totalCmpF32 = float_order.totalCmpF32;

fn sortF32Total(items: []f32) void {
    std.mem.sort(f32, items, {}, struct {
        pub fn less(_: void, a: f32, b: f32) bool {
            return totalCmpF32(a, b) == .lt;
        }
    }.less);
}

fn runF32HashMap(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});
    var m = try F32I32HashMap.init(allocator);
    defer m.deinit();
    for (operations.items) |op| {
        const obj = op.object;
        const op_name = obj.get("op").?.string;
        if (std.mem.eql(u8, op_name, "put")) {
            const k = parseF32Value(obj.get("key").?);
            const v = @as(i32, @intCast(obj.get("value").?.integer));
            _ = try m.put(k, v);
        } else if (std.mem.eql(u8, op_name, "remove")) {
            _ = m.remove(parseF32Value(obj.get("key").?));
        } else if (std.mem.eql(u8, op_name, "clear")) {
            m.clear();
        }
    }
    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var vbuf = std.array_list.Managed(u8).init(allocator);
        defer vbuf.deinit();
        const vw = vbuf.writer();
        if (std.mem.eql(u8, key, "size")) {
            try vw.print("{d}", .{m.size()});
        } else if (std.mem.eql(u8, key, "is_empty")) {
            try vw.print("{s}", .{if (m.isEmpty()) "true" else "false"});
        } else if (std.mem.startsWith(u8, key, "get_")) {
            const probe = parseF32Label(key[4..]);
            if (m.get(probe)) |v| try vw.print("{d}", .{v}) else try vw.writeAll("null");
        } else if (std.mem.startsWith(u8, key, "contains_")) {
            const probe = parseF32Label(key[9..]);
            try vw.print("{s}", .{if (m.containsKey(probe)) "true" else "false"});
        } else if (std.mem.eql(u8, key, "sorted_keys")) {
            const keys = try m.keysToSlice(allocator);
            defer allocator.free(keys);
            sortF32Total(keys);
            try vw.writeAll("[");
            for (keys, 0..) |k, i| {
                if (i > 0) try vw.writeAll(",");
                try vw.writeAll("\"");
                try writeF32(vw, k);
                try vw.writeAll("\"");
            }
            try vw.writeAll("]");
        } else {
            try vw.print("UNKNOWN_ASSERTION:{s}", .{key});
        }
        try emitF32(name, key, vbuf.items, expected, .f32_keyed, allocator, writer);
    }
}

// Print a precomputed f32 assertion value and compare against the expected
// JSON value; skip unrecognised keys silently.
fn emitF32(
    name: []const u8,
    key: []const u8,
    computed: []const u8,
    expected: std.json.Value,
    mode: FloatMode,
    allocator: Allocator,
    stdout: anytype,
) !void {
    if (std.mem.startsWith(u8, computed, "UNKNOWN_ASSERTION:")) return;
    try stdout.print("{s}: {s}\n", .{ key, computed });
    var ebuf = std.array_list.Managed(u8).init(allocator);
    defer ebuf.deinit();
    try renderExpected(ebuf.writer(), expected, key, mode);
    if (!std.mem.eql(u8, computed, ebuf.items) and !looseNanMatch(expected, mode, computed)) {
        try stdout.print("FAIL {s} {s}: expected={s} got={s}\n", .{ name, key, ebuf.items, computed });
        any_fail = true;
    }
}

fn runF32HashSet(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});
    var set = try F32HashSet.init(allocator);
    defer set.deinit();
    for (operations.items) |op| {
        const obj = op.object;
        const op_name = obj.get("op").?.string;
        if (std.mem.eql(u8, op_name, "add")) {
            _ = try set.add(parseF32Value(obj.get("value").?));
        } else if (std.mem.eql(u8, op_name, "remove")) {
            _ = set.remove(parseF32Value(obj.get("value").?));
        } else if (std.mem.eql(u8, op_name, "clear")) {
            set.clear();
        }
    }
    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var vbuf = std.array_list.Managed(u8).init(allocator);
        defer vbuf.deinit();
        const vw = vbuf.writer();
        if (std.mem.eql(u8, key, "size")) {
            try vw.print("{d}", .{set.size()});
        } else if (std.mem.eql(u8, key, "is_empty")) {
            try vw.print("{s}", .{if (set.isEmpty()) "true" else "false"});
        } else if (std.mem.startsWith(u8, key, "contains_")) {
            const probe = parseF32Label(key[9..]);
            try vw.print("{s}", .{if (set.contains(probe)) "true" else "false"});
        } else if (std.mem.eql(u8, key, "sorted_values") or std.mem.eql(u8, key, "to_sorted_array")) {
            const vals = try set.toSlice(allocator);
            defer allocator.free(vals);
            sortF32Total(vals);
            try vw.writeAll("[");
            for (vals, 0..) |v, i| {
                if (i > 0) try vw.writeAll(",");
                try vw.writeAll("\"");
                try writeF32(vw, v);
                try vw.writeAll("\"");
            }
            try vw.writeAll("]");
        } else {
            try vw.print("UNKNOWN_ASSERTION:{s}", .{key});
        }
        try emitF32(name, key, vbuf.items, expected, .f32_keyed, allocator, writer);
    }
}

// Routes through the PRODUCTION F32TreeSet (std.Treap ordered by
// float_order.totalCmpF32). The sorted output is toSlice(), the treap's
// in-order traversal -- NEVER sorted in the runner -- so this exercises the
// production float total-order comparator directly.
fn runF32TreeSet(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});
    var set = F32TreeSet.init(allocator);
    defer set.deinit();
    for (operations.items) |op| {
        const obj = op.object;
        const op_name = obj.get("op").?.string;
        if (std.mem.eql(u8, op_name, "add")) {
            _ = try set.add(parseF32Value(obj.get("value").?));
        } else if (std.mem.eql(u8, op_name, "remove")) {
            _ = set.remove(parseF32Value(obj.get("value").?));
        } else if (std.mem.eql(u8, op_name, "clear")) {
            set.clear();
        }
    }
    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var vbuf = std.array_list.Managed(u8).init(allocator);
        defer vbuf.deinit();
        const vw = vbuf.writer();
        if (std.mem.eql(u8, key, "size")) {
            try vw.print("{d}", .{set.size()});
        } else if (std.mem.eql(u8, key, "is_empty")) {
            try vw.print("{s}", .{if (set.isEmpty()) "true" else "false"});
        } else if (std.mem.eql(u8, key, "min")) {
            if (set.min()) |mn| try writeF32(vw, mn) else try vw.writeAll("null");
        } else if (std.mem.eql(u8, key, "max")) {
            if (set.max()) |mx| try writeF32(vw, mx) else try vw.writeAll("null");
        } else if (std.mem.startsWith(u8, key, "contains_")) {
            const probe = parseF32Label(key[9..]);
            try vw.print("{s}", .{if (set.contains(probe)) "true" else "false"});
        } else if (std.mem.eql(u8, key, "sorted") or std.mem.eql(u8, key, "sorted_values") or std.mem.eql(u8, key, "to_sorted_array")) {
            // In-order traversal straight from the production treap.
            const vals = try set.toSlice(allocator);
            defer allocator.free(vals);
            try vw.writeAll("[");
            for (vals, 0..) |v, i| {
                if (i > 0) try vw.writeAll(",");
                try vw.writeAll("\"");
                try writeF32(vw, v);
                try vw.writeAll("\"");
            }
            try vw.writeAll("]");
        } else {
            try vw.print("UNKNOWN_ASSERTION:{s}", .{key});
        }
        try emitF32(name, key, vbuf.items, expected, .f32_keyed, allocator, writer);
    }
}

fn runF32ArrayList(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});
    var list = F32ArrayList.init(allocator);
    defer list.deinit();
    for (operations.items) |op| {
        const obj = op.object;
        const op_name = obj.get("op").?.string;
        if (std.mem.eql(u8, op_name, "add")) {
            try list.add(parseF32Value(obj.get("value").?));
        } else if (std.mem.eql(u8, op_name, "clear")) {
            list.clear();
        }
    }
    const values = list.toSlice();
    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var vbuf = std.array_list.Managed(u8).init(allocator);
        defer vbuf.deinit();
        const vw = vbuf.writer();
        if (std.mem.eql(u8, key, "size")) {
            try vw.print("{d}", .{values.len});
        } else if (std.mem.eql(u8, key, "is_empty")) {
            try vw.print("{s}", .{if (values.len == 0) "true" else "false"});
        } else if (std.mem.eql(u8, key, "sum")) {
            // Production F32ArrayList.sum().
            try writeF32(vw, list.sum());
        } else if (std.mem.eql(u8, key, "min")) {
            // Production total-order min() (sign-flip comparator).
            if (list.min()) |mn| try writeF32(vw, mn) else try vw.writeAll("null");
        } else if (std.mem.eql(u8, key, "max")) {
            // Production total-order max().
            if (list.max()) |mx| try writeF32(vw, mx) else try vw.writeAll("null");
        } else if (std.mem.eql(u8, key, "sorted") or std.mem.eql(u8, key, "to_sorted_array")) {
            // Production F32ArrayList.sort() (total-order). Sort a copy so the
            // original element order is preserved for any later assertions.
            var sorted_list = F32ArrayList.init(allocator);
            defer sorted_list.deinit();
            for (values) |v| try sorted_list.add(v);
            sorted_list.sort();
            const buf = sorted_list.toSlice();
            try vw.writeAll("[");
            for (buf, 0..) |v, i| {
                if (i > 0) try vw.writeAll(",");
                try writeF32(vw, v);
            }
            try vw.writeAll("]");
        } else {
            try vw.print("UNKNOWN_ASSERTION:{s}", .{key});
        }
        try emitF32(name, key, vbuf.items, expected, .f32_list, allocator, writer);
    }
}

// ── HashMap<i64, i32> runner ────────────────────────────────────────────────
//
// Routes through the PRODUCTION I64I32HashMap (real i64 hash spread + key
// identity). i64 KEYS are decimal STRINGS (they exceed 2^53) parsed straight to
// i64 via std.fmt.parseInt — never via f64; small keys may also be bare JSON
// numbers. The value stays an i32 JSON number. See README §"Wide-integer (i64)
// operand encoding".

fn parseI64Operand(v: std.json.Value) i64 {
    return switch (v) {
        .string => |s| std.fmt.parseInt(i64, s, 10) catch @panic("invalid i64 decimal-string key"),
        .integer => |i| i,
        .number_string => |s| std.fmt.parseInt(i64, s, 10) catch @panic("invalid i64 number_string key"),
        else => @panic("expected i64 key (decimal string or number)"),
    };
}

fn runI64HashMap(
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});
    var m = try I64I32HashMap.init(allocator);
    defer m.deinit();
    for (operations.items) |op| {
        const obj = op.object;
        const op_name = obj.get("op").?.string;
        if (std.mem.eql(u8, op_name, "put")) {
            const k = parseI64Operand(obj.get("key").?);
            const v = @as(i32, @intCast(obj.get("value").?.integer));
            _ = try m.put(k, v);
        } else if (std.mem.eql(u8, op_name, "remove")) {
            _ = m.remove(parseI64Operand(obj.get("key").?));
        } else if (std.mem.eql(u8, op_name, "clear")) {
            m.clear();
        }
    }
    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var vbuf = std.array_list.Managed(u8).init(allocator);
        defer vbuf.deinit();
        const vw = vbuf.writer();
        var known = true;
        if (std.mem.eql(u8, key, "size")) {
            try vw.print("{d}", .{m.size()});
        } else if (std.mem.eql(u8, key, "is_empty")) {
            try vw.print("{s}", .{if (m.isEmpty()) "true" else "false"});
        } else if (std.mem.eql(u8, key, "sorted_keys")) {
            // i64 keys exceed 2^53: serialize each as a plain decimal STRING in
            // a quoted array, sorted numerically as i64 ascending.
            const keys = try m.keysToSlice(allocator);
            defer allocator.free(keys);
            std.mem.sort(i64, keys, {}, struct {
                pub fn lt(_: void, a: i64, b: i64) bool {
                    return a < b;
                }
            }.lt);
            try vw.writeAll("[");
            for (keys, 0..) |k, i| {
                if (i > 0) try vw.writeAll(",");
                try vw.print("\"{d}\"", .{k});
            }
            try vw.writeAll("]");
        } else if (std.mem.startsWith(u8, key, "get_")) {
            const k = std.fmt.parseInt(i64, key[4..], 10) catch @panic("bad get_ i64 suffix");
            if (m.get(k)) |v| try vw.print("{d}", .{v}) else try vw.writeAll("null");
        } else if (std.mem.startsWith(u8, key, "contains_")) {
            const k = std.fmt.parseInt(i64, key[9..], 10) catch @panic("bad contains_ i64 suffix");
            try vw.print("{s}", .{if (m.containsKey(k)) "true" else "false"});
        } else {
            known = false;
        }
        if (!known) continue; // unknown key -> skip
        try emitI64(name, key, vbuf.items, expected, allocator, writer);
    }
}

// Print a precomputed i64-map assertion value and compare against the expected
// JSON value. `sorted_keys` expected is a decimal-string array (rendered
// quoted); scalars are integers/bools/null.
fn emitI64(
    name: []const u8,
    key: []const u8,
    computed: []const u8,
    expected: std.json.Value,
    allocator: Allocator,
    stdout: anytype,
) !void {
    try stdout.print("{s}: {s}\n", .{ key, computed });
    var ebuf = std.array_list.Managed(u8).init(allocator);
    defer ebuf.deinit();
    const ew = ebuf.writer();
    switch (expected) {
        .null => try ew.writeAll("null"),
        .bool => |b| try ew.writeAll(if (b) "true" else "false"),
        .integer => |i| try ew.print("{d}", .{i}),
        .number_string => |s| try ew.writeAll(s),
        .array => |arr| {
            try ew.writeAll("[");
            for (arr.items, 0..) |e, i| {
                if (i > 0) try ew.writeAll(",");
                // i64 sorted_keys elements are decimal STRINGS — render quoted.
                switch (e) {
                    .string => |s| try ew.print("\"{s}\"", .{s}),
                    .integer => |n| try ew.print("\"{d}\"", .{n}),
                    .number_string => |s| try ew.print("\"{s}\"", .{s}),
                    else => @panic("unexpected i64 sorted_keys element"),
                }
            }
            try ew.writeAll("]");
        },
        else => @panic("unexpected i64 assertion expected value"),
    }
    if (!std.mem.eql(u8, computed, ebuf.items)) {
        try stdout.print("FAIL {s} {s}: expected={s} got={s}\n", .{ name, key, ebuf.items, computed });
        any_fail = true;
    }
}

// ── {List,Set}Multimap<i64, i32> runner ─────────────────────────────────────
//
// Routes through the PRODUCTION I64I32{List,Set}Multimap. These back onto Zig's
// std AutoHashMap (the STDLIB hasher), NOT the production OpenHashMap high-bit
// fold — so this verifies full-range i64 keys keep their identity (stay distinct
// and retrievable) through the stdlib map. It checks key identity, not
// bucket-distribution quality. List keeps duplicate values; Set dedups.
// i64 KEYS are decimal STRINGS (exceed 2^53)
// parsed via parseI64Operand — never via f64. Generic over the multimap type:
// both expose put / get(k)->[]const i32 / removeAll / containsKey / keysCount /
// uniqueKeys(allocator).
//
// Assertions (identical to the other ports):
//   distinct_key_count -> keysCount() (integer string)
//   sorted_keys        -> DISTINCT keys, ascending i64, quoted decimal strings
//   get_<k>            -> values for the key, ascending-sorted i32 array (sort a
//                         COPY); absent/removed => []
//   contains_key_<k>   -> bool
fn runI64Multimap(
    comptime M: type,
    m: *M,
    name: []const u8,
    operations: std.json.Array,
    assertions: std.json.ObjectMap,
    allocator: Allocator,
    writer: anytype,
    apply_ops: bool,
) !void {
    try writer.print("=== scenario: {s} ===\n", .{name});
    if (apply_ops) {
        for (operations.items) |op| {
            const obj = op.object;
            const op_name = obj.get("op").?.string;
            if (std.mem.eql(u8, op_name, "put")) {
                const k = parseI64Operand(obj.get("key").?);
                const v = @as(i32, @intCast(obj.get("value").?.integer));
                _ = try m.put(k, v);
            } else if (std.mem.eql(u8, op_name, "removeAll")) {
                _ = m.removeAll(parseI64Operand(obj.get("key").?));
            } else {
                @panic("unknown i64-multimap op");
            }
        }
    }
    for (assertions.keys(), assertions.values()) |key, expected| {
        if (std.mem.eql(u8, key, "comment")) continue;
        var vbuf = std.array_list.Managed(u8).init(allocator);
        defer vbuf.deinit();
        const vw = vbuf.writer();
        var known = true;
        if (std.mem.eql(u8, key, "distinct_key_count")) {
            try vw.print("{d}", .{m.keysCount()});
        } else if (std.mem.eql(u8, key, "sorted_keys")) {
            // DISTINCT keys, ascending i64, each a quoted decimal string —
            // same serialization as the i64-HashMap sorted_keys. uniqueKeys
            // allocates; free it.
            const keys = try m.uniqueKeys(allocator);
            defer allocator.free(keys);
            std.mem.sort(i64, keys, {}, struct {
                pub fn lt(_: void, a: i64, b: i64) bool {
                    return a < b;
                }
            }.lt);
            try vw.writeAll("[");
            for (keys, 0..) |k, i| {
                if (i > 0) try vw.writeAll(",");
                try vw.print("\"{d}\"", .{k});
            }
            try vw.writeAll("]");
        } else if (std.mem.startsWith(u8, key, "get_")) {
            const k = std.fmt.parseInt(i64, key[4..], 10) catch @panic("bad get_ i64 suffix");
            // get() returns a BORROWED slice; copy before sorting (sort a COPY).
            const src = m.get(k);
            const vals = try allocator.alloc(i32, src.len);
            defer allocator.free(vals);
            @memcpy(vals, src);
            std.mem.sort(i32, vals, {}, struct {
                pub fn lt(_: void, a: i32, b: i32) bool {
                    return a < b;
                }
            }.lt);
            try vw.writeAll("[");
            for (vals, 0..) |v, i| {
                if (i > 0) try vw.writeAll(",");
                try vw.print("{d}", .{v});
            }
            try vw.writeAll("]");
        } else if (std.mem.startsWith(u8, key, "contains_key_")) {
            const k = std.fmt.parseInt(i64, key[13..], 10) catch @panic("bad contains_key_ i64 suffix");
            try vw.print("{s}", .{if (m.containsKey(k)) "true" else "false"});
        } else {
            known = false;
        }
        if (!known) continue; // unknown key -> skip
        try emitI64Multimap(name, key, vbuf.items, expected, allocator, writer);
    }
}

// Print a precomputed i64-multimap assertion value and compare against the
// expected JSON value. `sorted_keys` expected is a decimal-string array
// (rendered quoted); `get_<k>` is a plain i32 array (rendered UNQUOTED);
// scalars are integers/bools.
fn emitI64Multimap(
    name: []const u8,
    key: []const u8,
    computed: []const u8,
    expected: std.json.Value,
    allocator: Allocator,
    stdout: anytype,
) !void {
    try stdout.print("{s}: {s}\n", .{ key, computed });
    var ebuf = std.array_list.Managed(u8).init(allocator);
    defer ebuf.deinit();
    const ew = ebuf.writer();
    const is_keys = std.mem.eql(u8, key, "sorted_keys");
    switch (expected) {
        .bool => |b| try ew.writeAll(if (b) "true" else "false"),
        .integer => |i| try ew.print("{d}", .{i}),
        .number_string => |s| try ew.writeAll(s),
        .array => |arr| {
            try ew.writeAll("[");
            for (arr.items, 0..) |e, i| {
                if (i > 0) try ew.writeAll(",");
                if (is_keys) {
                    // sorted_keys elements are decimal STRINGS — render quoted.
                    switch (e) {
                        .string => |s| try ew.print("\"{s}\"", .{s}),
                        .integer => |n| try ew.print("\"{d}\"", .{n}),
                        .number_string => |s| try ew.print("\"{s}\"", .{s}),
                        else => @panic("unexpected sorted_keys element"),
                    }
                } else {
                    // get_<k> value-array elements are plain i32 — UNQUOTED.
                    switch (e) {
                        .integer => |n| try ew.print("{d}", .{n}),
                        .number_string => |s| try ew.writeAll(s),
                        else => @panic("unexpected get_ value-array element"),
                    }
                }
            }
            try ew.writeAll("]");
        },
        else => @panic("unexpected i64-multimap assertion expected value"),
    }
    if (!std.mem.eql(u8, computed, ebuf.items)) {
        try stdout.print("FAIL {s} {s}: expected={s} got={s}\n", .{ name, key, ebuf.items, computed });
        any_fail = true;
    }
}

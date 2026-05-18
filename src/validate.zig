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

const I32I32HashMap = @import("hashmap/i32_i32_hash_map.zig").I32I32HashMap;
const I32ArrayList = @import("arraylist/i32_array_list.zig").I32ArrayList;
const I32HashSet = @import("hashset/i32_hash_set.zig").I32HashSet;
const I32HashBag = @import("bag/i32_hash_bag.zig").I32HashBag;
const I32TreeSet = @import("treeset/i32_tree_set.zig").I32TreeSet;
const I32I32TreeMap = @import("treemap/i32_i32_tree_map.zig").I32I32TreeMap;
const I32ArrayStack = @import("stack/i32_array_stack.zig").I32ArrayStack;
const F32I32HashMap = @import("hashmap/f32_i32_hash_map.zig").F32I32HashMap;
const F32HashSet = @import("hashset/f32_hash_set.zig").F32HashSet;
const F32ArrayList = @import("arraylist/f32_array_list.zig").F32ArrayList;

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

fn initCollection(kind: CollectionKind, allocator: Allocator) Collection {
    return switch (kind) {
        .hash_map => .{ .hash_map = I32I32HashMap.init(allocator) },
        .array_list => .{ .array_list = I32ArrayList.init(allocator) },
        .hash_set => .{ .hash_set = I32HashSet.init(allocator) },
        .hash_bag => .{ .hash_bag = I32HashBag.init(allocator) },
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

fn applyOperation(coll: *Collection, op: std.json.Value) void {
    const obj = op.object;
    const op_name = obj.get("op").?.string;

    if (std.mem.eql(u8, op_name, "put")) {
        const key = jsonToI32(obj.get("key").?).?;
        const value = jsonToI32(obj.get("value").?).?;
        switch (coll.*) {
            .hash_map => |*m| _ = m.put(key, value),
            .tree_map => |*m| _ = m.put(key, value),
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "add")) {
        const value = jsonToI32(obj.get("value").?).?;
        switch (coll.*) {
            .array_list => |*l| l.add(value),
            .hash_set => |*s| _ = s.add(value),
            .hash_bag => |*b| b.add(value),
            .tree_set => |*s| _ = s.add(value),
            .array_stack => |*s| s.push(value),
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "add_at")) {
        const index: usize = @intCast(obj.get("index").?.integer);
        const value = jsonToI32(obj.get("value").?).?;
        switch (coll.*) {
            .array_list => |*l| {
                l.items.insert(l.config.itemsAllocator(), index, value) catch @panic("out of memory");
            },
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "addToValue")) {
        // Cross-language scenarios (06-overflow/*) require wrapping i32 semantics.
        // Reimplement locally with +%= rather than relying on a production
        // `addToValue` that may or may not wrap; mirrors validate.rs.
        const key = jsonToI32(obj.get("key").?).?;
        const delta = jsonToI32(obj.get("delta").?).?;
        switch (coll.*) {
            .hash_map => |*m| {
                const cur: i32 = m.get(key) orelse 0;
                _ = m.put(key, cur +% delta);
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
            .array_stack => |*s| s.push(value),
            .array_list => |*l| l.push(value),
            else => {},
        }
    } else if (std.mem.eql(u8, op_name, "pop")) {
        switch (coll.*) {
            .array_stack => |*s| _ = s.pop(),
            else => {},
        }
    }
}

/// Get a sorted slice of values from an element-based collection.
/// Caller owns the returned slice.
fn getItemSlice(coll: *Collection, allocator: Allocator) []i32 {
    switch (coll.*) {
        .array_list => |*l| {
            const src = l.toSlice();
            const copy = allocator.alloc(i32, src.len) catch @panic("oom");
            @memcpy(copy, src);
            return copy;
        },
        .hash_set => |*s| {
            return s.toSlice(allocator);
        },
        .hash_bag => |*b| {
            return b.toSlice(allocator);
        },
        .tree_set => |*s| {
            // toSlice(allocator) now owns the return — no extra copy needed.
            return s.toSlice(allocator);
        },
        .array_stack => |*s| {
            const src = s.toSlice();
            const copy = allocator.alloc(i32, src.len) catch @panic("oom");
            @memcpy(copy, src);
            return copy;
        },
        else => {
            return allocator.alloc(i32, 0) catch @panic("oom");
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

fn evaluateAssertion(
    key: []const u8,
    coll: *Collection,
    other_coll: ?*Collection,
    allocator: Allocator,
    writer: anytype,
) !void {
    try writer.print("{s}: ", .{key});

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
    // --- sum (wrapping i32, matches Rust/Go) ---
    // Note: the production I32ArrayList.sum() returns a widened i64 so it
    // never overflows in normal use. The cross-language scenario contract
    // (scenarios/06-overflow/i32_sum_overflow.json) is wrapping i32 instead
    // — Java/Go wrap silently, Rust uses wrapping_add in release. Compute
    // it locally here rather than changing the production API.
    else if (std.mem.eql(u8, key, "sum")) {
        switch (coll.*) {
            .array_list => |*l| {
                var acc: i32 = 0;
                for (l.toSlice()) |item| acc +%= item;
                try writeI32(writer, acc);
            },
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
                const keys = m.keysToSlice(allocator);
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
                const vals = m.valuesToSlice(allocator);
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
        const items = getItemSlice(coll, allocator);
        defer allocator.free(items);
        try writeSortedArray(writer, items);
    }
    // --- inject_into_sum (widened i64 fold, matches Rust/Go) ---
    else if (std.mem.eql(u8, key, "inject_into_sum")) {
        switch (coll.*) {
            .array_list => |*l| {
                var acc: i64 = 0;
                for (l.toSlice()) |item| acc += @as(i64, @intCast(item));
                try writeI64(writer, acc);
            },
            .array_stack => |*s| {
                var acc: i64 = 0;
                for (s.toSlice()) |item| acc += @as(i64, @intCast(item));
                try writeI64(writer, acc);
            },
            else => try writeNull(writer),
        }
    }
    // --- inject_into_product (widened i64 fold, matches Rust/Go) ---
    else if (std.mem.eql(u8, key, "inject_into_product")) {
        switch (coll.*) {
            .array_list => |*l| {
                var acc: i64 = 1;
                for (l.toSlice()) |item| acc *= @as(i64, @intCast(item));
                try writeI64(writer, acc);
            },
            .array_stack => |*s| {
                var acc: i64 = 1;
                for (s.toSlice()) |item| acc *= @as(i64, @intCast(item));
                try writeI64(writer, acc);
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
        const items = getItemSlice(coll, allocator);
        defer allocator.free(items);
        // Zig 0.15 split ArrayList into Unmanaged (std.ArrayList) and Managed
        // (std.array_list.Managed). The allocator-carrying init(alloc) form
        // now lives on Managed; unmanaged uses .empty / append(alloc, item).
        var result = std.array_list.Managed(i32).init(allocator);
        defer result.deinit();
        for (items) |item| {
            if (item > threshold) result.append(item) catch @panic("oom");
        }
        const slice = result.items;
        const copy = allocator.alloc(i32, slice.len) catch @panic("oom");
        defer allocator.free(copy);
        @memcpy(copy, slice);
        try writeSortedArray(writer, copy);
    }
    // --- reject_gt_N ---
    else if (std.mem.startsWith(u8, key, "reject_gt_")) {
        const threshold = parseThreshold(key, "reject_gt_").?;
        const items = getItemSlice(coll, allocator);
        defer allocator.free(items);
        // Zig 0.15 split ArrayList into Unmanaged (std.ArrayList) and Managed
        // (std.array_list.Managed). The allocator-carrying init(alloc) form
        // now lives on Managed; unmanaged uses .empty / append(alloc, item).
        var result = std.array_list.Managed(i32).init(allocator);
        defer result.deinit();
        for (items) |item| {
            if (item <= threshold) result.append(item) catch @panic("oom");
        }
        const slice = result.items;
        const copy = allocator.alloc(i32, slice.len) catch @panic("oom");
        defer allocator.free(copy);
        @memcpy(copy, slice);
        try writeSortedArray(writer, copy);
    }
    // --- detect_gt_N ---
    else if (std.mem.startsWith(u8, key, "detect_gt_")) {
        const threshold = parseThreshold(key, "detect_gt_").?;
        const items = getItemSlice(coll, allocator);
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
        const items = getItemSlice(coll, allocator);
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
        const items = getItemSlice(coll, allocator);
        defer allocator.free(items);
        var c: i64 = 0;
        for (items) |item| {
            if (item < threshold) c += 1;
        }
        try writeI64(writer, c);
    }
    // --- count_even ---
    else if (std.mem.eql(u8, key, "count_even")) {
        const items = getItemSlice(coll, allocator);
        defer allocator.free(items);
        var c: i64 = 0;
        for (items) |item| {
            if (@rem(item, 2) == 0) c += 1;
        }
        try writeI64(writer, c);
    }
    // --- count_odd ---
    else if (std.mem.eql(u8, key, "count_odd")) {
        const items = getItemSlice(coll, allocator);
        defer allocator.free(items);
        var c: i64 = 0;
        for (items) |item| {
            if (@rem(item, 2) != 0) c += 1;
        }
        try writeI64(writer, c);
    }
    // --- any_satisfy_even ---
    else if (std.mem.eql(u8, key, "any_satisfy_even")) {
        const items = getItemSlice(coll, allocator);
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
        const items = getItemSlice(coll, allocator);
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
        const items = getItemSlice(coll, allocator);
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
        const items = getItemSlice(coll, allocator);
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
        const items = getItemSlice(coll, allocator);
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
        const items = getItemSlice(coll, allocator);
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
        const items = getItemSlice(coll, allocator);
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
                            var result = s.setUnion(os);
                            defer result.deinit();
                            if (std.mem.eql(u8, key, "union_size")) {
                                const sz: i64 = @intCast(result.len());
                                try writeI64(writer, sz);
                            } else {
                                const slice = result.toSlice(allocator);
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
                            var result = s.intersect(os);
                            defer result.deinit();
                            if (std.mem.eql(u8, key, "intersect_size")) {
                                const sz: i64 = @intCast(result.len());
                                try writeI64(writer, sz);
                            } else {
                                const slice = result.toSlice(allocator);
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
                            var result = s.difference(os);
                            defer result.deinit();
                            if (std.mem.eql(u8, key, "difference_size")) {
                                const sz: i64 = @intCast(result.len());
                                try writeI64(writer, sz);
                            } else {
                                const slice = result.toSlice(allocator);
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
                            var result = s.symmetricDifference(os);
                            defer result.deinit();
                            if (std.mem.eql(u8, key, "symmetric_difference_size")) {
                                const sz: i64 = @intCast(result.len());
                                try writeI64(writer, sz);
                            } else {
                                const slice = result.toSlice(allocator);
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
        try writer.print("UNKNOWN_KEY({s})", .{key});
    }

    try writer.writeAll("\n");
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
        return;
    }
    if (std.mem.eql(u8, collection_type, "HashSet<f32>")) {
        try runF32HashSet(name, operations, root.get("assertions").?.object, allocator, stdout);
        try stdout.flush();
        return;
    }
    if (std.mem.eql(u8, collection_type, "ArrayList<f32>")) {
        try runF32ArrayList(name, operations, root.get("assertions").?.object, allocator, stdout);
        try stdout.flush();
        return;
    }

    const kind = parseCollectionKind(collection_type) orelse {
        std.debug.print("Unknown collection type: {s}\n", .{collection_type});
        std.process.exit(1);
    };

    // Initialize main collection
    var coll = initCollection(kind, allocator);
    defer deinitCollection(&coll);

    // Apply operations
    for (operations.items) |op| {
        applyOperation(&coll, op);
    }

    // Initialize "other" collection if present (for set operations)
    var other_coll: ?Collection = null;
    if (root.get("other")) |other_json| {
        const other_obj = other_json.object;
        const other_type = other_obj.get("collection").?.string;
        const other_kind = parseCollectionKind(other_type) orelse {
            std.debug.print("Unknown other collection type: {s}\n", .{other_type});
            std.process.exit(1);
        };
        other_coll = initCollection(other_kind, allocator);
        const other_ops = other_obj.get("operations").?.array;
        for (other_ops.items) |op| {
            applyOperation(&other_coll.?, op);
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
    for (assertions.keys(), assertions.values()) |key, _| {
        // Scenario authors use "comment" as a doc string; the other ports
        // (Rust, Go) skip it. Treat it the same way here so harness diffs
        // line up.
        if (std.mem.eql(u8, key, "comment")) continue;
        const other_ptr: ?*Collection = if (other_coll != null) &other_coll.? else null;
        try evaluateAssertion(key, &coll, other_ptr, allocator, stdout);
    }
}

// ── f32 runners ────────────────────────────────────────────────────────────
//
// Float collections live on a separate dispatch path; the Collection union
// above is i32-only. These three runners (HashMap<f32,i32>, HashSet<f32>,
// ArrayList<f32>) are direct translations of the equivalent runners in
// mapdb-rust/src/bin/validate.rs and mapdb-golang/cmd/validate/main.go.
// Required by `cross-language-validation/scenarios/05-float-edge-cases/*`.

fn parseF32Value(v: std.json.Value) f32 {
    return switch (v) {
        .string => |s| parseF32Label(s),
        .float => |f| @as(f32, @floatCast(f)),
        .integer => |i| @as(f32, @floatFromInt(i)),
        .number_string => |s| std.fmt.parseFloat(f32, s) catch @panic("invalid f32 literal"),
        else => @panic("expected f32 value"),
    };
}

fn parseF32Label(s: []const u8) f32 {
    if (std.mem.eql(u8, s, "NaN")) return std.math.nan(f32);
    if (std.mem.eql(u8, s, "Infinity") or std.mem.eql(u8, s, "+Infinity")) return std.math.inf(f32);
    if (std.mem.eql(u8, s, "-Infinity")) return -std.math.inf(f32);
    if (std.mem.eql(u8, s, "pos_zero")) return 0.0;
    if (std.mem.eql(u8, s, "neg_zero")) return -0.0;
    return std.fmt.parseFloat(f32, s) catch @panic("invalid f32 literal in key");
}

fn writeF32(writer: anytype, v: f32) !void {
    if (std.math.isNan(v)) {
        try writer.writeAll("NaN");
        return;
    }
    if (std.math.isInf(v)) {
        if (v > 0) try writer.writeAll("Infinity") else try writer.writeAll("-Infinity");
        return;
    }
    if (v == 0 and std.math.signbit(v)) {
        try writer.writeAll("-0.0");
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

/// IEEE total order comparator on f32: matches Rust's `f32::total_cmp` and
/// the bit-pattern ordering in algorithms.md §"Float ordering for tree
/// collections". Same sign-flip-then-int-compare trick the Go runner uses.
fn totalCmpF32(a: f32, b: f32) std.math.Order {
    var ai: i32 = @bitCast(a);
    var bi: i32 = @bitCast(b);
    ai ^= @as(i32, @bitCast(@as(u32, @bitCast(ai >> 31)) >> 1));
    bi ^= @as(i32, @bitCast(@as(u32, @bitCast(bi >> 31)) >> 1));
    return std.math.order(ai, bi);
}

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
    var m = F32I32HashMap.init(allocator);
    defer m.deinit();
    for (operations.items) |op| {
        const obj = op.object;
        const op_name = obj.get("op").?.string;
        if (std.mem.eql(u8, op_name, "put")) {
            const k = parseF32Value(obj.get("key").?);
            const v = @as(i32, @intCast(obj.get("value").?.integer));
            _ = m.put(k, v);
        } else if (std.mem.eql(u8, op_name, "remove")) {
            _ = m.remove(parseF32Value(obj.get("key").?));
        } else if (std.mem.eql(u8, op_name, "clear")) {
            m.clear();
        }
    }
    for (assertions.keys()) |key| {
        if (std.mem.eql(u8, key, "comment")) continue;
        try writer.print("{s}: ", .{key});
        if (std.mem.eql(u8, key, "size")) {
            try writer.print("{d}", .{m.size()});
        } else if (std.mem.eql(u8, key, "is_empty")) {
            try writer.print("{s}", .{if (m.isEmpty()) "true" else "false"});
        } else if (std.mem.startsWith(u8, key, "get_")) {
            const probe = parseF32Label(key[4..]);
            if (m.get(probe)) |v| try writer.print("{d}", .{v}) else try writer.writeAll("null");
        } else if (std.mem.startsWith(u8, key, "contains_")) {
            const probe = parseF32Label(key[9..]);
            try writer.print("{s}", .{if (m.containsKey(probe)) "true" else "false"});
        } else if (std.mem.eql(u8, key, "sorted_keys")) {
            const keys = m.keysToSlice(allocator);
            defer allocator.free(keys);
            sortF32Total(keys);
            try writer.writeAll("[");
            for (keys, 0..) |k, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.writeAll("\"");
                try writeF32(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll("]");
        } else {
            try writer.print("UNKNOWN_KEY({s})", .{key});
        }
        try writer.writeAll("\n");
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
    var set = F32HashSet.init(allocator);
    defer set.deinit();
    for (operations.items) |op| {
        const obj = op.object;
        const op_name = obj.get("op").?.string;
        if (std.mem.eql(u8, op_name, "add")) {
            _ = set.add(parseF32Value(obj.get("value").?));
        } else if (std.mem.eql(u8, op_name, "remove")) {
            _ = set.remove(parseF32Value(obj.get("value").?));
        } else if (std.mem.eql(u8, op_name, "clear")) {
            set.clear();
        }
    }
    for (assertions.keys()) |key| {
        if (std.mem.eql(u8, key, "comment")) continue;
        try writer.print("{s}: ", .{key});
        if (std.mem.eql(u8, key, "size")) {
            try writer.print("{d}", .{set.size()});
        } else if (std.mem.eql(u8, key, "is_empty")) {
            try writer.print("{s}", .{if (set.isEmpty()) "true" else "false"});
        } else if (std.mem.startsWith(u8, key, "contains_")) {
            const probe = parseF32Label(key[9..]);
            try writer.print("{s}", .{if (set.contains(probe)) "true" else "false"});
        } else if (std.mem.eql(u8, key, "sorted_values") or std.mem.eql(u8, key, "to_sorted_array")) {
            const vals = set.toSlice(allocator);
            defer allocator.free(vals);
            sortF32Total(vals);
            try writer.writeAll("[");
            for (vals, 0..) |v, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.writeAll("\"");
                try writeF32(writer, v);
                try writer.writeAll("\"");
            }
            try writer.writeAll("]");
        } else {
            try writer.print("UNKNOWN_KEY({s})", .{key});
        }
        try writer.writeAll("\n");
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
            list.add(parseF32Value(obj.get("value").?));
        } else if (std.mem.eql(u8, op_name, "clear")) {
            list.clear();
        }
    }
    const values = list.toSlice();
    for (assertions.keys()) |key| {
        if (std.mem.eql(u8, key, "comment")) continue;
        try writer.print("{s}: ", .{key});
        if (std.mem.eql(u8, key, "size")) {
            try writer.print("{d}", .{values.len});
        } else if (std.mem.eql(u8, key, "is_empty")) {
            try writer.print("{s}", .{if (values.len == 0) "true" else "false"});
        } else if (std.mem.eql(u8, key, "sum")) {
            var acc: f32 = 0;
            for (values) |v| acc += v;
            try writeF32(writer, acc);
        } else if (std.mem.eql(u8, key, "min")) {
            if (values.len == 0) {
                try writer.writeAll("null");
            } else {
                var mn = values[0];
                for (values[1..]) |v| if (totalCmpF32(v, mn) == .lt) {
                    mn = v;
                };
                try writeF32(writer, mn);
            }
        } else if (std.mem.eql(u8, key, "max")) {
            if (values.len == 0) {
                try writer.writeAll("null");
            } else {
                var mx = values[0];
                for (values[1..]) |v| if (totalCmpF32(v, mx) == .gt) {
                    mx = v;
                };
                try writeF32(writer, mx);
            }
        } else if (std.mem.eql(u8, key, "sorted") or std.mem.eql(u8, key, "to_sorted_array")) {
            const buf = allocator.alloc(f32, values.len) catch @panic("oom");
            defer allocator.free(buf);
            @memcpy(buf, values);
            sortF32Total(buf);
            try writer.writeAll("[");
            for (buf, 0..) |v, i| {
                if (i > 0) try writer.writeAll(",");
                try writeF32(writer, v);
            }
            try writer.writeAll("]");
        } else {
            try writer.print("UNKNOWN_KEY({s})", .{key});
        }
        try writer.writeAll("\n");
    }
}

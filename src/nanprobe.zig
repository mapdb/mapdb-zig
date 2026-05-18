// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// nanprobe inserts IEEE 754 edge cases (NaN, -0.0, +0.0, +Inf, -Inf) into
// float-keyed maps and float element sets, then reports observed behavior
// in a canonical per-line format so outputs can be diffed across languages.

const std = @import("std");
const F32I32HashMap = @import("hashmap/f32_i32_hash_map.zig").F32I32HashMap;
const F32HashSet = @import("hashset/f32_hash_set.zig").F32HashSet;

const nan_f32: f32 = std.math.nan(f32);
const pos_inf: f32 = std.math.inf(f32);
const neg_inf: f32 = -std.math.inf(f32);

pub fn main() !void {
    // Zig 0.15 removed std.io.getStdOut(); stdout is now reached via
    // std.fs.File.stdout() and a buffered std.Io.Writer that requires
    // explicit flush. Requires Zig 0.15+.
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try stdout.print("lang: zig\n", .{});
    try probeMapNaN(allocator, stdout);
    try probeMapNegZero(allocator, stdout);
    try probeMapInfinity(allocator, stdout);
    try probeSetNaN(allocator, stdout);
    try probeSetNegZero(allocator, stdout);
    try probeSetMixed(allocator, stdout);
}

fn probeMapNaN(allocator: std.mem.Allocator, stdout: anytype) !void {
    var m = F32I32HashMap.init(allocator);
    defer m.deinit();

    _ = m.put(nan_f32, 1);
    try stdout.print("map_nan_size_after_put1: {d}\n", .{m.size()});

    _ = m.put(nan_f32, 2);
    try stdout.print("map_nan_size_after_put2: {d}\n", .{m.size()});

    _ = m.put(nan_f32, 3);
    try stdout.print("map_nan_size_after_put3: {d}\n", .{m.size()});

    const v = m.get(nan_f32);
    try stdout.print("map_nan_get_found: {}\n", .{v != null});
    try stdout.print("map_nan_get_value: {d}\n", .{v orelse 0});

    try stdout.print("map_nan_contains_key: {}\n", .{m.containsKey(nan_f32)});

    const removed = m.remove(nan_f32);
    try stdout.print("map_nan_remove_found: {}\n", .{removed != null});
    try stdout.print("map_nan_size_after_remove: {d}\n", .{m.size()});
}

fn probeMapNegZero(allocator: std.mem.Allocator, stdout: anytype) !void {
    var m = F32I32HashMap.init(allocator);
    defer m.deinit();

    _ = m.put(@as(f32, 0.0), 100);
    _ = m.put(@as(f32, -0.0), 200);

    try stdout.print("map_zero_size: {d}\n", .{m.size()});

    const v1 = m.get(@as(f32, 0.0)) orelse 0;
    const v2 = m.get(@as(f32, -0.0)) orelse 0;
    try stdout.print("map_zero_get_pos: {d}\n", .{v1});
    try stdout.print("map_zero_get_neg: {d}\n", .{v2});

    // Which zero is stored? Walk entries until we find an occupied one.
    var first_key: f32 = 0.0;
    for (0..m.inner.capacity) |i| {
        if (m.inner.entries[i].occupied) {
            first_key = m.inner.entries[i].key;
            break;
        }
    }
    const bits: u32 = @bitCast(first_key);
    const sign_bit_set = (bits & (@as(u32, 1) << 31)) != 0;
    try stdout.print("map_zero_stored_negative: {}\n", .{sign_bit_set});
}

fn probeMapInfinity(allocator: std.mem.Allocator, stdout: anytype) !void {
    var m = F32I32HashMap.init(allocator);
    defer m.deinit();

    _ = m.put(pos_inf, 111);
    _ = m.put(neg_inf, 222);

    try stdout.print("map_inf_size: {d}\n", .{m.size()});

    const v1 = m.get(pos_inf) orelse 0;
    const v2 = m.get(neg_inf) orelse 0;
    try stdout.print("map_pinf_get: {d}\n", .{v1});
    try stdout.print("map_ninf_get: {d}\n", .{v2});

    try stdout.print("map_pinf_contains: {}\n", .{m.containsKey(pos_inf)});
    try stdout.print("map_ninf_contains: {}\n", .{m.containsKey(neg_inf)});
}

fn probeSetNaN(allocator: std.mem.Allocator, stdout: anytype) !void {
    var s = F32HashSet.init(allocator);
    defer s.deinit();

    _ = s.add(nan_f32);
    _ = s.add(nan_f32);
    _ = s.add(nan_f32);
    try stdout.print("set_nan_size: {d}\n", .{s.size()});
    try stdout.print("set_nan_contains: {}\n", .{s.contains(nan_f32)});
}

fn probeSetNegZero(allocator: std.mem.Allocator, stdout: anytype) !void {
    var s = F32HashSet.init(allocator);
    defer s.deinit();

    _ = s.add(@as(f32, 0.0));
    _ = s.add(@as(f32, -0.0));
    try stdout.print("set_zero_size: {d}\n", .{s.size()});
    try stdout.print("set_pos_zero_contains: {}\n", .{s.contains(@as(f32, 0.0))});
    try stdout.print("set_neg_zero_contains: {}\n", .{s.contains(@as(f32, -0.0))});
}

fn probeSetMixed(allocator: std.mem.Allocator, stdout: anytype) !void {
    var s = F32HashSet.init(allocator);
    defer s.deinit();

    _ = s.add(@as(f32, 1.0));
    _ = s.add(nan_f32);
    _ = s.add(pos_inf);
    _ = s.add(neg_inf);
    _ = s.add(@as(f32, 0.0));
    try stdout.print("set_mixed_size: {d}\n", .{s.size()});
}

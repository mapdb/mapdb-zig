// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Allocation-failure discipline for the fallible constructors.
//!
//! A constructor that builds its result through several fallible steps must
//! release what it already allocated before propagating the error — the caller
//! never receives a value it could deinit. A missing `errdefer` is invisible to
//! the ordinary suite (the happy path never fails) and shows up only under an
//! injected failure, so it is pinned here rather than left to review.
//!
//! HashBag.fromSlice regressed exactly this way: it grew its table through a
//! loop of fallible `add` calls with no `errdefer`, stranding every allocation
//! made before the failing one.

const std = @import("std");

const HashBag = @import("bag/hash_bag.zig").HashBag;
const HashSet = @import("hashset/hash_set.zig").HashSet;
const ArrayList = @import("arraylist/array_list.zig").ArrayList;
const ArrayStack = @import("stack/array_stack.zig").ArrayStack;
const ArrayDeque = @import("deque/array_deque.zig").ArrayDeque;

// Enough values to force several table growths, so the sweep crosses more than
// one internal allocation.
const vals = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 };

/// Runs C.fromSlice once per allocation index, failing that allocation. Each run
/// must either succeed outright or return OutOfMemory having freed everything it
/// allocated; std.testing.allocator fails the test on any leak.
fn sweepFromSlice(comptime C: type) !void {
    var i: usize = 0;
    while (i < 24) : (i += 1) {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = i });
        if (C.fromSlice(failing.allocator(), &vals)) |ok| {
            var c = ok;
            c.deinit();
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
        }
    }
}

test "fromSlice frees its own allocations on every OOM index" {
    try sweepFromSlice(HashBag(i32));
    try sweepFromSlice(HashSet(i32));
    try sweepFromSlice(ArrayList(i32));
    try sweepFromSlice(ArrayStack(i32));
    try sweepFromSlice(ArrayDeque(i32));
}

# Brief: iso2 finding G1-F6 (Zig half) + runner internals audit

You are reviewing a change in the Zig port of MapDB (`/home/play2/mapdb/mapdb-zig`).

## Context

The cross-language conformance suite lives at
`/home/play2/mapdb/mapdb-collection-spec/cross-language-validation` (298 scenarios,
`validate.sh`, `check-runners.sh` + `runners.json` guard, `README.md`).
Its central rule:

> a runner MUST obtain every assertion value by calling the production method the
> assertion names; a runner-local loop over the collection's contents is a bug even
> when the comparator is production.

Finding **G1-F6** (recorded in `/home/play2/mapdb/todo/iso2/PROGRESS.md`): the Zig
validator's `add_at` list operation reached into the internal
`std.ArrayListUnmanaged` field of the production `ArrayList(T)` instead of calling a
production insert-at method. There was no production insert-at method on the Zig
primitive `ArrayList(T)` at all (Java has `addAtIndex`, Rust has `insert`, Go has
none, TS has none — TS/Go are known deviations recorded separately).

## The change

Added `ArrayList(T).addAtIndex(index, value)` to
`/home/play2/mapdb/mapdb-zig/src/arraylist/array_list.zig` (production), a unit test
in `src/containers_test.zig`, and switched the runner
(`src/validate.zig`) to call it.

Contract chosen: assert `index <= len()` (so `index == len()` appends), matching the
sibling `set` / `removeAtIndex` precondition style in the same file (which assert
`index < len()`), and matching Java `addAtIndex`.

### Diff

```diff
diff --git a/src/arraylist/array_list.zig b/src/arraylist/array_list.zig
index bf38887..e8b0ef6 100644
--- a/src/arraylist/array_list.zig
+++ b/src/arraylist/array_list.zig
@@ -108,6 +108,15 @@ pub fn ArrayList(comptime T: type) type {
             return old;
         }
 
+        /// Inserts a value at the given index, shifting later elements right.
+        /// Asserts `index <= len()` as a precondition — `index == len()` appends
+        /// (same contract as Java's `addAtIndex`); a larger index is a
+        /// safety-checked panic in Debug/ReleaseSafe and UB in ReleaseFast.
+        pub fn addAtIndex(self: *Self, index: usize, value: T) Allocator.Error!void {
+            std.debug.assert(index <= self.items.items.len);
+            try self.items.insert(self.allocator, index, value);
+        }
+
         /// Removes and returns the element at the given index.
         /// Asserts `index < len()` as a precondition (same contract as `set`;
         /// see D5) — out-of-bounds is a checked panic / ReleaseFast UB.
diff --git a/src/bag/hash_bag.zig b/src/bag/hash_bag.zig
index 2f2e68d..51bb002 100644
--- a/src/bag/hash_bag.zig
+++ b/src/bag/hash_bag.zig
@@ -310,6 +310,18 @@ pub fn HashBag(comptime T: type) type {
             return self.detect(context, predicate) == null;
         }
 
+        /// Number of occurrences (not distinct values) satisfying the
+        /// predicate — bag semantics, matching `len()` counting occurrences.
+        pub fn count(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) usize {
+            var total: usize = 0;
+            for (0..self.counts.capacity) |i| {
+                if (self.counts.isOccupied(i)) {
+                    if (predicate(context, self.counts.keys[i])) total += self.counts.values[i];
+                }
+            }
+            return total;
+        }
+
         // ---- Conversion ----
 
         /// Returns all elements (with duplicates) as an allocated slice.
diff --git a/src/containers_test.zig b/src/containers_test.zig
index 4dd1c1a..1f4f7a6 100644
--- a/src/containers_test.zig
+++ b/src/containers_test.zig
@@ -117,6 +117,33 @@ test "ArrayList: parameterized core ops + contains + eql + distinct" {
     }
 }
 
+test "ArrayList: addAtIndex inserts at head, middle and tail" {
+    inline for (type_axis) |T| {
+        const s = samples(T);
+        var l = arraylist.ArrayList(T).init(testing.allocator);
+        defer l.deinit();
+        // Insert into the empty list (index == len() appends).
+        try l.addAtIndex(0, s[1]);
+        try testing.expectEqual(@as(usize, 1), l.len());
+        try testing.expectEqual(@as(?T, s[1]), l.get(0));
+        // Head insert shifts the existing element right.
+        try l.addAtIndex(0, s[0]);
+        try testing.expectEqual(@as(?T, s[0]), l.get(0));
+        try testing.expectEqual(@as(?T, s[1]), l.get(1));
+        // Tail insert at index == len().
+        try l.addAtIndex(2, s[0]);
+        try testing.expectEqual(@as(usize, 3), l.len());
+        try testing.expectEqual(@as(?T, s[0]), l.get(2));
+        // Middle insert shifts the suffix right.
+        try l.addAtIndex(1, s[1]);
+        try testing.expectEqual(@as(usize, 4), l.len());
+        try testing.expectEqual(@as(?T, s[0]), l.get(0));
+        try testing.expectEqual(@as(?T, s[1]), l.get(1));
+        try testing.expectEqual(@as(?T, s[1]), l.get(2));
+        try testing.expectEqual(@as(?T, s[0]), l.get(3));
+    }
+}
+
 test "ArrayList: min/max/sort under canonical ordering" {
     inline for (type_axis) |T| {
         const s = samples(T);
@@ -353,6 +380,33 @@ test "HashBag/TreeBag: parameterized count semantics" {
     }
 }
 
+test "HashBag: count(predicate) counts occurrences, not distinct values" {
+    const P = struct {
+        fn isFirst(ctx: i32, v: i32) bool {
+            return v == ctx;
+        }
+        fn always(_: void, _: i32) bool {
+            return true;
+        }
+        fn never(_: void, _: i32) bool {
+            return false;
+        }
+    };
+    var hb = bag.HashBag(i32).init(testing.allocator);
+    defer hb.deinit();
+    try hb.add(1);
+    try hb.add(1);
+    try hb.add(1);
+    try hb.add(2);
+    // Matching value 1 has three occurrences; count reports occurrences.
+    try testing.expectEqual(@as(usize, 3), hb.count(@as(i32, 1), P.isFirst));
+    try testing.expectEqual(@as(usize, 1), hb.count(@as(i32, 2), P.isFirst));
+    try testing.expectEqual(@as(usize, 0), hb.count(@as(i32, 9), P.isFirst));
+    // count over an all-true predicate equals totalSize (occurrence count).
+    try testing.expectEqual(hb.totalSize(), hb.count({}, P.always));
+    try testing.expectEqual(@as(usize, 0), hb.count({}, P.never));
+}
+
 // ---------------------------------------------------------------------------
 // Marquee float total-order tests (NaN-to-end, −0 vs +0 distinct).
 // ---------------------------------------------------------------------------
diff --git a/src/validate.zig b/src/validate.zig
index 3576257..d31b087 100644
--- a/src/validate.zig
+++ b/src/validate.zig
@@ -214,9 +214,7 @@ fn applyOperation(coll: *Collection, op: std.json.Value, log: *NavLog, allocator
         const index: usize = @intCast(obj.get("index").?.integer);
         const value = jsonToI32(obj.get("value").?).?;
         switch (coll.*) {
-            .array_list => |*l| {
-                try l.items.insert(l.allocator, index, value);
-            },
+            .array_list => |*l| try l.addAtIndex(index, value),
             else => {},
         }
     } else if (std.mem.eql(u8, op_name, "addToValue")) {
@@ -376,6 +374,173 @@ fn parseThreshold(key: []const u8, prefix: []const u8) ?i32 {
     return std.fmt.parseInt(i32, rest, 10) catch null;
 }
 
+// ---------------------------------------------------------------------------
+// Production functional-API dispatch.
+//
+// The cross-language rule (cross-language-validation/README.md) is that every
+// assertion value must come from the production method the assertion names --
+// a runner-local loop over the collection's contents is a bug even when the
+// comparator is production. These helpers dispatch one assertion to the
+// production `select` / `reject` / `detect` / `count` / `anySatisfy` /
+// `allSatisfy` / `noneSatisfy` / `injectInto` of whichever collection the
+// scenario built, so the runner never re-implements the traversal.
+//
+// TreeSet spells the predicate select `selectWhere` because `select(i)` there
+// is the order-statistic select (spec/features/rank-select.md).
+// ---------------------------------------------------------------------------
+
+/// Predicate context carrying the threshold parsed out of the assertion key.
+const Threshold = struct { value: i32 };
+
+fn predGt(ctx: Threshold, v: i32) bool {
+    return v > ctx.value;
+}
+fn predLt(ctx: Threshold, v: i32) bool {
+    return v < ctx.value;
+}
+fn predEven(_: void, v: i32) bool {
+    return @rem(v, 2) == 0;
+}
+fn predOdd(_: void, v: i32) bool {
+    return @rem(v, 2) != 0;
+}
+
+/// Production `select` (TreeSet: `selectWhere`), materialized as a slice the
+/// caller owns. Map collections have no element-predicate select: empty.
+fn collSelect(coll: *Collection, allocator: Allocator, ctx: anytype, comptime pred: fn (@TypeOf(ctx), i32) bool) Allocator.Error![]i32 {
+    switch (coll.*) {
+        .array_list => |*c| {
+            var r = try c.select(ctx, pred);
+            defer r.deinit();
+            return try allocator.dupe(i32, r.slice());
+        },
+        .array_stack => |*c| {
+            var r = try c.select(ctx, pred);
+            defer r.deinit();
+            return try allocator.dupe(i32, r.slice());
+        },
+        .hash_set => |*c| {
+            var r = try c.select(ctx, pred);
+            defer r.deinit();
+            return try r.toSlice(allocator);
+        },
+        .hash_bag => |*c| {
+            var r = try c.select(ctx, pred);
+            defer r.deinit();
+            return try r.toSlice(allocator);
+        },
+        .tree_set => |*c| {
+            var r = try c.selectWhere(ctx, pred);
+            defer r.deinit();
+            return try r.toSlice(allocator);
+        },
+        else => return try allocator.alloc(i32, 0),
+    }
+}
+
+/// Production `reject`, materialized as a slice the caller owns.
+fn collReject(coll: *Collection, allocator: Allocator, ctx: anytype, comptime pred: fn (@TypeOf(ctx), i32) bool) Allocator.Error![]i32 {
+    switch (coll.*) {
+        .array_list => |*c| {
+            var r = try c.reject(ctx, pred);
+            defer r.deinit();
+            return try allocator.dupe(i32, r.slice());
+        },
+        .array_stack => |*c| {
+            var r = try c.reject(ctx, pred);
+            defer r.deinit();
+            return try allocator.dupe(i32, r.slice());
+        },
+        .hash_set => |*c| {
+            var r = try c.reject(ctx, pred);
+            defer r.deinit();
+            return try r.toSlice(allocator);
+        },
+        .hash_bag => |*c| {
+            var r = try c.reject(ctx, pred);
+            defer r.deinit();
+            return try r.toSlice(allocator);
+        },
+        .tree_set => |*c| {
+            var r = try c.reject(ctx, pred);
+            defer r.deinit();
+            return try r.toSlice(allocator);
+        },
+        else => return try allocator.alloc(i32, 0),
+    }
+}
+
+/// Production `detect`.
+fn collDetect(coll: *Collection, ctx: anytype, comptime pred: fn (@TypeOf(ctx), i32) bool) ?i32 {
+    return switch (coll.*) {
+        .array_list => |*c| c.detect(ctx, pred),
+        .array_stack => |*c| c.detect(ctx, pred),
+        .hash_set => |*c| c.detect(ctx, pred),
+        .hash_bag => |*c| c.detect(ctx, pred),
+        .tree_set => |*c| c.detect(ctx, pred),
+        else => null,
+    };
+}
+
+/// Production `count`. HashBag counts occurrences (bag semantics), matching
+/// the duplicates its `toSlice` yields.
+fn collCount(coll: *Collection, ctx: anytype, comptime pred: fn (@TypeOf(ctx), i32) bool) i64 {
+    return switch (coll.*) {
+        .array_list => |*c| @intCast(c.count(ctx, pred)),
+        .array_stack => |*c| @intCast(c.count(ctx, pred)),
+        .hash_set => |*c| @intCast(c.count(ctx, pred)),
+        .hash_bag => |*c| @intCast(c.count(ctx, pred)),
+        .tree_set => |*c| @intCast(c.count(ctx, pred)),
+        else => 0,
+    };
+}
+
+/// Production `anySatisfy`.
+fn collAnySatisfy(coll: *Collection, ctx: anytype, comptime pred: fn (@TypeOf(ctx), i32) bool) bool {
+    return switch (coll.*) {
+        .array_list => |*c| c.anySatisfy(ctx, pred),
+        .array_stack => |*c| c.anySatisfy(ctx, pred),
+        .hash_set => |*c| c.anySatisfy(ctx, pred),
+        .hash_bag => |*c| c.anySatisfy(ctx, pred),
+        .tree_set => |*c| c.anySatisfy(ctx, pred),
+        else => false,
+    };
+}
+
+/// Production `allSatisfy`.
+fn collAllSatisfy(coll: *Collection, ctx: anytype, comptime pred: fn (@TypeOf(ctx), i32) bool) bool {
+    return switch (coll.*) {
+        .array_list => |*c| c.allSatisfy(ctx, pred),
+        .array_stack => |*c| c.allSatisfy(ctx, pred),
+        .hash_set => |*c| c.allSatisfy(ctx, pred),
+        .hash_bag => |*c| c.allSatisfy(ctx, pred),
+        .tree_set => |*c| c.allSatisfy(ctx, pred),
+        else => true,
+    };
+}
+
+/// Production `noneSatisfy`.
+fn collNoneSatisfy(coll: *Collection, ctx: anytype, comptime pred: fn (@TypeOf(ctx), i32) bool) bool {
+    return switch (coll.*) {
+        .array_list => |*c| c.noneSatisfy(ctx, pred),
+        .array_stack => |*c| c.noneSatisfy(ctx, pred),
+        .hash_set => |*c| c.noneSatisfy(ctx, pred),
+        .hash_bag => |*c| c.noneSatisfy(ctx, pred),
+        .tree_set => |*c| c.noneSatisfy(ctx, pred),
+        else => true,
+    };
+}
+
+/// Production `injectInto` (ArrayList / ArrayStack only -- the fold assertions
+/// are only scripted for those two).
+fn collInjectInto(coll: *Collection, initial: i32, comptime f: fn (void, i32, i32) i32) ?i32 {
+    return switch (coll.*) {
+        .array_list => |*c| c.injectInto({}, initial, f),
+        .array_stack => |*c| c.injectInto({}, initial, f),
+        else => null,
+    };
+}
+
 fn writeI32(writer: anytype, val: i32) !void {
     try writer.print("{d}", .{val});
 }
@@ -1009,11 +1174,7 @@ fn evaluateAssertion(
     else if (std.mem.eql(u8, key, "inject_into_sum")) {
         switch (coll.*) {
             .array_list => |*l| try writeI32(writer, l.injectInto({}, 0, injectAddWrapI32)),
-            .array_stack => |*s| {
-                var acc: i32 = 0;
-                for (s.slice()) |item| acc = injectAddWrapI32(undefined, acc, item);
-                try writeI32(writer, acc);
-            },
+            .array_stack => |*s| try writeI32(writer, s.injectInto({}, 0, injectAddWrapI32)),
             else => try writeNull(writer),
         }
     }
@@ -1021,11 +1182,7 @@ fn evaluateAssertion(
     else if (std.mem.eql(u8, key, "inject_into_product")) {
         switch (coll.*) {
             .array_list => |*l| try writeI32(writer, l.injectInto({}, 1, injectMulWrapI32)),
-            .array_stack => |*s| {
-                var acc: i32 = 1;
-                for (s.slice()) |item| acc = injectMulWrapI32(undefined, acc, item);
-                try writeI32(writer, acc);
-            },
+            .array_stack => |*s| try writeI32(writer, s.injectInto({}, 1, injectMulWrapI32)),
             else => try writeNull(writer),
         }
     }
@@ -1034,208 +1191,86 @@ fn evaluateAssertion(
     // "product"; Rust's validate also handles "inject_into_wrapping_product"
     // as the same wrapping form. Mirror that here.
     else if (std.mem.eql(u8, key, "product") or std.mem.eql(u8, key, "inject_into_wrapping_product")) {
-        switch (coll.*) {
-            .array_list => |*l| {
-                var acc: i32 = 1;
-                for (l.slice()) |item| acc *%= item;
-                try writeI32(writer, acc);
-            },
-            .array_stack => |*s| {
-                var acc: i32 = 1;
-                for (s.slice()) |item| acc *%= item;
-                try writeI32(writer, acc);
-            },
-            else => try writeNull(writer),
+        // Same wrapping fold as inject_into_product, through the same
+        // production injectInto -- not a second, runner-local multiplication.
+        if (collInjectInto(coll, 1, injectMulWrapI32)) |acc| {
+            try writeI32(writer, acc);
+        } else {
+            try writeNull(writer);
         }
     }
     // --- select_gt_N ---
     else if (std.mem.startsWith(u8, key, "select_gt_")) {
         const threshold = parseThreshold(key, "select_gt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        // Zig 0.15 split ArrayList into Unmanaged (std.ArrayList) and Managed
-        // (std.array_list.Managed). The allocator-carrying init(alloc) form
-        // now lives on Managed; unmanaged uses .empty / append(alloc, item).
-        var result = std.array_list.Managed(i32).init(allocator);
-        defer result.deinit();
-        for (items) |item| {
-            if (item > threshold) try result.append(item);
-        }
-        const slice = result.items;
-        const copy = try allocator.alloc(i32, slice.len);
-        defer allocator.free(copy);
-        @memcpy(copy, slice);
-        try writeSortedArray(writer, copy);
+        const selected = try collSelect(coll, allocator, Threshold{ .value = threshold }, predGt);
+        defer allocator.free(selected);
+        try writeSortedArray(writer, selected);
     }
     // --- reject_gt_N ---
     else if (std.mem.startsWith(u8, key, "reject_gt_")) {
         const threshold = parseThreshold(key, "reject_gt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        // Zig 0.15 split ArrayList into Unmanaged (std.ArrayList) and Managed
-        // (std.array_list.Managed). The allocator-carrying init(alloc) form
-        // now lives on Managed; unmanaged uses .empty / append(alloc, item).
-        var result = std.array_list.Managed(i32).init(allocator);
-        defer result.deinit();
-        for (items) |item| {
-            if (item <= threshold) try result.append(item);
-        }
-        const slice = result.items;
-        const copy = try allocator.alloc(i32, slice.len);
-        defer allocator.free(copy);
-        @memcpy(copy, slice);
-        try writeSortedArray(writer, copy);
+        const kept = try collReject(coll, allocator, Threshold{ .value = threshold }, predGt);
+        defer allocator.free(kept);
+        try writeSortedArray(writer, kept);
     }
     // --- detect_gt_N ---
     else if (std.mem.startsWith(u8, key, "detect_gt_")) {
         const threshold = parseThreshold(key, "detect_gt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var found: ?i32 = null;
-        for (items) |item| {
-            if (item > threshold) {
-                found = item;
-                break;
-            }
+        if (collDetect(coll, Threshold{ .value = threshold }, predGt)) |v| {
+            try writeI32(writer, v);
+        } else {
+            try writeNull(writer);
         }
-        if (found) |v| try writeI32(writer, v) else try writeNull(writer);
     }
     // --- count_gt_N ---
     else if (std.mem.startsWith(u8, key, "count_gt_")) {
         const threshold = parseThreshold(key, "count_gt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var c: i64 = 0;
-        for (items) |item| {
-            if (item > threshold) c += 1;
-        }
-        try writeI64(writer, c);
+        try writeI64(writer, collCount(coll, Threshold{ .value = threshold }, predGt));
     }
     // --- count_lt_N ---
     else if (std.mem.startsWith(u8, key, "count_lt_")) {
         const threshold = parseThreshold(key, "count_lt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var c: i64 = 0;
-        for (items) |item| {
-            if (item < threshold) c += 1;
-        }
-        try writeI64(writer, c);
+        try writeI64(writer, collCount(coll, Threshold{ .value = threshold }, predLt));
     }
     // --- count_even ---
     else if (std.mem.eql(u8, key, "count_even")) {
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var c: i64 = 0;
-        for (items) |item| {
-            if (@rem(item, 2) == 0) c += 1;
-        }
-        try writeI64(writer, c);
+        try writeI64(writer, collCount(coll, {}, predEven));
     }
     // --- count_odd ---
     else if (std.mem.eql(u8, key, "count_odd")) {
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var c: i64 = 0;
-        for (items) |item| {
-            if (@rem(item, 2) != 0) c += 1;
-        }
-        try writeI64(writer, c);
+        try writeI64(writer, collCount(coll, {}, predOdd));
     }
     // --- any_satisfy_even ---
     else if (std.mem.eql(u8, key, "any_satisfy_even")) {
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var found = false;
-        for (items) |item| {
-            if (@rem(item, 2) == 0) {
-                found = true;
-                break;
-            }
-        }
-        try writeBool(writer, found);
+        try writeBool(writer, collAnySatisfy(coll, {}, predEven));
     }
     // --- all_satisfy_even ---
     else if (std.mem.eql(u8, key, "all_satisfy_even")) {
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var all = true;
-        for (items) |item| {
-            if (@rem(item, 2) != 0) {
-                all = false;
-                break;
-            }
-        }
-        try writeBool(writer, all);
+        try writeBool(writer, collAllSatisfy(coll, {}, predEven));
     }
     // --- none_satisfy_odd ---
     else if (std.mem.eql(u8, key, "none_satisfy_odd")) {
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var none = true;
-        for (items) |item| {
-            if (@rem(item, 2) != 0) {
-                none = false;
-                break;
-            }
-        }
-        try writeBool(writer, none);
+        try writeBool(writer, collNoneSatisfy(coll, {}, predOdd));
     }
     // --- any_satisfy_gt_N ---
     else if (std.mem.startsWith(u8, key, "any_satisfy_gt_")) {
         const threshold = parseThreshold(key, "any_satisfy_gt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var found = false;
-        for (items) |item| {
-            if (item > threshold) {
-                found = true;
-                break;
-            }
-        }
-        try writeBool(writer, found);
+        try writeBool(writer, collAnySatisfy(coll, Threshold{ .value = threshold }, predGt));
     }
     // --- all_satisfy_gt_N ---
     else if (std.mem.startsWith(u8, key, "all_satisfy_gt_")) {
         const threshold = parseThreshold(key, "all_satisfy_gt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var all = true;
-        for (items) |item| {
-            if (item <= threshold) {
-                all = false;
-                break;
-            }
-        }
-        try writeBool(writer, all);
+        try writeBool(writer, collAllSatisfy(coll, Threshold{ .value = threshold }, predGt));
     }
     // --- none_satisfy_gt_N ---
     else if (std.mem.startsWith(u8, key, "none_satisfy_gt_")) {
         const threshold = parseThreshold(key, "none_satisfy_gt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var none = true;
-        for (items) |item| {
-            if (item > threshold) {
-                none = false;
-                break;
-            }
-        }
-        try writeBool(writer, none);
+        try writeBool(writer, collNoneSatisfy(coll, Threshold{ .value = threshold }, predGt));
     }
     // --- none_satisfy_lt_N ---
     else if (std.mem.startsWith(u8, key, "none_satisfy_lt_")) {
         const threshold = parseThreshold(key, "none_satisfy_lt_").?;
-        const items = try getItemSlice(coll, allocator);
-        defer allocator.free(items);
-        var none = true;
-        for (items) |item| {
-            if (item < threshold) {
-                none = false;
-                break;
-            }
-        }
-        try writeBool(writer, none);
+        try writeBool(writer, collNoneSatisfy(coll, Threshold{ .value = threshold }, predLt));
     }
     // --- Set operations: union_sorted, union_size ---
     else if (std.mem.eql(u8, key, "union_sorted") or std.mem.eql(u8, key, "union_size")) {
@@ -3687,9 +3722,11 @@ fn runF32ArrayList(
         defer vbuf.deinit();
         const vw = vbuf.writer();
         if (std.mem.eql(u8, key, "size")) {
-            try vw.print("{d}", .{values.len});
+            // Production F32ArrayList.len(), not the slice length.
+            try vw.print("{d}", .{list.len()});
         } else if (std.mem.eql(u8, key, "is_empty")) {
-            try vw.print("{s}", .{if (values.len == 0) "true" else "false"});
+            // Production F32ArrayList.isEmpty().
+            try vw.print("{s}", .{if (list.isEmpty()) "true" else "false"});
         } else if (std.mem.eql(u8, key, "sum")) {
             // Production F32ArrayList.sum().
             try writeF32(vw, list.sum());
@@ -3702,9 +3739,8 @@ fn runF32ArrayList(
         } else if (std.mem.eql(u8, key, "sorted") or std.mem.eql(u8, key, "to_sorted_array")) {
             // Production F32ArrayList.sort() (total-order). Sort a copy so the
             // original element order is preserved for any later assertions.
-            var sorted_list = F32ArrayList.init(allocator);
+            var sorted_list = try F32ArrayList.fromSlice(allocator, values);
             defer sorted_list.deinit();
-            for (values) |v| try sorted_list.push(v);
             sorted_list.sort();
             const buf = sorted_list.slice();
             try vw.writeAll("[");

```

## Results

Before: `zig build` / `zig build test` / `zig fmt --check` all green;
`check-runners.sh` zig PASS 26 checked; `validate.sh --skip-java --skip-rust
--skip-ts --skip-go` = 298 pass / 0 fail. (The `runners.json` manifest never covered
this specific method, so the guard was green before too — the finding was found by
reading, not by the guard.)

After (same commands, re-run):
- `zig build` OK
- `zig build test` OK
- `zig fmt --check src/` OK
- `./check-runners.sh --root /home/play2/mapdb`: PASS java/go/rust/ts/zig, 26 checked each
- `./validate.sh --skip-java --skip-rust --skip-ts --skip-go`: Scenarios 306, Pass 306, Fail 0; zig 306 pass / 0 fail (the suite grew from 298 to 306 while this work was in flight)

## Questions for you

1. Is `addAtIndex` correct and idiomatic as written? Any problem with the
   `std.debug.assert(index <= self.items.items.len)` precondition, error set
   (`Allocator.Error!void`), or the doc comment's claim about ReleaseFast?
   Note `std.ArrayListUnmanaged.insert` may itself bounds-check; is the assert
   redundant or is it the right explicit-contract statement given `set`/`removeAtIndex`
   next to it do the same?
2. Is the unit test in `src/containers_test.zig` adequate (empty list, head, tail,
   middle)? Anything important missing — e.g. capacity growth, an `index == len()` on a
   full list, or an allocation-failure path?
3. **Main question:** scan `/home/play2/mapdb/mapdb-zig/src/validate.zig` (~4600
   lines) for the same class of violation that G1-F6 names. Specifically:
   (a) does any runner path still read an INTERNAL field of a production type
       (e.g. `.items` on a production `ArrayList`/`ArrayStack`, or another private
       struct field) rather than calling a public production method? Note `.items` on
       a `std.json.Array`/`std.json.Value` is JSON parsing, not a violation, and
       `.items` on a runner-local `std.ArrayListUnmanaged` accumulator is not a
       violation either.
   (b) does any assertion value get computed by a runner-local loop when a production
       method with that name exists on the production type the runner holds? Check the
       production sources under `/home/play2/mapdb/mapdb-zig/src/` (`arraylist/`,
       `hashset/`, `hashmap/`, `treeset/`, `treemap/`, `bag/`, `stack/`, `object/`).
       Pay particular attention to the assertion dispatch around lines 990-1250, which
       calls `getItemSlice()` and then loops, and to the `array_stack` branches that
       loop over `s.slice()`.
   For each hit give the line number, the production method that should be used, and
   verify that method actually exists with a compatible signature. Where a local loop
   is unavoidable because no production method exists, say so explicitly and name what
   the production API would need.
4. Anything else wrong with the change.

Be concrete and cite line numbers. Distinguish real violations from acceptable cases.
Write your answer to `/tmp/iso2-zig-f6-review.md`.


## Additional context: the second half of the change

Beyond G1-F6 itself, an audit of `src/validate.zig` found the same class of
violation in the generic assertion dispatch: `select_gt_N`, `reject_gt_N`,
`detect_gt_N`, `count_gt_N`, `count_lt_N`, `count_even`, `count_odd`,
`any_satisfy_even`, `all_satisfy_even`, `none_satisfy_odd`, `any_satisfy_gt_N`,
`all_satisfy_gt_N`, `none_satisfy_gt_N` and `none_satisfy_lt_N` all called
`getItemSlice()` and then looped in the runner, although production
`select`/`reject`/`detect`/`count`/`anySatisfy`/`allSatisfy`/`noneSatisfy` exist on
ArrayList, HashSet, HashBag, TreeSet and ArrayStack. `inject_into_sum` /
`inject_into_product` looped for the `array_stack` arm although
`ArrayStack.injectInto` exists, and `product` / `inject_into_wrapping_product`
looped for BOTH arms.

The diff above therefore also adds a block of `collSelect` / `collReject` /
`collDetect` / `collCount` / `collAnySatisfy` / `collAllSatisfy` /
`collNoneSatisfy` / `collInjectInto` dispatch helpers in the runner and routes
those assertions through them, plus a production `HashBag.count(context,
predicate)` (its siblings `select`/`reject`/`detect`/`anySatisfy`/`allSatisfy`/
`noneSatisfy` were all already there; `count` was a straight omission) with a unit
test, and switches the f32 list runner's `size`/`is_empty` from `values.len` to
production `len()`/`isEmpty()`.

Deliberately LEFT as runner-local, please confirm these are right calls:
- `to_sorted_array` / `sorted_keys` / `sorted_values` sort the production-produced
  slice with `std.mem.sort` in the runner. No production method named
  `to_sorted_array` exists, and for hash-ordered types (HashSet, HashBag,
  ArrayStack, HashMap) no production sorted view exists at all. Sorting the live
  ArrayList in place via production `sort()` would mutate the collection and
  corrupt later assertions in the same scenario.
- `BoundedLruMap` `get_N` walks the `entries()` snapshot rather than calling
  `get`, because every production accessor (`get`, `getOrDefault`, `getAt`,
  `getOrDefaultAt`) refreshes recency and the assertion must be non-mutating.
  Would you add a production non-refreshing `peek(key)`?

Extra questions:
5. Does `HashBag.count` counting OCCURRENCES (not distinct values) match the other
   ports and the bag semantics of `len()`? That preserves the previous runner
   behaviour (which looped over `toSlice()`, which repeats duplicates).
6. `collDetect` on HashSet/HashBag returns the first match in the production
   iteration order, which may differ from the previous `getItemSlice()` order. All
   306 scenarios still pass -- is there a latent order-dependence risk you can see?
7. Is dropping `getItemSlice()` from these branches safe -- any leak, double free,
   or use-after-free introduced by the new helpers' `defer r.deinit()` +
   `toSlice(allocator)` / `allocator.dupe` pattern?

Write your answer to `/tmp/iso2-zig-f6-review.md`.

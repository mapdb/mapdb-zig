# Review: iso2 G1-F6 (Zig) and validator audit

## Verdict

The `addAtIndex` production change is correct, idiomatic for this codebase, and fixes G1-F6. The new functional dispatch also correctly removes the listed runner-local implementations. I would not call the broader runner audit complete, however: there are three remaining cases where an assertion has a matching production method but the runner obtains the answer through a different API. There is also a separate `sorted_values` contract inconsistency.

## Findings

### 1. The generic `is_empty` assertion still does not call production `isEmpty`

At `src/validate.zig:1025-1026`, `is_empty` is computed as:

```zig
getCollectionSize(coll) == 0
```

`getCollectionSize` (`src/validate.zig:1389-1398`) dispatches to `len()`. This is semantically equivalent today, but it violates the stated runner rule and cannot catch a defective production `isEmpty()` implementation. The compatible method exists on every member of `Collection`:

- `src/hashmap/hash_map.zig:174` — `isEmpty(self: *const Self) bool`
- `src/arraylist/array_list.zig:159` — same signature
- `src/hashset/hash_set.zig:124` — same signature
- `src/bag/hash_bag.zig:148` — same signature
- `src/treeset/tree_set.zig:230` — same signature
- `src/treemap/tree_map.zig:141` — same signature
- `src/stack/array_stack.zig:76` — same signature

Add an `isCollectionEmpty` switch which calls those methods and use it at line 1026. The f32-list change at `src/validate.zig:3727-3729` already makes exactly this correction for that separate runner.

### 2. `as_ranges` bypasses the matching production `asRanges`

At `src/validate.zig:4564-4565`, the `as_ranges` assertion calls `set.items()`. `items()` is a public borrowed-view method, not an internal-field access, so this is not category 3(a). It nevertheless bypasses the method named by the assertion.

The exact compatible production API exists at `src/range_set.zig:312`:

```zig
pub fn asRanges(self: Self, allocator: Allocator) ![]Range
```

The runner should call `set.asRanges(allocator)`, defer-free the returned slice, and render it. That tests the production copy/materialization path as well as its contents.

### 3. `as_map_of_ranges` similarly bypasses `asMapOfRanges`

At `src/validate.zig:4643-4644`, `as_map_of_ranges` calls `map.items()`. Again, this is a public method rather than an internal field, but the exact matching production API exists at `src/range_map.zig:178`:

```zig
pub fn asMapOfRanges(self: Self, allocator: Allocator) ![]Entry
```

Use that allocated result and defer-free it. The `items()` calls used only to serialize the result of `complement()` or `subRangeSet()`/`subRangeMap()` are acceptable: the substantive operation is already performed by the named production method, and the remaining loop is canonical rendering.

### 4. Separate contract issue: TreeMap `sorted_values` is not sorted by value

At `src/validate.zig:1157-1160`, the TreeMap arm writes `m.valuesSlice()` directly. That slice is in key order. The suite README at `cross-language-validation/README.md:625` defines `sorted_values` as “All values, sorted ascending,” and the brief's claim that `sorted_values` sorts a production-produced slice is therefore not true for this arm.

There is no production sorted-values view, so the correct harness action is to duplicate `valuesSlice()`, sort the copy, and render it. This is the same acceptable canonicalization used by the HashMap arm. There is also a scenario/spec inconsistency: `scenarios/17-bulk-load/treemap_i32_from_sorted.json` currently expects `[100,0,50,200,210]`, which is key order rather than ascending value order. The spec and scenario need to be reconciled together; changing only the runner would make that scenario fail.

### 5. Unsupported functional assertions currently manufacture answers instead of becoming unknown

The default arms in the new helpers return `[]`, `null`, `0`, `false`, or `true` (`src/validate.zig:437,469,481,494,506,518,530`). Current functional scenarios target ArrayList, so this does not affect the 306 cases. For a future map scenario, however, the runner would emit a plausible assertion value rather than `UNKNOWN_ASSERTION`, risking a false green.

Maps have a different predicate shape `(context, key, value)`, so the existing one-argument predicates are not directly compatible. The helpers should report “unsupported” to `evaluateAssertion`, which should emit the unknown sentinel, unless map-specific assertion semantics are added.

## `addAtIndex` review

`src/arraylist/array_list.zig:115-118` is correct:

- `index <= len` is the right insertion precondition and permits append at `index == len`.
- `Allocator.Error!void` exactly matches `std.ArrayListUnmanaged.insert` in Zig 0.15.2 (including `error.OutOfMemory`).
- The explicit `std.debug.assert` is mildly redundant with the stdlib method's documented precondition, but it is useful and consistent with adjacent `set` and `removeAtIndex`. It also rejects an invalid index before the stdlib growth path can allocate.
- The ReleaseFast statement is correct: `std.debug.assert` becomes an optimizer assumption and violating it is illegal behavior. The comment is incomplete because the same is true in ReleaseSmall. I would say “Debug/ReleaseSafe panic; ReleaseFast/ReleaseSmall illegal behavior” here and in the adjacent comments for consistency.

The implementation could spell the assertion as `index <= self.len()`, but directly reading its own backing storage inside the production type is entirely legitimate and avoids no meaningful issue.

## Unit-test adequacy

The test at `src/containers_test.zig:120-145` adequately covers the behavioral contract across all eight element types: insertion into empty, head shift, tail append, and middle shift. The first insertion also exercises allocation from zero capacity. A specifically full-buffer insertion would only retest stdlib growth mechanics and is not necessary for this thin wrapper.

An optional useful addition is a `FailingAllocator` test which forces the initial insert to return `error.OutOfMemory` and verifies `len() == 0`. That would pin the advertised error propagation and no-mutation-on-failure behavior, but its absence is not a blocker. An invalid-index panic test would pin the precondition, but Zig 0.15's standard testing surface does not make that especially convenient and the assertion is explicit.

## Audit of `validate.zig`

### Direct internal-field access

I found no remaining direct read/write of an internal field of a production collection. In particular, the old `l.items.insert(l.allocator, ...)` is gone; `add_at` now calls `l.addAtIndex` at `src/validate.zig:217`.

The remaining `.items` field accesses are acceptable:

- JSON parsing (`operations.items`, JSON arrays).
- Runner-local output buffers (`cbuf.items`, `ebuf.items`, `vbuf.items`).
- Runner-local `NavLog`, `LruEvictLog`, and `LruResultLog` accumulators.
- At `src/validate.zig:4565,4585,4590,4644,4657`, `items()` is a public method call, not a field access. The two direct projection cases are nevertheless findings 2 and 3 above because more specifically named production methods exist.

Fields of production-returned value records such as `entry.key`, `entry.value`, and `entry.range` are public result data and are not collection internals.

### Assertion-side runner-local traversal

The previously identified functional loops are fixed. The dispatch at `src/validate.zig:410-541` calls compatible production APIs, whose definitions are:

- ArrayList: `select/reject/detect/anySatisfy/allSatisfy/noneSatisfy/count` at `src/arraylist/array_list.zig:185-237`, and `injectInto` at line 395.
- ArrayStack: the same operations at `src/stack/array_stack.zig:171-213`.
- HashSet: the predicate operations at `src/hashset/hash_set.zig:184-254`.
- HashBag: existing operations at `src/bag/hash_bag.zig:263-309` and new `count` at line 315.
- TreeSet: `selectWhere/reject/detect/anySatisfy/allSatisfy/noneSatisfy/count` at `src/treeset/tree_set.zig:314-366`.

The assertion branches at `src/validate.zig:1174-1273` now use those helpers/methods. `product` and `inject_into_wrapping_product` correctly use production `injectInto`; there is no separate production `product` method.

The only remaining assertion loop over a production snapshot that computes, rather than merely renders, an answer is BoundedLruMap `get_N` at `src/validate.zig:4209-4221`. Its reason is valid: all existing production getters (`get`, `getOrDefault`, `getAt`, `getOrDefaultAt`, at `src/bounded_lru/bounded_lru.zig:318-361`) refresh recency on a hit, while assertion evaluation must not alter later LRU-order assertions. `entries()` is public and read-only, so this does not expose internals. Nevertheless, under the strict production-method rule it remains an unavoidable API gap. I would add:

```zig
pub fn peek(self: *const Self, key: K) ?V
```

with no recency refresh and no TTL enforcement (the non-mutating analogue of `get`), then route `get_N` through it. If TTL-aware non-mutating lookup is needed later, add `peekAt(key, now)` separately.

`to_sorted_array`, unordered `sorted_keys`, and unordered `sorted_values` are acceptable harness-side canonicalization. No production method with those exact non-mutating sorted-snapshot semantics exists for the relevant hash/stack types. `getItemSlice()` is now used only by `to_sorted_array` (`src/validate.zig:1165-1168`), and sorting the returned copy cannot mutate the subject. Output loops which merely serialize a production-returned slice are also acceptable.

One operation-side analogue is worth recording: Roaring `add_range`/`remove_range` is expanded into calls to scalar `add`/`remove` at `src/validate.zig:2183-2189` because `src/roaring.zig` has no bulk range API. It is not an assertion-value violation, and it does use production scalar operations, but full operation-level conformance would require production `addRange(from, to)` and `removeRange(from, to)` methods.

## HashBag `count`

Counting occurrences is the correct bag contract. It matches `HashBag.len()`/`totalSize()`, preserves the previous runner behavior through duplicate-expanding `toSlice()`, and matches Java's primitive HashBag implementation, whose `count(predicate)` adds each matching distinct key's occurrence count. Rust/TypeScript bag iteration likewise repeats elements by occurrence. Counting distinct matching keys would be inconsistent with those semantics.

The unit test at `src/containers_test.zig:383-406` directly distinguishes occurrence count from distinct count and covers matching, absent, all-true, and all-false predicates. It is adequate.

## `detect` order

There is no order change with the current implementations:

- ArrayList and ArrayStack: both the old slice and `detect` traverse backing order.
- HashSet: `toSlice` and `detect` both scan occupied backing-table slots in increasing index order (`src/hashset/hash_set.zig:210-217,329-337`).
- HashBag: `toSlice` and `detect` both scan the count table in increasing slot order (`src/bag/hash_bag.zig:287-293,328-337`); repeated copies cannot change the first matching distinct value.
- TreeSet: both `toSlice` and `detect` use in-order traversal (`src/treeset/tree_set.zig:270-277,334-340`).

There is still a cross-port design risk if a future scenario asks `detect` of an unordered collection and more than one element matches: different table layouts may validly select different elements. Such scenarios should ensure at most one match or explicitly define an order-independent expected set. The runner should not override production order to hide that issue.

## Ownership and allocation

The new helper ownership pattern is sound. For ArrayList/ArrayStack, `allocator.dupe` completes before the temporary result is deinitialized. For HashSet/HashBag/TreeSet, `toSlice(allocator)` returns independent caller-owned storage before the temporary collection is deinitialized. Error returns also run the `defer`, and each caller frees the returned slice exactly once. I found no introduced leak, double-free, or use-after-free.

There is a pre-existing OOM leak in production `HashSet.toSlice` at `src/hashset/hash_set.zig:329-337`: its local `ArrayListUnmanaged` has no `errdefer buf.deinit(allocator)`, so a failed append (or failed `toOwnedSlice`) can leak prior scratch allocation. The new helpers rely on that method, but did not create the bug; the old `getItemSlice` HashSet path relied on it too. It should be fixed and given the same failing-allocator coverage already present for `HashBag.toSlice`.

## Verification

I independently ran:

- `zig build test` — pass
- `zig fmt --check src/` — pass
- `validate.sh --skip-java --skip-rust --skip-ts --skip-go` — 306/306 pass; Zig runner-symbol guard 26/26

These results confirm behavior but do not cover the strict-method bypasses above, because those bypasses currently produce the same values as the production methods.

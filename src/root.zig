// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

pub const hash_table = @import("hash_table.zig");
pub const hash = @import("hash.zig");
pub const float_order = @import("float_order.zig");
pub const object = @import("object/object.zig");

pub const api = @import("api/api.zig");
pub const arraylist = @import("arraylist/arraylist.zig");
pub const bag = @import("bag/bag.zig");
pub const bitset = @import("bitset/bitset.zig");
pub const deque = @import("deque/deque.zig");
pub const hashmap = @import("hashmap/hashmap.zig");
pub const hashset = @import("hashset/hashset.zig");
pub const immutable = @import("immutable/immutable.zig");
pub const immutable_sorted = @import("immutable_sorted/immutable_sorted.zig");
pub const interval = @import("interval/interval.zig");
pub const multimap = @import("multimap/multimap.zig");
pub const parallel = @import("parallel/parallel.zig");
pub const priority_queue = @import("priority_queue/priority_queue.zig");
pub const range = @import("range.zig");
pub const range_set = @import("range_set.zig");
pub const range_map = @import("range_map.zig");
pub const stack = @import("stack/stack.zig");
pub const treemap = @import("treemap/treemap.zig");
pub const treeset = @import("treeset/treeset.zig");
pub const tuple = @import("tuple/tuple.zig");

pub const I32ArrayList = @import("arraylist/arraylist.zig").I32ArrayList;
pub const I32HashSet = @import("hashset/hashset.zig").I32HashSet;
pub const I32HashBag = @import("bag/bag.zig").I32HashBag;
pub const I32ArrayStack = @import("stack/stack.zig").I32ArrayStack;
pub const I32I64HashMap = @import("hashmap/hashmap.zig").I32I64HashMap;
pub const I32TreeSet = @import("treeset/treeset.zig").I32TreeSet;
pub const I32I64TreeMap = @import("treemap/treemap.zig").I32I64TreeMap;
pub const I32I64Pair = @import("tuple/tuple.zig").I32I64Pair;
pub const I32Interval = @import("interval/interval.zig").I32Interval;
pub const Range = @import("range.zig").Range;
pub const BoundType = @import("range.zig").BoundType;
pub const I32Range = @import("range.zig").I32Range;
pub const RangeSet = @import("range_set.zig").RangeSet;
pub const I32RangeSet = @import("range_set.zig").I32RangeSet;
pub const RangeMap = @import("range_map.zig").RangeMap;
pub const I32I32RangeMap = @import("range_map.zig").I32I32RangeMap;
pub const ImmutableI32ArrayList = @import("immutable/immutable.zig").ImmutableI32ArrayList;
pub const ImmutableI32HashSet = @import("immutable/immutable.zig").ImmutableI32HashSet;
pub const ImmutableI32HashBag = @import("immutable/immutable.zig").ImmutableI32HashBag;
pub const ImmutableI32ArrayStack = @import("immutable/immutable.zig").ImmutableI32ArrayStack;
pub const ImmutableSortedMap = @import("immutable_sorted/immutable_sorted.zig").ImmutableSortedMap;
pub const ImmutableSortedSet = @import("immutable_sorted/immutable_sorted.zig").ImmutableSortedSet;
pub const ImmutableI32I32SortedMap = @import("immutable_sorted/immutable_sorted.zig").ImmutableI32I32SortedMap;
pub const ImmutableI32SortedSet = @import("immutable_sorted/immutable_sorted.zig").ImmutableI32SortedSet;

comptime {
    _ = @import("hash.zig");
    _ = @import("float_order.zig");
    _ = @import("regression_phase3_test.zig");
    _ = @import("object/object.zig");
    _ = @import("object/treemap.zig");
    _ = @import("object/treeset.zig");
    _ = @import("api/api.zig");
    _ = @import("arraylist/arraylist.zig");
    _ = @import("arraylist/array_list.zig");
    _ = @import("bag/bag.zig");
    _ = @import("bag/hash_bag.zig");
    _ = @import("bag/tree_bag.zig");
    _ = @import("bitset/bitset.zig");
    _ = @import("containers_test.zig");
    _ = @import("iterator_test.zig");
    _ = @import("mut_iterator_test.zig");
    _ = @import("deque/deque.zig");
    _ = @import("deque/array_deque.zig");
    _ = @import("hashmap/hashmap.zig");
    _ = @import("hashmap/hash_map_test.zig");
    _ = @import("hashset/hashset.zig");
    _ = @import("hashset/hash_set.zig");
    _ = @import("immutable/immutable.zig");
    _ = @import("immutable/immutable_test.zig");
    _ = @import("immutable_sorted/immutable_sorted.zig");
    _ = @import("immutable_sorted/immutable_sorted_test.zig");
    _ = @import("interval/interval.zig");
    _ = @import("interval/interval_test.zig");
    _ = @import("multimap/multimap.zig");
    _ = @import("multimap/multimap_test.zig");
    _ = @import("parallel/parallel.zig");
    _ = @import("priority_queue/priority_queue.zig");
    _ = @import("range.zig");
    _ = @import("range_set.zig");
    _ = @import("range_map.zig");
    _ = @import("stack/stack.zig");
    _ = @import("stack/array_stack.zig");
    _ = @import("treemap/treemap.zig");
    _ = @import("treemap/tree_map_test.zig");
    _ = @import("treeset/treeset.zig");
    _ = @import("treeset/tree_set.zig");
    _ = @import("tuple/tuple.zig");
    _ = @import("tuple/pair_test.zig");
}

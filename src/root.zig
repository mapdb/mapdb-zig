// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


pub const allocator_config = @import("allocator_config.zig");
pub const hash_table = @import("hash_table.zig");
pub const object = @import("object/object.zig");

pub const api = @import("api/api.zig");
pub const arraylist = @import("arraylist/arraylist.zig");
pub const bag = @import("bag/bag.zig");
pub const bitset = @import("bitset/bitset.zig");
pub const deque = @import("deque/deque.zig");
pub const hashmap = @import("hashmap/hashmap.zig");
pub const hashset = @import("hashset/hashset.zig");
pub const immutable = @import("immutable/immutable.zig");
pub const interval = @import("interval/interval.zig");
pub const multimap = @import("multimap/multimap.zig");
pub const parallel = @import("parallel/parallel.zig");
pub const priority_queue = @import("priority_queue/priority_queue.zig");
pub const stack = @import("stack/stack.zig");
pub const treemap = @import("treemap/treemap.zig");
pub const treeset = @import("treeset/treeset.zig");
pub const tuple = @import("tuple/tuple.zig");

pub const I32ArrayList = @import("arraylist/i32_array_list.zig").I32ArrayList;
pub const I32HashSet = @import("hashset/i32_hash_set.zig").I32HashSet;
pub const I32HashBag = @import("bag/i32_hash_bag.zig").I32HashBag;
pub const I32ArrayStack = @import("stack/i32_array_stack.zig").I32ArrayStack;
pub const I32I64HashMap = @import("hashmap/i32_i64_hash_map.zig").I32I64HashMap;
pub const I32TreeSet = @import("treeset/i32_tree_set.zig").I32TreeSet;
pub const I32I64TreeMap = @import("treemap/i32_i64_tree_map.zig").I32I64TreeMap;
pub const I32I64Pair = @import("tuple/i32_i64_pair.zig").I32I64Pair;
pub const I32Interval = @import("interval/i32_interval.zig").I32Interval;
pub const ImmutableI32ArrayList = @import("immutable/immutable_i32_array_list.zig").ImmutableI32ArrayList;
pub const ImmutableI32HashSet = @import("immutable/immutable_i32_hash_set.zig").ImmutableI32HashSet;
pub const ImmutableI32HashBag = @import("immutable/immutable_i32_hash_bag.zig").ImmutableI32HashBag;
pub const ImmutableI32ArrayStack = @import("immutable/immutable_i32_array_stack.zig").ImmutableI32ArrayStack;

comptime {
    _ = @import("object/object.zig");
    _ = @import("api/api.zig");
    _ = @import("arraylist/arraylist.zig");
    _ = @import("bag/bag.zig");
    _ = @import("bitset/bitset.zig");
    _ = @import("deque/deque.zig");
    _ = @import("hashmap/hashmap.zig");
    _ = @import("hashset/hashset.zig");
    _ = @import("immutable/immutable.zig");
    _ = @import("interval/interval.zig");
    _ = @import("multimap/multimap.zig");
    _ = @import("parallel/parallel.zig");
    _ = @import("priority_queue/priority_queue.zig");
    _ = @import("stack/stack.zig");
    _ = @import("treemap/treemap.zig");
    _ = @import("treeset/treeset.zig");
    _ = @import("tuple/tuple.zig");
}

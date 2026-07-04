// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! mapdb collections — ergonomic Eclipse-Collections-style primitive and object
//! collections for Zig (a port of the MapDB/Eclipse Collections API surface).
//!
//! ## Ownership (shallow containers, move-out removal)
//!
//! Collections store keys/values **by value and never inspect them**. The
//! collection owns only its backing storage (freed by `deinit`); any memory the
//! stored bits reference is the caller's for the whole lifecycle. `get` returns
//! a shallow copy (a read — never free it); `remove` and `put`-returning-an-old
//! -value are ownership transfers (the caller disposes of what comes back);
//! `clear`/`deinit` free structure only, so drain owning values first. Object
//! collections add `getPtr`/`getConstPtr` borrowed accessors. Full contract:
//! `src/object/object.zig` module doc and
//! `todo/fable-zig/fable-review-01-ownership-model.md`.
//!
//! ## Concurrency contract
//!
//! 1. **All collections are single-threaded.** Any concurrent use — including
//!    one writer with any reader, and including borrowed slices/iterators
//!    obtained before another thread mutates — is undefined behavior.
//!    Read-only sharing of a collection that no thread mutates is allowed
//!    (exception: `BoundedLruMap.get` mutates recency, so it is a writer).
//! 2. `Synchronized(C)` wraps any collection in an `RwLock` guard for coarse
//!    locking; borrowed views obtained through a guard are valid only until the
//!    guard is released.
//! 3. `ShardedHashMap(K, V)` is a genuinely concurrent map (per-shard RwLock).
//!    It never returns interior pointers; callback accessors run under a shard
//!    lock and must not reenter the map; iteration is weakly consistent;
//!    `deinit` requires external quiescence.
//! 4. Any allocator given to a concurrent collection must be thread-safe.
//!    (`parallel.filter` is the exception — its workers never allocate.)
//!
//! See `todo/fable-zig/fable-review-02-concurrent-map-memory.md`.

pub const hash_table = @import("hash_table.zig");
pub const hash = @import("hash.zig");
pub const bloom = @import("bloom.zig");
pub const Bloom = @import("bloom.zig").Bloom;
pub const count_min = @import("count_min.zig");
pub const space_saving = @import("space_saving.zig");
pub const float_order = @import("float_order.zig");
pub const object = @import("object/object.zig");

// Data pump (bulk import) shared vocabulary. The per-collection pump methods
// (`fromSorted` / `bulkLoad` / `Sink`) live on the comptime-generic structs and
// ride the existing aliases; only these shared enums/errors are re-exported.
pub const pump = @import("pump.zig");
pub const DupPolicy = pump.DupPolicy;
pub const PumpError = pump.PumpError;

pub const api = @import("api/api.zig");
pub const arraylist = @import("arraylist/arraylist.zig");
pub const bag = @import("bag/bag.zig");
pub const bitset = @import("bitset/bitset.zig");
pub const bounded_lru = @import("bounded_lru/bounded_lru.zig");
pub const deque = @import("deque/deque.zig");
pub const hashmap = @import("hashmap/hashmap.zig");
pub const hashset = @import("hashset/hashset.zig");
pub const hyperloglog = @import("hyperloglog/hyperloglog.zig");
pub const immutable = @import("immutable/immutable.zig");
pub const immutable_sorted = @import("immutable_sorted/immutable_sorted.zig");
pub const interval = @import("interval/interval.zig");
pub const multimap = @import("multimap/multimap.zig");
pub const parallel = @import("parallel/parallel.zig");
pub const priority_queue = @import("priority_queue/priority_queue.zig");
pub const range = @import("range.zig");
pub const fenwick = @import("fenwick.zig");
pub const range_set = @import("range_set.zig");
pub const range_map = @import("range_map.zig");
pub const roaring = @import("roaring.zig");
pub const stack = @import("stack/stack.zig");
pub const treemap = @import("treemap/treemap.zig");
pub const treeset = @import("treeset/treeset.zig");
pub const tuple = @import("tuple/tuple.zig");

// Concurrency tiers (see the //! contract above and doc 02).
pub const concurrent = @import("concurrent/concurrent.zig");
pub const Synchronized = concurrent.Synchronized;
pub const ShardedHashMap = concurrent.ShardedHashMap;

pub const I32ArrayList = @import("arraylist/arraylist.zig").I32ArrayList;
pub const I32HashSet = @import("hashset/hashset.zig").I32HashSet;
pub const I32HashBag = @import("bag/bag.zig").I32HashBag;
pub const I32ArrayStack = @import("stack/stack.zig").I32ArrayStack;
pub const I32I64HashMap = @import("hashmap/hashmap.zig").I32I64HashMap;
pub const I32TreeSet = @import("treeset/treeset.zig").I32TreeSet;
pub const I32I64TreeMap = @import("treemap/treemap.zig").I32I64TreeMap;
pub const I32I64Pair = @import("tuple/tuple.zig").I32I64Pair;
pub const I32Interval = @import("interval/interval.zig").I32Interval;
pub const BoundedLruMap = @import("bounded_lru/bounded_lru.zig").BoundedLruMap;
pub const I32I32BoundedLruMap = @import("bounded_lru/bounded_lru.zig").I32I32BoundedLruMap;
pub const EvictionCause = @import("bounded_lru/bounded_lru.zig").EvictionCause;
pub const CountMin = @import("count_min.zig").CountMin;
pub const SpaceSaving = @import("space_saving.zig").SpaceSaving;
pub const Range = @import("range.zig").Range;
pub const BoundType = @import("range.zig").BoundType;
pub const I32Range = @import("range.zig").I32Range;
pub const FenwickTree = @import("fenwick.zig").FenwickTree;
pub const RangeSet = @import("range_set.zig").RangeSet;
pub const I32RangeSet = @import("range_set.zig").I32RangeSet;
pub const RangeMap = @import("range_map.zig").RangeMap;
pub const I32I32RangeMap = @import("range_map.zig").I32I32RangeMap;
pub const RoaringU32 = @import("roaring.zig").RoaringU32;
pub const ImmutableI32ArrayList = @import("immutable/immutable.zig").ImmutableI32ArrayList;
pub const ImmutableI32HashSet = @import("immutable/immutable.zig").ImmutableI32HashSet;
pub const ImmutableI32HashBag = @import("immutable/immutable.zig").ImmutableI32HashBag;
pub const ImmutableI32ArrayStack = @import("immutable/immutable.zig").ImmutableI32ArrayStack;
pub const ImmutableSortedMap = @import("immutable_sorted/immutable_sorted.zig").ImmutableSortedMap;
pub const ImmutableSortedSet = @import("immutable_sorted/immutable_sorted.zig").ImmutableSortedSet;
pub const ImmutableI32I32SortedMap = @import("immutable_sorted/immutable_sorted.zig").ImmutableI32I32SortedMap;
pub const ImmutableI32SortedSet = @import("immutable_sorted/immutable_sorted.zig").ImmutableI32SortedSet;
pub const HyperLogLog = @import("hyperloglog/hyperloglog.zig").HyperLogLog;

comptime {
    _ = @import("hyperloglog/hyperloglog.zig");
    _ = @import("hash.zig");
    _ = @import("bloom.zig");
    _ = @import("count_min.zig");
    _ = @import("space_saving.zig");
    _ = @import("float_order.zig");
    _ = @import("pump.zig");
    _ = @import("pump_test.zig");
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
    _ = @import("bounded_lru/bounded_lru.zig");
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
    _ = @import("fenwick.zig");
    _ = @import("range_set.zig");
    _ = @import("range_map.zig");
    _ = @import("roaring.zig");
    _ = @import("stack/stack.zig");
    _ = @import("stack/array_stack.zig");
    _ = @import("treemap/treemap.zig");
    _ = @import("treemap/tree_map_test.zig");
    _ = @import("treeset/treeset.zig");
    _ = @import("treeset/tree_set.zig");
    _ = @import("tuple/tuple.zig");
    _ = @import("tuple/pair_test.zig");
}

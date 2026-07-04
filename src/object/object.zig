// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Object collection module index — generic (comptime) collections for
//! arbitrary key/value types.
//!
//! ## Ownership model (shallow containers, move-out removal)
//!
//! These collections store keys and values **by value and never inspect
//! them**. If those bits reference memory (a slice, pointer, or owning
//! struct), that memory is the caller's responsibility for the whole
//! lifecycle. The library's own storage (tables, nodes) is what `deinit`
//! frees — never the payloads. Concretely:
//!
//! * `get(key) -> ?V` is a **read**: it returns a shallow copy of bits the map
//!   still holds. Do NOT free what `get` returns — the entry is still in the
//!   map, so freeing it double-frees on the next `remove`/`deinit`.
//! * `getPtr`/`getConstPtr` return a **borrowed** pointer to the map-owned
//!   value for in-place mutation. Invalidated by any structural mutation
//!   (put/remove/clear/deinit, and rehash for hash maps). Never free it.
//! * `put` returning an old value, and `remove`, are ownership **transfers**
//!   (move-out): the returned value has left the map and the caller must
//!   dispose of it if it owns memory. `_ = try map.put(k, v)` with an owning V
//!   **leaks** the replaced value — inspect the return.
//! * `clear`/`deinit`/range-removal free structure only. For an owning V the
//!   caller must drain (iterate + free) first, or use a `…With(dropFn)`
//!   overload where one is provided.
//!
//! This mirrors `std.HashMapUnmanaged` (shallow) and the primitive tier, so
//! Zig users arrive with the right mental model. See
//! `todo/fable-zig/fable-review-01-ownership-model.md`.

pub const ArrayList = @import("arraylist.zig").ArrayList;
pub const HashSet = @import("hashset.zig").HashSet;
pub const HashMap = @import("hashmap.zig").HashMap;
pub const HashBag = @import("hashbag.zig").HashBag;
pub const ArrayStack = @import("arraystack.zig").ArrayStack;
pub const HashBiMap = @import("hashbimap.zig").HashBiMap;
pub const LinkedHashMap = @import("linkedhashmap.zig").LinkedHashMap;
pub const LinkedHashSet = @import("linkedhashset.zig").LinkedHashSet;

pub const HashingStrategy = @import("strategy.zig").HashingStrategy;
pub const Comparator = @import("strategy.zig").Comparator;
pub const naturalComparator = @import("strategy.zig").naturalComparator;
pub const reverseComparator = @import("strategy.zig").reverseComparator;
pub const reversed = @import("strategy.zig").reversed;
pub const comparatorByField = @import("strategy.zig").comparatorByField;
pub const thenComparing = @import("strategy.zig").thenComparing;
pub const TreeMap = @import("treemap.zig").TreeMap;
pub const TreeSet = @import("treeset.zig").TreeSet;
pub const HashSetWithStrategy = @import("strategy_hashset.zig").HashSetWithStrategy;
pub const HashMapWithStrategy = @import("strategy_hashmap.zig").HashMapWithStrategy;

// Runnable examples (tests only; no public re-exports).
comptime {
    _ = @import("strategy_examples.zig");
    _ = @import("ownership_test.zig");
}

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}

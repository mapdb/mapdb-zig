// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Object collection module index — generic (comptime) collections for arbitrary types.

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
}

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}

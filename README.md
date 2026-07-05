# mapdb-collections (Zig)

High-performance primitive-specialized and generic collections for Zig, inspired by [Eclipse Collections](https://eclipse.dev/collections/).

## Why?

Zig's standard library provides `std.ArrayList` and `std.AutoHashMap` — solid building blocks, but without the rich functional iteration API that Eclipse Collections is known for. This library provides:

- **Primitive-specialized types** (`I32ArrayList`, `I32HashSet`, `I32I64HashMap`, etc.) with direct value storage and no allocator overhead for hash tables (open addressing)
- **Generic comptime collections** (`ArrayList(T)`, `HashSet(T)`, `HashMap(K,V)`, etc.) with the full Eclipse Collections API
- Rich functional methods: `select`, `reject`, `detect`, `anySatisfy`, `allSatisfy`, `injectInto`, `collectInt`, and more

## Primitive Collections

| Type | Mutable | Immutable | Variants |
|------|---------|-----------|----------|
| **ArrayList** | `I32ArrayList` | `ImmutableI32ArrayList` | 8 types |
| **HashSet** | `I32HashSet` | `ImmutableI32HashSet` | 8 types |
| **HashBag** | `I32HashBag` | `ImmutableI32HashBag` | 8 types |
| **ArrayStack** | `I32ArrayStack` | `ImmutableI32ArrayStack` | 8 types |
| **HashMap** | `I32I64HashMap` | `ImmutableI32I64HashMap` | 64 pairs (8x8) |
| **TreeSet** | `I32TreeSet` | — | 8 types |
| **TreeMap** | `I32I64TreeMap` | — | 64 pairs |
| **Pair** | `I32I64Pair` | — | 64 pairs |
| **Interval** | `I32Interval` | — | range type |

## Object Collections

Generic comptime collections using `pub fn Type(comptime T: type) type`:

| Type | Description |
|------|-------------|
| `ArrayList(T)` | Ordered list backed by `ArrayListUnmanaged(T)` |
| `HashSet(T)` | Unordered set backed by `AutoHashMapUnmanaged(T, void)` |
| `HashMap(K, V)` | Key-value map backed by `AutoHashMapUnmanaged(K, V)` |
| `HashBag(T)` | Counting bag backed by `AutoHashMapUnmanaged(T, usize)` |
| `ArrayStack(T)` | LIFO stack backed by `ArrayListUnmanaged(T)` |
| `HashBiMap(K, V)` | Bidirectional map with unique keys and values |

## Memory management

Every collection is **managed by default**: it stores the allocator you pass to
`init` and uses it for its own growth and teardown, so the common path threads
no allocator through method calls — batteries-included, Eclipse-Collections-style
ergonomics. Each type wraps an unmanaged stdlib core (`ArrayListUnmanaged`,
`AutoHashMapUnmanaged`, treaps).

The library does **not** force a single allocator model — both the managed
(stored-allocator) and explicit-allocator styles are supported, and neither is
removed. Where a method returns **raw owned memory** you pick the allocator
explicitly, so the result can live in a different arena than the collection:
**a method that takes an allocator returns raw owned memory you free with that
allocator; a method that takes none returns no raw memory you must free.** So
slice/raw materializers (`toSlice(allocator)`, `rangeKeysIn(range, allocator)`)
take an explicit allocator; mutators and count-returning ops (`put`, `remove`,
`removeRange`) use the stored one. Borrowed views (`slice`, `…Slice`, `items`)
allocate nothing.

Functional methods that return a **fresh collection** (`select`, `reject`,
`setUnion`, `reversed`, `toImmutable`/`toMutable`) are managed: the result is
backed by the source's stored allocator and freed by its own `deinit`. An
explicit-allocator tier for the flagship types can be added on demand without
disturbing this default.

## Quick Start

```zig
const std = @import("std");
const mapdb = @import("mapdb_collections");

// Primitive ArrayList
var list = mapdb.I32ArrayList.init(allocator);
defer list.deinit();
list.push(3);
list.push(1);
list.push(4);
list.sort();
const big = list.select(struct {
    pub fn call(v: i32) bool { return v > 2; }
}.call);
defer big.deinit();

// Generic ArrayList
const ObjList = mapdb.object.ArrayList([]const u8);
var names = ObjList.init(allocator);
defer names.deinit();
names.push("Alice");
names.push("Bob");
names.push("Charlie");
const found = names.detect(struct {
    pub fn call(s: []const u8) bool { return s[0] == 'B'; }
}.call);
// found == "Bob"
```

## Stats

- **568 source files**, **4,443 tests** passing
- All 8 Zig primitive types + generic comptime types
- Zero external dependencies
- Requires Zig 0.15.0+

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

Every collection is **managed**: it stores the allocator you pass to `init` and
uses it for all its own growth and teardown, so you don't thread an allocator
through method calls. This is a deliberate design choice — batteries-included,
Eclipse-Collections-style ergonomics — even though each type's internals are
unmanaged stdlib containers (`ArrayListUnmanaged`, `AutoHashMapUnmanaged`,
treaps) and the broader ecosystem is unmanaged-first. There is no speculative
parallel `Unmanaged` tier; the managed wrappers are the supported surface.

One rule says where an `Allocator` reappears in a signature: **a method that
takes an allocator returns owned memory (you free it with that allocator); a
method that takes none never returns anything you may free.** Materializers that
hand back a fresh slice/collection (`toSlice(allocator)`, `rangeKeysIn(range,
allocator)`) take an explicit allocator; mutators and count-returning ops
(`put`, `remove`, `removeRange`) use the stored one. Borrowed views (`slice`,
`…Slice`, `items`) allocate nothing.

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

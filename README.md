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

## Quick Start

```zig
const std = @import("std");
const mapdb = @import("mapdb_collections");

// Primitive ArrayList
var list = mapdb.I32ArrayList.init();
defer list.deinit(allocator);
list.append(allocator, 3);
list.append(allocator, 1);
list.append(allocator, 4);
list.sort();
const big = list.select(allocator, struct {
    pub fn call(v: i32) bool { return v > 2; }
}.call);

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

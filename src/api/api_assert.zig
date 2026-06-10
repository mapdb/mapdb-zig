// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Compile-time interface assertions + conformance coverage for the primitive
//! collection / map families.
//!
//! This single file replaces the 72 per-(K,V) / per-type `<k>_<v>_map.zig` and
//! `<t>_collection.zig` files. Those files were uniform: the `@hasDecl`
//! method-name checks for a map (len/isEmpty/containsKey/get + put/remove/clear)
//! and for a collection / list / set / bag / stack are IDENTICAL regardless of
//! the element types — only the *conformance block* (which concrete production
//! types are checked) varied, and that variation is purely mechanical over the
//! type axis.
//!
//! So the assertions are exposed as generic, type-erased functions
//! (`assertMap`, `assertMutableMap`, `assertCollection`, …), and the
//! conformance coverage is preserved by the `comptime` blocks at the bottom,
//! which iterate the named aliases of every collapsed family aggregator and
//! assert that every concrete production map type and collection type satisfies
//! its matching interface. This is a SUPERSET of what the 72 deleted files
//! verified — losing a conformance check here is the failure mode this file
//! exists to prevent.

const std = @import("std");

// ───────────────────────── Map interfaces ─────────────────────────

/// Comptime interface for a read-only primitive map (any key/value type).
///
/// Equivalent to the Go `<K><V>MapIterable` interface / Rust `<K><V>Map` trait
/// / Java `<K><V>Map` interface.
pub fn assertMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for a mutable primitive map. Extends `assertMap`.
pub fn assertMutableMap(comptime T: type) void {
    assertMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// ───────────────────── Collection interfaces ─────────────────────

/// Comptime interface for a read-only primitive collection (any element type).
pub fn assertCollection(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "contains")) @compileError(@typeName(T) ++ " missing contains()");
    }
}

/// Comptime interface for a mutable primitive collection. Extends
/// `assertCollection` with `clear` + `deinit`.
pub fn assertMutableCollection(comptime T: type) void {
    assertCollection(T);
    comptime {
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
        if (!@hasDecl(T, "deinit")) @compileError(@typeName(T) ++ " missing deinit()");
    }
}

// ── Category interfaces — mirror Java's IntList / IntSet / IntBag / IntStack ──

/// Read-only ordered list with positional access. `get(index)` returns `?V`.
pub fn assertList(comptime T: type) void {
    assertCollection(T);
    comptime {
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Mutable ordered list. Adds `add` (append) and `set` (positional replace).
pub fn assertMutableList(comptime T: type) void {
    assertList(T);
    assertMutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
        if (!@hasDecl(T, "set")) @compileError(@typeName(T) ++ " missing set()");
    }
}

/// Read-only set marker — uniqueness implied; no extra methods of its own.
pub fn assertSet(comptime T: type) void {
    assertCollection(T);
}

/// Mutable set. `add(value) bool` returns true if the value was newly inserted.
pub fn assertMutableSet(comptime T: type) void {
    assertSet(T);
    assertMutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only multiset (bag) with occurrence counts.
pub fn assertBag(comptime T: type) void {
    assertCollection(T);
    comptime {
        if (!@hasDecl(T, "occurrencesOf")) @compileError(@typeName(T) ++ " missing occurrencesOf()");
        if (!@hasDecl(T, "sizeDistinct")) @compileError(@typeName(T) ++ " missing sizeDistinct()");
    }
}

/// Mutable bag. `add(value)` adds one occurrence.
pub fn assertMutableBag(comptime T: type) void {
    assertBag(T);
    assertMutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only LIFO stack. `peek()` returns the top element.
pub fn assertStack(comptime T: type) void {
    assertCollection(T);
    comptime {
        if (!@hasDecl(T, "peek")) @compileError(@typeName(T) ++ " missing peek()");
    }
}

/// Mutable LIFO stack. Adds `push` and `pop`.
pub fn assertMutableStack(comptime T: type) void {
    assertStack(T);
    assertMutableCollection(T);
    comptime {
        if (!@hasDecl(T, "push")) @compileError(@typeName(T) ++ " missing push()");
        if (!@hasDecl(T, "pop")) @compileError(@typeName(T) ++ " missing pop()");
    }
}

// ───────────────────── Conformance coverage ─────────────────────
//
// The whole point of the api/ layer: if any concrete production type drifts
// away from its interface, these blocks fail to compile. They reference the
// CamelCase named aliases of the collapsed family aggregators (the same
// aliases the cross-language validate harness consumes), so they automatically
// track whatever those aggregators export.

// Element-type axis. The CamelCase prefix is how every aggregator names its
// aliases; the lowercase token is how the per-file namespaces (and the
// interval aggregator) name theirs. Interval exists for integer types only.
const Elem = struct { camel: []const u8, lower: []const u8, integer: bool };

const elems = [_]Elem{
    .{ .camel = "Bool", .lower = "bool", .integer = false },
    .{ .camel = "Char", .lower = "char", .integer = false },
    .{ .camel = "F32", .lower = "f32", .integer = false },
    .{ .camel = "F64", .lower = "f64", .integer = false },
    .{ .camel = "I8", .lower = "i8", .integer = true },
    .{ .camel = "I16", .lower = "i16", .integer = true },
    .{ .camel = "I32", .lower = "i32", .integer = true },
    .{ .camel = "I64", .lower = "i64", .integer = true },
};

// ── Map conformance: every (K, V) concrete map type satisfies its interface ──
//
// Covers, for every K×V pair (64 combinations):
//   * HashMap     — MutableMap
//   * TreeMap     — MutableMap
//   * HashBiMap   — MutableMap
//   * ImmutableHashMap — Map (read-only)
// This reproduces exactly the per-file `<k>_<v>_map.zig` conformance blocks.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    for (elems) |k| {
        for (elems) |v| {
            const kv = k.camel ++ v.camel;
            assertMutableMap(@field(hashmap, kv ++ "HashMap"));
            assertMutableMap(@field(treemap, kv ++ "TreeMap"));
            assertMutableMap(@field(hashmap, kv ++ "HashBiMap"));
            assertMap(@field(immutable, "Immutable" ++ kv ++ "HashMap"));
        }
    }
}

// ── Collection conformance: every element-typed collection satisfies it ──
//
// Covers, for every element type (8 types):
//   * ArrayList   — MutableCollection + MutableList
//   * HashSet     — MutableCollection + MutableSet
//   * TreeSet     — MutableCollection + MutableSet
//   * HashBag     — MutableCollection + MutableBag
//   * TreeBag     — MutableCollection + MutableBag
//   * ArrayStack  — MutableCollection + MutableStack
//   * ImmutableArrayList  — Collection + List
//   * ImmutableHashSet    — Collection + Set
//   * ImmutableHashBag    — Collection + Bag
//   * ImmutableArrayStack — Collection + Stack
//   * Interval (integer element types only) — Collection
// This reproduces exactly the per-file `<t>_collection.zig` conformance blocks.
comptime {
    const arraylist = @import("../arraylist/arraylist.zig");
    const hashset = @import("../hashset/hashset.zig");
    const treeset = @import("../treeset/treeset.zig");
    const bag = @import("../bag/bag.zig");
    const stack = @import("../stack/stack.zig");
    const immutable = @import("../immutable/immutable.zig");
    const interval = @import("../interval/interval.zig");

    for (elems) |e| {
        const c = e.camel;

        // ArrayList — List + MutableList
        const ArrayList = @field(arraylist, c ++ "ArrayList");
        assertMutableCollection(ArrayList);
        assertMutableList(ArrayList);

        // HashSet / TreeSet — Set + MutableSet
        const HashSet = @field(hashset, c ++ "HashSet");
        assertMutableCollection(HashSet);
        assertMutableSet(HashSet);
        const TreeSet = @field(treeset, c ++ "TreeSet");
        assertMutableCollection(TreeSet);
        assertMutableSet(TreeSet);

        // HashBag / TreeBag — Bag + MutableBag
        const HashBag = @field(bag, c ++ "HashBag");
        assertMutableCollection(HashBag);
        assertMutableBag(HashBag);
        const TreeBag = @field(bag, c ++ "TreeBag");
        assertMutableCollection(TreeBag);
        assertMutableBag(TreeBag);

        // ArrayStack — Stack + MutableStack
        const ArrayStack = @field(stack, c ++ "ArrayStack");
        assertMutableCollection(ArrayStack);
        assertMutableStack(ArrayStack);

        // Immutable types — read-only category trait only
        const ImmutableArrayList = @field(immutable, "Immutable" ++ c ++ "ArrayList");
        assertCollection(ImmutableArrayList);
        assertList(ImmutableArrayList);
        const ImmutableHashSet = @field(immutable, "Immutable" ++ c ++ "HashSet");
        assertCollection(ImmutableHashSet);
        assertSet(ImmutableHashSet);
        const ImmutableHashBag = @field(immutable, "Immutable" ++ c ++ "HashBag");
        assertCollection(ImmutableHashBag);
        assertBag(ImmutableHashBag);
        const ImmutableArrayStack = @field(immutable, "Immutable" ++ c ++ "ArrayStack");
        assertCollection(ImmutableArrayStack);
        assertStack(ImmutableArrayStack);

        // Interval — read-only Collection (integer element types only).
        if (e.integer) {
            const ns = @field(interval, e.lower ++ "_interval");
            const Interval = @field(ns, c ++ "Interval");
            assertCollection(Interval);
        }
    }
}

test "api conformance comptime blocks compile" {
    // The comptime blocks above do the real verification; referencing a generic
    // assert here keeps this file self-testing.
    const arraylist = @import("../arraylist/arraylist.zig");
    assertMutableCollection(arraylist.I32ArrayList);
}

// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only collections of `i32` values.
///
/// Any struct that has these methods can be used where an I32Collection is expected.
/// Use `assertI32Collection(T)` to verify at compile time.
///
/// Equivalent to:
///   Go:   I32Iterable interface
///   Rust: I32Collection trait
///   Java: I32Iterable interface
pub fn assertI32Collection(comptime T: type) void {
    // Required methods for read-only collection
    comptime {
        // fn len(*const T) usize
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        // fn isEmpty(*const T) bool
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        // fn contains(*const T, i32) bool
        if (!@hasDecl(T, "contains")) @compileError(@typeName(T) ++ " missing contains()");
    }
}

/// Comptime interface for mutable collections of `i32` values.
///
/// Extends I32Collection with mutation operations.
///
/// Equivalent to:
///   Go:   I32MutableCollection interface
///   Rust: I32MutableCollection trait
///   Java: MutableI32Collection interface
pub fn assertI32MutableCollection(comptime T: type) void {
    // Must satisfy read-only interface first
    assertI32Collection(T);

    comptime {
        // fn clear(*T) void
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
        // fn deinit(*T) void
        if (!@hasDecl(T, "deinit")) @compileError(@typeName(T) ++ " missing deinit()");
    }
}

// ── Category interfaces — mirror Java's IntList/IntSet/IntBag/IntStack ──

/// Read-only ordered list with positional access. `get(index)` returns ?i32.
pub fn assertI32List(comptime T: type) void {
    assertI32Collection(T);
    comptime {
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Mutable ordered list. Adds `add` (append) and `set` (positional replace).
pub fn assertI32MutableList(comptime T: type) void {
    assertI32List(T);
    assertI32MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
        if (!@hasDecl(T, "set")) @compileError(@typeName(T) ++ " missing set()");
    }
}

/// Read-only set marker — uniqueness implied; no extra methods of its own.
pub fn assertI32Set(comptime T: type) void {
    assertI32Collection(T);
}

/// Mutable set. `add(value) bool` returns true if the value was newly inserted.
pub fn assertI32MutableSet(comptime T: type) void {
    assertI32Set(T);
    assertI32MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only multiset (bag) with occurrence counts.
pub fn assertI32Bag(comptime T: type) void {
    assertI32Collection(T);
    comptime {
        if (!@hasDecl(T, "occurrencesOf")) @compileError(@typeName(T) ++ " missing occurrencesOf()");
        if (!@hasDecl(T, "sizeDistinct")) @compileError(@typeName(T) ++ " missing sizeDistinct()");
    }
}

/// Mutable bag. `add(value)` adds one occurrence.
pub fn assertI32MutableBag(comptime T: type) void {
    assertI32Bag(T);
    assertI32MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only LIFO stack. `peek()` returns the top element.
pub fn assertI32Stack(comptime T: type) void {
    assertI32Collection(T);
    comptime {
        if (!@hasDecl(T, "peek")) @compileError(@typeName(T) ++ " missing peek()");
    }
}

/// Mutable LIFO stack. Adds `push` and `pop`.
pub fn assertI32MutableStack(comptime T: type) void {
    assertI32Stack(T);
    assertI32MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "push")) @compileError(@typeName(T) ++ " missing push()");
        if (!@hasDecl(T, "pop")) @compileError(@typeName(T) ++ " missing pop()");
    }
}

// Compile-time verification that every concrete collection type for `i32`
// satisfies the matching read-only and (where applicable) mutable interface.
// If any implementation drifts this block fails to compile.
//
// Imports go through the per-package index files (arraylist.zig, hashset.zig,
// etc.) rather than directly naming implementation files. This means the
// index file is the swap point — to use a different backing implementation,
// change which file the index re-exports. Both user code and this drift
// guard pick up the change automatically.
comptime {
    const arraylist = @import("../arraylist/arraylist.zig");
    const hashset = @import("../hashset/hashset.zig");
    const treeset = @import("../treeset/treeset.zig");
    const bag = @import("../bag/bag.zig");
    const stack = @import("../stack/stack.zig");
    const immutable = @import("../immutable/immutable.zig");

    // ArrayList — List + MutableList
    const ArrayList = arraylist.i32_array_list.I32ArrayList;
    assertI32MutableCollection(ArrayList);
    assertI32MutableList(ArrayList);

    // HashSet / TreeSet — Set + MutableSet
    const HashSet = hashset.i32_hash_set.I32HashSet;
    assertI32MutableCollection(HashSet);
    assertI32MutableSet(HashSet);
    const TreeSet = treeset.i32_tree_set.I32TreeSet;
    assertI32MutableCollection(TreeSet);
    assertI32MutableSet(TreeSet);

    // HashBag / TreeBag — Bag + MutableBag
    const HashBag = bag.i32_hash_bag.I32HashBag;
    assertI32MutableCollection(HashBag);
    assertI32MutableBag(HashBag);
    const TreeBag = bag.i32_tree_bag.I32TreeBag;
    assertI32MutableCollection(TreeBag);
    assertI32MutableBag(TreeBag);

    // ArrayStack — Stack + MutableStack
    const ArrayStack = stack.i32_array_stack.I32ArrayStack;
    assertI32MutableCollection(ArrayStack);
    assertI32MutableStack(ArrayStack);

    // Immutable types — read-only category trait only
    const ImmutableArrayList = immutable.immutable_i32_array_list.ImmutableI32ArrayList;
    assertI32Collection(ImmutableArrayList);
    assertI32List(ImmutableArrayList);

    const ImmutableHashSet = immutable.immutable_i32_hash_set.ImmutableI32HashSet;
    assertI32Collection(ImmutableHashSet);
    assertI32Set(ImmutableHashSet);

    const ImmutableHashBag = immutable.immutable_i32_hash_bag.ImmutableI32HashBag;
    assertI32Collection(ImmutableHashBag);
    assertI32Bag(ImmutableHashBag);

    const ImmutableArrayStack = immutable.immutable_i32_array_stack.ImmutableI32ArrayStack;
    assertI32Collection(ImmutableArrayStack);
    assertI32Stack(ImmutableArrayStack);

    // Interval — read-only Collection (integer types only)
    const interval = @import("../interval/interval.zig");
    const Interval = interval.i32_interval.I32Interval;
    assertI32Collection(Interval);
}

test "assertI32Collection comptime check" {
    // This test passes if it compiles — the comptime block above does the real checking.
    const arraylist = @import("../arraylist/arraylist.zig");
    assertI32Collection(arraylist.i32_array_list.I32ArrayList);
}

// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only collections of `i8` values.
///
/// Any struct that has these methods can be used where an I8Collection is expected.
/// Use `assertI8Collection(T)` to verify at compile time.
///
/// Equivalent to:
///   Go:   I8Iterable interface
///   Rust: I8Collection trait
///   Java: I8Iterable interface
pub fn assertI8Collection(comptime T: type) void {
    // Required methods for read-only collection
    comptime {
        // fn len(*const T) usize
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        // fn isEmpty(*const T) bool
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        // fn contains(*const T, i8) bool
        if (!@hasDecl(T, "contains")) @compileError(@typeName(T) ++ " missing contains()");
    }
}

/// Comptime interface for mutable collections of `i8` values.
///
/// Extends I8Collection with mutation operations.
///
/// Equivalent to:
///   Go:   I8MutableCollection interface
///   Rust: I8MutableCollection trait
///   Java: MutableI8Collection interface
pub fn assertI8MutableCollection(comptime T: type) void {
    // Must satisfy read-only interface first
    assertI8Collection(T);

    comptime {
        // fn clear(*T) void
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
        // fn deinit(*T) void
        if (!@hasDecl(T, "deinit")) @compileError(@typeName(T) ++ " missing deinit()");
    }
}

// ── Category interfaces — mirror Java's IntList/IntSet/IntBag/IntStack ──

/// Read-only ordered list with positional access. `get(index)` returns ?i8.
pub fn assertI8List(comptime T: type) void {
    assertI8Collection(T);
    comptime {
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Mutable ordered list. Adds `add` (append) and `set` (positional replace).
pub fn assertI8MutableList(comptime T: type) void {
    assertI8List(T);
    assertI8MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
        if (!@hasDecl(T, "set")) @compileError(@typeName(T) ++ " missing set()");
    }
}

/// Read-only set marker — uniqueness implied; no extra methods of its own.
pub fn assertI8Set(comptime T: type) void {
    assertI8Collection(T);
}

/// Mutable set. `add(value) bool` returns true if the value was newly inserted.
pub fn assertI8MutableSet(comptime T: type) void {
    assertI8Set(T);
    assertI8MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only multiset (bag) with occurrence counts.
pub fn assertI8Bag(comptime T: type) void {
    assertI8Collection(T);
    comptime {
        if (!@hasDecl(T, "occurrencesOf")) @compileError(@typeName(T) ++ " missing occurrencesOf()");
        if (!@hasDecl(T, "sizeDistinct")) @compileError(@typeName(T) ++ " missing sizeDistinct()");
    }
}

/// Mutable bag. `add(value)` adds one occurrence.
pub fn assertI8MutableBag(comptime T: type) void {
    assertI8Bag(T);
    assertI8MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only LIFO stack. `peek()` returns the top element.
pub fn assertI8Stack(comptime T: type) void {
    assertI8Collection(T);
    comptime {
        if (!@hasDecl(T, "peek")) @compileError(@typeName(T) ++ " missing peek()");
    }
}

/// Mutable LIFO stack. Adds `push` and `pop`.
pub fn assertI8MutableStack(comptime T: type) void {
    assertI8Stack(T);
    assertI8MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "push")) @compileError(@typeName(T) ++ " missing push()");
        if (!@hasDecl(T, "pop")) @compileError(@typeName(T) ++ " missing pop()");
    }
}

// Compile-time verification that every concrete collection type for `i8`
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
    const ArrayList = arraylist.i8_array_list.I8ArrayList;
    assertI8MutableCollection(ArrayList);
    assertI8MutableList(ArrayList);

    // HashSet / TreeSet — Set + MutableSet
    const HashSet = hashset.i8_hash_set.I8HashSet;
    assertI8MutableCollection(HashSet);
    assertI8MutableSet(HashSet);
    const TreeSet = treeset.i8_tree_set.I8TreeSet;
    assertI8MutableCollection(TreeSet);
    assertI8MutableSet(TreeSet);

    // HashBag / TreeBag — Bag + MutableBag
    const HashBag = bag.i8_hash_bag.I8HashBag;
    assertI8MutableCollection(HashBag);
    assertI8MutableBag(HashBag);
    const TreeBag = bag.i8_tree_bag.I8TreeBag;
    assertI8MutableCollection(TreeBag);
    assertI8MutableBag(TreeBag);

    // ArrayStack — Stack + MutableStack
    const ArrayStack = stack.i8_array_stack.I8ArrayStack;
    assertI8MutableCollection(ArrayStack);
    assertI8MutableStack(ArrayStack);

    // Immutable types — read-only category trait only
    const ImmutableArrayList = immutable.immutable_i8_array_list.ImmutableI8ArrayList;
    assertI8Collection(ImmutableArrayList);
    assertI8List(ImmutableArrayList);

    const ImmutableHashSet = immutable.immutable_i8_hash_set.ImmutableI8HashSet;
    assertI8Collection(ImmutableHashSet);
    assertI8Set(ImmutableHashSet);

    const ImmutableHashBag = immutable.immutable_i8_hash_bag.ImmutableI8HashBag;
    assertI8Collection(ImmutableHashBag);
    assertI8Bag(ImmutableHashBag);

    const ImmutableArrayStack = immutable.immutable_i8_array_stack.ImmutableI8ArrayStack;
    assertI8Collection(ImmutableArrayStack);
    assertI8Stack(ImmutableArrayStack);

    // Interval — read-only Collection (integer types only)
    const interval = @import("../interval/interval.zig");
    const Interval = interval.i8_interval.I8Interval;
    assertI8Collection(Interval);
}

test "assertI8Collection comptime check" {
    // This test passes if it compiles — the comptime block above does the real checking.
    const arraylist = @import("../arraylist/arraylist.zig");
    assertI8Collection(arraylist.i8_array_list.I8ArrayList);
}

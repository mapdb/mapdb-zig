// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only collections of `f32` values.
///
/// Any struct that has these methods can be used where an F32Collection is expected.
/// Use `assertF32Collection(T)` to verify at compile time.
///
/// Equivalent to:
///   Go:   F32Iterable interface
///   Rust: F32Collection trait
///   Java: F32Iterable interface
pub fn assertF32Collection(comptime T: type) void {
    // Required methods for read-only collection
    comptime {
        // fn len(*const T) usize
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        // fn isEmpty(*const T) bool
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        // fn contains(*const T, f32) bool
        if (!@hasDecl(T, "contains")) @compileError(@typeName(T) ++ " missing contains()");
    }
}

/// Comptime interface for mutable collections of `f32` values.
///
/// Extends F32Collection with mutation operations.
///
/// Equivalent to:
///   Go:   F32MutableCollection interface
///   Rust: F32MutableCollection trait
///   Java: MutableF32Collection interface
pub fn assertF32MutableCollection(comptime T: type) void {
    // Must satisfy read-only interface first
    assertF32Collection(T);

    comptime {
        // fn clear(*T) void
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
        // fn deinit(*T) void
        if (!@hasDecl(T, "deinit")) @compileError(@typeName(T) ++ " missing deinit()");
    }
}

// ── Category interfaces — mirror Java's IntList/IntSet/IntBag/IntStack ──

/// Read-only ordered list with positional access. `get(index)` returns ?f32.
pub fn assertF32List(comptime T: type) void {
    assertF32Collection(T);
    comptime {
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Mutable ordered list. Adds `add` (append) and `set` (positional replace).
pub fn assertF32MutableList(comptime T: type) void {
    assertF32List(T);
    assertF32MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
        if (!@hasDecl(T, "set")) @compileError(@typeName(T) ++ " missing set()");
    }
}

/// Read-only set marker — uniqueness implied; no extra methods of its own.
pub fn assertF32Set(comptime T: type) void {
    assertF32Collection(T);
}

/// Mutable set. `add(value) bool` returns true if the value was newly inserted.
pub fn assertF32MutableSet(comptime T: type) void {
    assertF32Set(T);
    assertF32MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only multiset (bag) with occurrence counts.
pub fn assertF32Bag(comptime T: type) void {
    assertF32Collection(T);
    comptime {
        if (!@hasDecl(T, "occurrencesOf")) @compileError(@typeName(T) ++ " missing occurrencesOf()");
        if (!@hasDecl(T, "sizeDistinct")) @compileError(@typeName(T) ++ " missing sizeDistinct()");
    }
}

/// Mutable bag. `add(value)` adds one occurrence.
pub fn assertF32MutableBag(comptime T: type) void {
    assertF32Bag(T);
    assertF32MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only LIFO stack. `peek()` returns the top element.
pub fn assertF32Stack(comptime T: type) void {
    assertF32Collection(T);
    comptime {
        if (!@hasDecl(T, "peek")) @compileError(@typeName(T) ++ " missing peek()");
    }
}

/// Mutable LIFO stack. Adds `push` and `pop`.
pub fn assertF32MutableStack(comptime T: type) void {
    assertF32Stack(T);
    assertF32MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "push")) @compileError(@typeName(T) ++ " missing push()");
        if (!@hasDecl(T, "pop")) @compileError(@typeName(T) ++ " missing pop()");
    }
}

// Compile-time verification that every concrete collection type for `f32`
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
    const ArrayList = arraylist.f32_array_list.F32ArrayList;
    assertF32MutableCollection(ArrayList);
    assertF32MutableList(ArrayList);

    // HashSet / TreeSet — Set + MutableSet
    const HashSet = hashset.f32_hash_set.F32HashSet;
    assertF32MutableCollection(HashSet);
    assertF32MutableSet(HashSet);
    const TreeSet = treeset.f32_tree_set.F32TreeSet;
    assertF32MutableCollection(TreeSet);
    assertF32MutableSet(TreeSet);

    // HashBag / TreeBag — Bag + MutableBag
    const HashBag = bag.f32_hash_bag.F32HashBag;
    assertF32MutableCollection(HashBag);
    assertF32MutableBag(HashBag);
    const TreeBag = bag.f32_tree_bag.F32TreeBag;
    assertF32MutableCollection(TreeBag);
    assertF32MutableBag(TreeBag);

    // ArrayStack — Stack + MutableStack
    const ArrayStack = stack.f32_array_stack.F32ArrayStack;
    assertF32MutableCollection(ArrayStack);
    assertF32MutableStack(ArrayStack);

    // Immutable types — read-only category trait only
    const ImmutableArrayList = immutable.immutable_f32_array_list.ImmutableF32ArrayList;
    assertF32Collection(ImmutableArrayList);
    assertF32List(ImmutableArrayList);

    const ImmutableHashSet = immutable.immutable_f32_hash_set.ImmutableF32HashSet;
    assertF32Collection(ImmutableHashSet);
    assertF32Set(ImmutableHashSet);

    const ImmutableHashBag = immutable.immutable_f32_hash_bag.ImmutableF32HashBag;
    assertF32Collection(ImmutableHashBag);
    assertF32Bag(ImmutableHashBag);

    const ImmutableArrayStack = immutable.immutable_f32_array_stack.ImmutableF32ArrayStack;
    assertF32Collection(ImmutableArrayStack);
    assertF32Stack(ImmutableArrayStack);
}

test "assertF32Collection comptime check" {
    // This test passes if it compiles — the comptime block above does the real checking.
    const arraylist = @import("../arraylist/arraylist.zig");
    assertF32Collection(arraylist.f32_array_list.F32ArrayList);
}

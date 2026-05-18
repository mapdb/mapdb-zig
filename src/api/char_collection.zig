// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only collections of `u21` values.
///
/// Any struct that has these methods can be used where an CharCollection is expected.
/// Use `assertCharCollection(T)` to verify at compile time.
///
/// Equivalent to:
///   Go:   CharIterable interface
///   Rust: CharCollection trait
///   Java: CharIterable interface
pub fn assertCharCollection(comptime T: type) void {
    // Required methods for read-only collection
    comptime {
        // fn len(*const T) usize
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        // fn isEmpty(*const T) bool
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        // fn contains(*const T, u21) bool
        if (!@hasDecl(T, "contains")) @compileError(@typeName(T) ++ " missing contains()");
    }
}

/// Comptime interface for mutable collections of `u21` values.
///
/// Extends CharCollection with mutation operations.
///
/// Equivalent to:
///   Go:   CharMutableCollection interface
///   Rust: CharMutableCollection trait
///   Java: MutableCharCollection interface
pub fn assertCharMutableCollection(comptime T: type) void {
    // Must satisfy read-only interface first
    assertCharCollection(T);

    comptime {
        // fn clear(*T) void
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
        // fn deinit(*T) void
        if (!@hasDecl(T, "deinit")) @compileError(@typeName(T) ++ " missing deinit()");
    }
}

// ── Category interfaces — mirror Java's IntList/IntSet/IntBag/IntStack ──

/// Read-only ordered list with positional access. `get(index)` returns ?u21.
pub fn assertCharList(comptime T: type) void {
    assertCharCollection(T);
    comptime {
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Mutable ordered list. Adds `add` (append) and `set` (positional replace).
pub fn assertCharMutableList(comptime T: type) void {
    assertCharList(T);
    assertCharMutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
        if (!@hasDecl(T, "set")) @compileError(@typeName(T) ++ " missing set()");
    }
}

/// Read-only set marker — uniqueness implied; no extra methods of its own.
pub fn assertCharSet(comptime T: type) void {
    assertCharCollection(T);
}

/// Mutable set. `add(value) bool` returns true if the value was newly inserted.
pub fn assertCharMutableSet(comptime T: type) void {
    assertCharSet(T);
    assertCharMutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only multiset (bag) with occurrence counts.
pub fn assertCharBag(comptime T: type) void {
    assertCharCollection(T);
    comptime {
        if (!@hasDecl(T, "occurrencesOf")) @compileError(@typeName(T) ++ " missing occurrencesOf()");
        if (!@hasDecl(T, "sizeDistinct")) @compileError(@typeName(T) ++ " missing sizeDistinct()");
    }
}

/// Mutable bag. `add(value)` adds one occurrence.
pub fn assertCharMutableBag(comptime T: type) void {
    assertCharBag(T);
    assertCharMutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only LIFO stack. `peek()` returns the top element.
pub fn assertCharStack(comptime T: type) void {
    assertCharCollection(T);
    comptime {
        if (!@hasDecl(T, "peek")) @compileError(@typeName(T) ++ " missing peek()");
    }
}

/// Mutable LIFO stack. Adds `push` and `pop`.
pub fn assertCharMutableStack(comptime T: type) void {
    assertCharStack(T);
    assertCharMutableCollection(T);
    comptime {
        if (!@hasDecl(T, "push")) @compileError(@typeName(T) ++ " missing push()");
        if (!@hasDecl(T, "pop")) @compileError(@typeName(T) ++ " missing pop()");
    }
}

// Compile-time verification that every concrete collection type for `u21`
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
    const ArrayList = arraylist.char_array_list.CharArrayList;
    assertCharMutableCollection(ArrayList);
    assertCharMutableList(ArrayList);

    // HashSet / TreeSet — Set + MutableSet
    const HashSet = hashset.char_hash_set.CharHashSet;
    assertCharMutableCollection(HashSet);
    assertCharMutableSet(HashSet);
    const TreeSet = treeset.char_tree_set.CharTreeSet;
    assertCharMutableCollection(TreeSet);
    assertCharMutableSet(TreeSet);

    // HashBag / TreeBag — Bag + MutableBag
    const HashBag = bag.char_hash_bag.CharHashBag;
    assertCharMutableCollection(HashBag);
    assertCharMutableBag(HashBag);
    const TreeBag = bag.char_tree_bag.CharTreeBag;
    assertCharMutableCollection(TreeBag);
    assertCharMutableBag(TreeBag);

    // ArrayStack — Stack + MutableStack
    const ArrayStack = stack.char_array_stack.CharArrayStack;
    assertCharMutableCollection(ArrayStack);
    assertCharMutableStack(ArrayStack);

    // Immutable types — read-only category trait only
    const ImmutableArrayList = immutable.immutable_char_array_list.ImmutableCharArrayList;
    assertCharCollection(ImmutableArrayList);
    assertCharList(ImmutableArrayList);

    const ImmutableHashSet = immutable.immutable_char_hash_set.ImmutableCharHashSet;
    assertCharCollection(ImmutableHashSet);
    assertCharSet(ImmutableHashSet);

    const ImmutableHashBag = immutable.immutable_char_hash_bag.ImmutableCharHashBag;
    assertCharCollection(ImmutableHashBag);
    assertCharBag(ImmutableHashBag);

    const ImmutableArrayStack = immutable.immutable_char_array_stack.ImmutableCharArrayStack;
    assertCharCollection(ImmutableArrayStack);
    assertCharStack(ImmutableArrayStack);
}

test "assertCharCollection comptime check" {
    // This test passes if it compiles — the comptime block above does the real checking.
    const arraylist = @import("../arraylist/arraylist.zig");
    assertCharCollection(arraylist.char_array_list.CharArrayList);
}

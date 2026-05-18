
const std = @import("std");

/// Comptime interface for read-only collections of `i16` values.
///
/// Any struct that has these methods can be used where an I16Collection is expected.
/// Use `assertI16Collection(T)` to verify at compile time.
///
/// Equivalent to:
///   Go:   I16Iterable interface
///   Rust: I16Collection trait
///   Java: I16Iterable interface
pub fn assertI16Collection(comptime T: type) void {
    // Required methods for read-only collection
    comptime {
        // fn len(*const T) usize
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        // fn isEmpty(*const T) bool
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        // fn contains(*const T, i16) bool
        if (!@hasDecl(T, "contains")) @compileError(@typeName(T) ++ " missing contains()");
    }
}

/// Comptime interface for mutable collections of `i16` values.
///
/// Extends I16Collection with mutation operations.
///
/// Equivalent to:
///   Go:   I16MutableCollection interface
///   Rust: I16MutableCollection trait
///   Java: MutableI16Collection interface
pub fn assertI16MutableCollection(comptime T: type) void {
    // Must satisfy read-only interface first
    assertI16Collection(T);

    comptime {
        // fn clear(*T) void
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
        // fn deinit(*T) void
        if (!@hasDecl(T, "deinit")) @compileError(@typeName(T) ++ " missing deinit()");
    }
}

// ── Category interfaces — mirror Java's IntList/IntSet/IntBag/IntStack ──

/// Read-only ordered list with positional access. `get(index)` returns ?i16.
pub fn assertI16List(comptime T: type) void {
    assertI16Collection(T);
    comptime {
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Mutable ordered list. Adds `add` (append) and `set` (positional replace).
pub fn assertI16MutableList(comptime T: type) void {
    assertI16List(T);
    assertI16MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
        if (!@hasDecl(T, "set")) @compileError(@typeName(T) ++ " missing set()");
    }
}

/// Read-only set marker — uniqueness implied; no extra methods of its own.
pub fn assertI16Set(comptime T: type) void {
    assertI16Collection(T);
}

/// Mutable set. `add(value) bool` returns true if the value was newly inserted.
pub fn assertI16MutableSet(comptime T: type) void {
    assertI16Set(T);
    assertI16MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only multiset (bag) with occurrence counts.
pub fn assertI16Bag(comptime T: type) void {
    assertI16Collection(T);
    comptime {
        if (!@hasDecl(T, "occurrencesOf")) @compileError(@typeName(T) ++ " missing occurrencesOf()");
        if (!@hasDecl(T, "sizeDistinct")) @compileError(@typeName(T) ++ " missing sizeDistinct()");
    }
}

/// Mutable bag. `add(value)` adds one occurrence.
pub fn assertI16MutableBag(comptime T: type) void {
    assertI16Bag(T);
    assertI16MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only LIFO stack. `peek()` returns the top element.
pub fn assertI16Stack(comptime T: type) void {
    assertI16Collection(T);
    comptime {
        if (!@hasDecl(T, "peek")) @compileError(@typeName(T) ++ " missing peek()");
    }
}

/// Mutable LIFO stack. Adds `push` and `pop`.
pub fn assertI16MutableStack(comptime T: type) void {
    assertI16Stack(T);
    assertI16MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "push")) @compileError(@typeName(T) ++ " missing push()");
        if (!@hasDecl(T, "pop")) @compileError(@typeName(T) ++ " missing pop()");
    }
}

// Compile-time verification that every concrete collection type for `i16`
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
    const ArrayList = arraylist.i16_array_list.I16ArrayList;
    assertI16MutableCollection(ArrayList);
    assertI16MutableList(ArrayList);

    // HashSet / TreeSet — Set + MutableSet
    const HashSet = hashset.i16_hash_set.I16HashSet;
    assertI16MutableCollection(HashSet);
    assertI16MutableSet(HashSet);
    const TreeSet = treeset.i16_tree_set.I16TreeSet;
    assertI16MutableCollection(TreeSet);
    assertI16MutableSet(TreeSet);

    // HashBag / TreeBag — Bag + MutableBag
    const HashBag = bag.i16_hash_bag.I16HashBag;
    assertI16MutableCollection(HashBag);
    assertI16MutableBag(HashBag);
    const TreeBag = bag.i16_tree_bag.I16TreeBag;
    assertI16MutableCollection(TreeBag);
    assertI16MutableBag(TreeBag);

    // ArrayStack — Stack + MutableStack
    const ArrayStack = stack.i16_array_stack.I16ArrayStack;
    assertI16MutableCollection(ArrayStack);
    assertI16MutableStack(ArrayStack);

    // Immutable types — read-only category trait only
    const ImmutableArrayList = immutable.immutable_i16_array_list.ImmutableI16ArrayList;
    assertI16Collection(ImmutableArrayList);
    assertI16List(ImmutableArrayList);

    const ImmutableHashSet = immutable.immutable_i16_hash_set.ImmutableI16HashSet;
    assertI16Collection(ImmutableHashSet);
    assertI16Set(ImmutableHashSet);

    const ImmutableHashBag = immutable.immutable_i16_hash_bag.ImmutableI16HashBag;
    assertI16Collection(ImmutableHashBag);
    assertI16Bag(ImmutableHashBag);

    const ImmutableArrayStack = immutable.immutable_i16_array_stack.ImmutableI16ArrayStack;
    assertI16Collection(ImmutableArrayStack);
    assertI16Stack(ImmutableArrayStack);

    // Interval — read-only Collection (integer types only)
    const interval = @import("../interval/interval.zig");
    const Interval = interval.i16_interval.I16Interval;
    assertI16Collection(Interval);
}

test "assertI16Collection comptime check" {
    // This test passes if it compiles — the comptime block above does the real checking.
    const arraylist = @import("../arraylist/arraylist.zig");
    assertI16Collection(arraylist.i16_array_list.I16ArrayList);
}

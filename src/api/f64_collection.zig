
const std = @import("std");

/// Comptime interface for read-only collections of `f64` values.
///
/// Any struct that has these methods can be used where an F64Collection is expected.
/// Use `assertF64Collection(T)` to verify at compile time.
///
/// Equivalent to:
///   Go:   F64Iterable interface
///   Rust: F64Collection trait
///   Java: F64Iterable interface
pub fn assertF64Collection(comptime T: type) void {
    // Required methods for read-only collection
    comptime {
        // fn len(*const T) usize
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        // fn isEmpty(*const T) bool
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        // fn contains(*const T, f64) bool
        if (!@hasDecl(T, "contains")) @compileError(@typeName(T) ++ " missing contains()");
    }
}

/// Comptime interface for mutable collections of `f64` values.
///
/// Extends F64Collection with mutation operations.
///
/// Equivalent to:
///   Go:   F64MutableCollection interface
///   Rust: F64MutableCollection trait
///   Java: MutableF64Collection interface
pub fn assertF64MutableCollection(comptime T: type) void {
    // Must satisfy read-only interface first
    assertF64Collection(T);

    comptime {
        // fn clear(*T) void
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
        // fn deinit(*T) void
        if (!@hasDecl(T, "deinit")) @compileError(@typeName(T) ++ " missing deinit()");
    }
}

// ── Category interfaces — mirror Java's IntList/IntSet/IntBag/IntStack ──

/// Read-only ordered list with positional access. `get(index)` returns ?f64.
pub fn assertF64List(comptime T: type) void {
    assertF64Collection(T);
    comptime {
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Mutable ordered list. Adds `add` (append) and `set` (positional replace).
pub fn assertF64MutableList(comptime T: type) void {
    assertF64List(T);
    assertF64MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
        if (!@hasDecl(T, "set")) @compileError(@typeName(T) ++ " missing set()");
    }
}

/// Read-only set marker — uniqueness implied; no extra methods of its own.
pub fn assertF64Set(comptime T: type) void {
    assertF64Collection(T);
}

/// Mutable set. `add(value) bool` returns true if the value was newly inserted.
pub fn assertF64MutableSet(comptime T: type) void {
    assertF64Set(T);
    assertF64MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only multiset (bag) with occurrence counts.
pub fn assertF64Bag(comptime T: type) void {
    assertF64Collection(T);
    comptime {
        if (!@hasDecl(T, "occurrencesOf")) @compileError(@typeName(T) ++ " missing occurrencesOf()");
        if (!@hasDecl(T, "sizeDistinct")) @compileError(@typeName(T) ++ " missing sizeDistinct()");
    }
}

/// Mutable bag. `add(value)` adds one occurrence.
pub fn assertF64MutableBag(comptime T: type) void {
    assertF64Bag(T);
    assertF64MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only LIFO stack. `peek()` returns the top element.
pub fn assertF64Stack(comptime T: type) void {
    assertF64Collection(T);
    comptime {
        if (!@hasDecl(T, "peek")) @compileError(@typeName(T) ++ " missing peek()");
    }
}

/// Mutable LIFO stack. Adds `push` and `pop`.
pub fn assertF64MutableStack(comptime T: type) void {
    assertF64Stack(T);
    assertF64MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "push")) @compileError(@typeName(T) ++ " missing push()");
        if (!@hasDecl(T, "pop")) @compileError(@typeName(T) ++ " missing pop()");
    }
}

// Compile-time verification that every concrete collection type for `f64`
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
    const ArrayList = arraylist.f64_array_list.F64ArrayList;
    assertF64MutableCollection(ArrayList);
    assertF64MutableList(ArrayList);

    // HashSet / TreeSet — Set + MutableSet
    const HashSet = hashset.f64_hash_set.F64HashSet;
    assertF64MutableCollection(HashSet);
    assertF64MutableSet(HashSet);
    const TreeSet = treeset.f64_tree_set.F64TreeSet;
    assertF64MutableCollection(TreeSet);
    assertF64MutableSet(TreeSet);

    // HashBag / TreeBag — Bag + MutableBag
    const HashBag = bag.f64_hash_bag.F64HashBag;
    assertF64MutableCollection(HashBag);
    assertF64MutableBag(HashBag);
    const TreeBag = bag.f64_tree_bag.F64TreeBag;
    assertF64MutableCollection(TreeBag);
    assertF64MutableBag(TreeBag);

    // ArrayStack — Stack + MutableStack
    const ArrayStack = stack.f64_array_stack.F64ArrayStack;
    assertF64MutableCollection(ArrayStack);
    assertF64MutableStack(ArrayStack);

    // Immutable types — read-only category trait only
    const ImmutableArrayList = immutable.immutable_f64_array_list.ImmutableF64ArrayList;
    assertF64Collection(ImmutableArrayList);
    assertF64List(ImmutableArrayList);

    const ImmutableHashSet = immutable.immutable_f64_hash_set.ImmutableF64HashSet;
    assertF64Collection(ImmutableHashSet);
    assertF64Set(ImmutableHashSet);

    const ImmutableHashBag = immutable.immutable_f64_hash_bag.ImmutableF64HashBag;
    assertF64Collection(ImmutableHashBag);
    assertF64Bag(ImmutableHashBag);

    const ImmutableArrayStack = immutable.immutable_f64_array_stack.ImmutableF64ArrayStack;
    assertF64Collection(ImmutableArrayStack);
    assertF64Stack(ImmutableArrayStack);
}

test "assertF64Collection comptime check" {
    // This test passes if it compiles — the comptime block above does the real checking.
    const arraylist = @import("../arraylist/arraylist.zig");
    assertF64Collection(arraylist.f64_array_list.F64ArrayList);
}

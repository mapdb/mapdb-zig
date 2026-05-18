
const std = @import("std");

/// Comptime interface for read-only collections of `i64` values.
///
/// Any struct that has these methods can be used where an I64Collection is expected.
/// Use `assertI64Collection(T)` to verify at compile time.
///
/// Equivalent to:
///   Go:   I64Iterable interface
///   Rust: I64Collection trait
///   Java: I64Iterable interface
pub fn assertI64Collection(comptime T: type) void {
    // Required methods for read-only collection
    comptime {
        // fn len(*const T) usize
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        // fn isEmpty(*const T) bool
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        // fn contains(*const T, i64) bool
        if (!@hasDecl(T, "contains")) @compileError(@typeName(T) ++ " missing contains()");
    }
}

/// Comptime interface for mutable collections of `i64` values.
///
/// Extends I64Collection with mutation operations.
///
/// Equivalent to:
///   Go:   I64MutableCollection interface
///   Rust: I64MutableCollection trait
///   Java: MutableI64Collection interface
pub fn assertI64MutableCollection(comptime T: type) void {
    // Must satisfy read-only interface first
    assertI64Collection(T);

    comptime {
        // fn clear(*T) void
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
        // fn deinit(*T) void
        if (!@hasDecl(T, "deinit")) @compileError(@typeName(T) ++ " missing deinit()");
    }
}

// ── Category interfaces — mirror Java's IntList/IntSet/IntBag/IntStack ──

/// Read-only ordered list with positional access. `get(index)` returns ?i64.
pub fn assertI64List(comptime T: type) void {
    assertI64Collection(T);
    comptime {
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Mutable ordered list. Adds `add` (append) and `set` (positional replace).
pub fn assertI64MutableList(comptime T: type) void {
    assertI64List(T);
    assertI64MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
        if (!@hasDecl(T, "set")) @compileError(@typeName(T) ++ " missing set()");
    }
}

/// Read-only set marker — uniqueness implied; no extra methods of its own.
pub fn assertI64Set(comptime T: type) void {
    assertI64Collection(T);
}

/// Mutable set. `add(value) bool` returns true if the value was newly inserted.
pub fn assertI64MutableSet(comptime T: type) void {
    assertI64Set(T);
    assertI64MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only multiset (bag) with occurrence counts.
pub fn assertI64Bag(comptime T: type) void {
    assertI64Collection(T);
    comptime {
        if (!@hasDecl(T, "occurrencesOf")) @compileError(@typeName(T) ++ " missing occurrencesOf()");
        if (!@hasDecl(T, "sizeDistinct")) @compileError(@typeName(T) ++ " missing sizeDistinct()");
    }
}

/// Mutable bag. `add(value)` adds one occurrence.
pub fn assertI64MutableBag(comptime T: type) void {
    assertI64Bag(T);
    assertI64MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "add")) @compileError(@typeName(T) ++ " missing add()");
    }
}

/// Read-only LIFO stack. `peek()` returns the top element.
pub fn assertI64Stack(comptime T: type) void {
    assertI64Collection(T);
    comptime {
        if (!@hasDecl(T, "peek")) @compileError(@typeName(T) ++ " missing peek()");
    }
}

/// Mutable LIFO stack. Adds `push` and `pop`.
pub fn assertI64MutableStack(comptime T: type) void {
    assertI64Stack(T);
    assertI64MutableCollection(T);
    comptime {
        if (!@hasDecl(T, "push")) @compileError(@typeName(T) ++ " missing push()");
        if (!@hasDecl(T, "pop")) @compileError(@typeName(T) ++ " missing pop()");
    }
}

// Compile-time verification that every concrete collection type for `i64`
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
    const ArrayList = arraylist.i64_array_list.I64ArrayList;
    assertI64MutableCollection(ArrayList);
    assertI64MutableList(ArrayList);

    // HashSet / TreeSet — Set + MutableSet
    const HashSet = hashset.i64_hash_set.I64HashSet;
    assertI64MutableCollection(HashSet);
    assertI64MutableSet(HashSet);
    const TreeSet = treeset.i64_tree_set.I64TreeSet;
    assertI64MutableCollection(TreeSet);
    assertI64MutableSet(TreeSet);

    // HashBag / TreeBag — Bag + MutableBag
    const HashBag = bag.i64_hash_bag.I64HashBag;
    assertI64MutableCollection(HashBag);
    assertI64MutableBag(HashBag);
    const TreeBag = bag.i64_tree_bag.I64TreeBag;
    assertI64MutableCollection(TreeBag);
    assertI64MutableBag(TreeBag);

    // ArrayStack — Stack + MutableStack
    const ArrayStack = stack.i64_array_stack.I64ArrayStack;
    assertI64MutableCollection(ArrayStack);
    assertI64MutableStack(ArrayStack);

    // Immutable types — read-only category trait only
    const ImmutableArrayList = immutable.immutable_i64_array_list.ImmutableI64ArrayList;
    assertI64Collection(ImmutableArrayList);
    assertI64List(ImmutableArrayList);

    const ImmutableHashSet = immutable.immutable_i64_hash_set.ImmutableI64HashSet;
    assertI64Collection(ImmutableHashSet);
    assertI64Set(ImmutableHashSet);

    const ImmutableHashBag = immutable.immutable_i64_hash_bag.ImmutableI64HashBag;
    assertI64Collection(ImmutableHashBag);
    assertI64Bag(ImmutableHashBag);

    const ImmutableArrayStack = immutable.immutable_i64_array_stack.ImmutableI64ArrayStack;
    assertI64Collection(ImmutableArrayStack);
    assertI64Stack(ImmutableArrayStack);

    // Interval — read-only Collection (integer types only)
    const interval = @import("../interval/interval.zig");
    const Interval = interval.i64_interval.I64Interval;
    assertI64Collection(Interval);
}

test "assertI64Collection comptime check" {
    // This test passes if it compiles — the comptime block above does the real checking.
    const arraylist = @import("../arraylist/arraylist.zig");
    assertI64Collection(arraylist.i64_array_list.I64ArrayList);
}

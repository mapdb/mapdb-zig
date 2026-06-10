// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic tree set type.
//!
//! `TreeSet(T)` is a single-source generic backed by `std.Treap` with a
//! type-branched total-order comparator. This module exposes the named
//! `<T>TreeSet` aliases that the rest of the project (and the cross-language
//! validate harness) consume, and preserves the historical per-file lowercase
//! namespaces for backward compatibility (e.g. `treeset.i32_tree_set.I32TreeSet`).

pub const TreeSet = @import("tree_set.zig").TreeSet;

// ---- Named tree set aliases ----

pub const BoolTreeSet = TreeSet(bool);
pub const CharTreeSet = TreeSet(u21);
pub const F32TreeSet = TreeSet(f32);
pub const F64TreeSet = TreeSet(f64);
pub const I8TreeSet = TreeSet(i8);
pub const I16TreeSet = TreeSet(i16);
pub const I32TreeSet = TreeSet(i32);
pub const I64TreeSet = TreeSet(i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_tree_set = struct {
    pub const BoolTreeSet = TreeSet(bool);
};
pub const char_tree_set = struct {
    pub const CharTreeSet = TreeSet(u21);
};
pub const f32_tree_set = struct {
    pub const F32TreeSet = TreeSet(f32);
};
pub const f64_tree_set = struct {
    pub const F64TreeSet = TreeSet(f64);
};
pub const i8_tree_set = struct {
    pub const I8TreeSet = TreeSet(i8);
};
pub const i16_tree_set = struct {
    pub const I16TreeSet = TreeSet(i16);
};
pub const i32_tree_set = struct {
    pub const I32TreeSet = TreeSet(i32);
};
pub const i64_tree_set = struct {
    pub const I64TreeSet = TreeSet(i64);
};

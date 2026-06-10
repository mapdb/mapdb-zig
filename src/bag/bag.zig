// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic bag types.
//!
//! `HashBag(T)` is backed by `OpenHashMap(T, usize)`; `TreeBag(T)` is backed by
//! `std.Treap` with a type-branched total-order comparator. This module exposes
//! the named `<T>HashBag` / `<T>TreeBag` aliases that the rest of the project
//! (and the cross-language validate harness) consume, and preserves the
//! historical per-file lowercase namespaces for backward compatibility (e.g.
//! `bag.i32_hash_bag.I32HashBag`).

pub const HashBag = @import("hash_bag.zig").HashBag;
pub const TreeBag = @import("tree_bag.zig").TreeBag;

// ---- Named hash bag aliases ----

pub const BoolHashBag = HashBag(bool);
pub const CharHashBag = HashBag(u21);
pub const F32HashBag = HashBag(f32);
pub const F64HashBag = HashBag(f64);
pub const I8HashBag = HashBag(i8);
pub const I16HashBag = HashBag(i16);
pub const I32HashBag = HashBag(i32);
pub const I64HashBag = HashBag(i64);

// ---- Named tree bag aliases ----

pub const BoolTreeBag = TreeBag(bool);
pub const CharTreeBag = TreeBag(u21);
pub const F32TreeBag = TreeBag(f32);
pub const F64TreeBag = TreeBag(f64);
pub const I8TreeBag = TreeBag(i8);
pub const I16TreeBag = TreeBag(i16);
pub const I32TreeBag = TreeBag(i32);
pub const I64TreeBag = TreeBag(i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_hash_bag = struct {
    pub const BoolHashBag = HashBag(bool);
};
pub const bool_tree_bag = struct {
    pub const BoolTreeBag = TreeBag(bool);
};
pub const char_hash_bag = struct {
    pub const CharHashBag = HashBag(u21);
};
pub const char_tree_bag = struct {
    pub const CharTreeBag = TreeBag(u21);
};
pub const f32_hash_bag = struct {
    pub const F32HashBag = HashBag(f32);
};
pub const f32_tree_bag = struct {
    pub const F32TreeBag = TreeBag(f32);
};
pub const f64_hash_bag = struct {
    pub const F64HashBag = HashBag(f64);
};
pub const f64_tree_bag = struct {
    pub const F64TreeBag = TreeBag(f64);
};
pub const i8_hash_bag = struct {
    pub const I8HashBag = HashBag(i8);
};
pub const i8_tree_bag = struct {
    pub const I8TreeBag = TreeBag(i8);
};
pub const i16_hash_bag = struct {
    pub const I16HashBag = HashBag(i16);
};
pub const i16_tree_bag = struct {
    pub const I16TreeBag = TreeBag(i16);
};
pub const i32_hash_bag = struct {
    pub const I32HashBag = HashBag(i32);
};
pub const i32_tree_bag = struct {
    pub const I32TreeBag = TreeBag(i32);
};
pub const i64_hash_bag = struct {
    pub const I64HashBag = HashBag(i64);
};
pub const i64_tree_bag = struct {
    pub const I64TreeBag = TreeBag(i64);
};

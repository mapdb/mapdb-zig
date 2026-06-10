// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic tree map type.
//!
//! `TreeMap(K, V)` is a single-source generic backed by two sorted
//! `std.ArrayListUnmanaged`s, binary-searched via a type-branched total-order
//! comparator (IEEE 754 totalOrder for float keys, natural order otherwise).
//! This module exposes the named `<K><V>TreeMap` aliases that the rest of the
//! project (and the cross-language validate harness) consume, and preserves the
//! historical per-file lowercase namespaces for backward compatibility (e.g.
//! `treemap.i32_i32_tree_map.I32I32TreeMap`).

pub const TreeMap = @import("tree_map.zig").TreeMap;

// ---- Named tree map aliases ----

pub const BoolBoolTreeMap = TreeMap(bool, bool);
pub const BoolCharTreeMap = TreeMap(bool, u21);
pub const BoolF32TreeMap = TreeMap(bool, f32);
pub const BoolF64TreeMap = TreeMap(bool, f64);
pub const BoolI8TreeMap = TreeMap(bool, i8);
pub const BoolI16TreeMap = TreeMap(bool, i16);
pub const BoolI32TreeMap = TreeMap(bool, i32);
pub const BoolI64TreeMap = TreeMap(bool, i64);
pub const CharBoolTreeMap = TreeMap(u21, bool);
pub const CharCharTreeMap = TreeMap(u21, u21);
pub const CharF32TreeMap = TreeMap(u21, f32);
pub const CharF64TreeMap = TreeMap(u21, f64);
pub const CharI8TreeMap = TreeMap(u21, i8);
pub const CharI16TreeMap = TreeMap(u21, i16);
pub const CharI32TreeMap = TreeMap(u21, i32);
pub const CharI64TreeMap = TreeMap(u21, i64);
pub const F32BoolTreeMap = TreeMap(f32, bool);
pub const F32CharTreeMap = TreeMap(f32, u21);
pub const F32F32TreeMap = TreeMap(f32, f32);
pub const F32F64TreeMap = TreeMap(f32, f64);
pub const F32I8TreeMap = TreeMap(f32, i8);
pub const F32I16TreeMap = TreeMap(f32, i16);
pub const F32I32TreeMap = TreeMap(f32, i32);
pub const F32I64TreeMap = TreeMap(f32, i64);
pub const F64BoolTreeMap = TreeMap(f64, bool);
pub const F64CharTreeMap = TreeMap(f64, u21);
pub const F64F32TreeMap = TreeMap(f64, f32);
pub const F64F64TreeMap = TreeMap(f64, f64);
pub const F64I8TreeMap = TreeMap(f64, i8);
pub const F64I16TreeMap = TreeMap(f64, i16);
pub const F64I32TreeMap = TreeMap(f64, i32);
pub const F64I64TreeMap = TreeMap(f64, i64);
pub const I8BoolTreeMap = TreeMap(i8, bool);
pub const I8CharTreeMap = TreeMap(i8, u21);
pub const I8F32TreeMap = TreeMap(i8, f32);
pub const I8F64TreeMap = TreeMap(i8, f64);
pub const I8I8TreeMap = TreeMap(i8, i8);
pub const I8I16TreeMap = TreeMap(i8, i16);
pub const I8I32TreeMap = TreeMap(i8, i32);
pub const I8I64TreeMap = TreeMap(i8, i64);
pub const I16BoolTreeMap = TreeMap(i16, bool);
pub const I16CharTreeMap = TreeMap(i16, u21);
pub const I16F32TreeMap = TreeMap(i16, f32);
pub const I16F64TreeMap = TreeMap(i16, f64);
pub const I16I8TreeMap = TreeMap(i16, i8);
pub const I16I16TreeMap = TreeMap(i16, i16);
pub const I16I32TreeMap = TreeMap(i16, i32);
pub const I16I64TreeMap = TreeMap(i16, i64);
pub const I32BoolTreeMap = TreeMap(i32, bool);
pub const I32CharTreeMap = TreeMap(i32, u21);
pub const I32F32TreeMap = TreeMap(i32, f32);
pub const I32F64TreeMap = TreeMap(i32, f64);
pub const I32I8TreeMap = TreeMap(i32, i8);
pub const I32I16TreeMap = TreeMap(i32, i16);
pub const I32I32TreeMap = TreeMap(i32, i32);
pub const I32I64TreeMap = TreeMap(i32, i64);
pub const I64BoolTreeMap = TreeMap(i64, bool);
pub const I64CharTreeMap = TreeMap(i64, u21);
pub const I64F32TreeMap = TreeMap(i64, f32);
pub const I64F64TreeMap = TreeMap(i64, f64);
pub const I64I8TreeMap = TreeMap(i64, i8);
pub const I64I16TreeMap = TreeMap(i64, i16);
pub const I64I32TreeMap = TreeMap(i64, i32);
pub const I64I64TreeMap = TreeMap(i64, i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_bool_tree_map = struct {
    pub const BoolBoolTreeMap = TreeMap(bool, bool);
};
pub const bool_char_tree_map = struct {
    pub const BoolCharTreeMap = TreeMap(bool, u21);
};
pub const bool_f32_tree_map = struct {
    pub const BoolF32TreeMap = TreeMap(bool, f32);
};
pub const bool_f64_tree_map = struct {
    pub const BoolF64TreeMap = TreeMap(bool, f64);
};
pub const bool_i8_tree_map = struct {
    pub const BoolI8TreeMap = TreeMap(bool, i8);
};
pub const bool_i16_tree_map = struct {
    pub const BoolI16TreeMap = TreeMap(bool, i16);
};
pub const bool_i32_tree_map = struct {
    pub const BoolI32TreeMap = TreeMap(bool, i32);
};
pub const bool_i64_tree_map = struct {
    pub const BoolI64TreeMap = TreeMap(bool, i64);
};
pub const char_bool_tree_map = struct {
    pub const CharBoolTreeMap = TreeMap(u21, bool);
};
pub const char_char_tree_map = struct {
    pub const CharCharTreeMap = TreeMap(u21, u21);
};
pub const char_f32_tree_map = struct {
    pub const CharF32TreeMap = TreeMap(u21, f32);
};
pub const char_f64_tree_map = struct {
    pub const CharF64TreeMap = TreeMap(u21, f64);
};
pub const char_i8_tree_map = struct {
    pub const CharI8TreeMap = TreeMap(u21, i8);
};
pub const char_i16_tree_map = struct {
    pub const CharI16TreeMap = TreeMap(u21, i16);
};
pub const char_i32_tree_map = struct {
    pub const CharI32TreeMap = TreeMap(u21, i32);
};
pub const char_i64_tree_map = struct {
    pub const CharI64TreeMap = TreeMap(u21, i64);
};
pub const f32_bool_tree_map = struct {
    pub const F32BoolTreeMap = TreeMap(f32, bool);
};
pub const f32_char_tree_map = struct {
    pub const F32CharTreeMap = TreeMap(f32, u21);
};
pub const f32_f32_tree_map = struct {
    pub const F32F32TreeMap = TreeMap(f32, f32);
};
pub const f32_f64_tree_map = struct {
    pub const F32F64TreeMap = TreeMap(f32, f64);
};
pub const f32_i8_tree_map = struct {
    pub const F32I8TreeMap = TreeMap(f32, i8);
};
pub const f32_i16_tree_map = struct {
    pub const F32I16TreeMap = TreeMap(f32, i16);
};
pub const f32_i32_tree_map = struct {
    pub const F32I32TreeMap = TreeMap(f32, i32);
};
pub const f32_i64_tree_map = struct {
    pub const F32I64TreeMap = TreeMap(f32, i64);
};
pub const f64_bool_tree_map = struct {
    pub const F64BoolTreeMap = TreeMap(f64, bool);
};
pub const f64_char_tree_map = struct {
    pub const F64CharTreeMap = TreeMap(f64, u21);
};
pub const f64_f32_tree_map = struct {
    pub const F64F32TreeMap = TreeMap(f64, f32);
};
pub const f64_f64_tree_map = struct {
    pub const F64F64TreeMap = TreeMap(f64, f64);
};
pub const f64_i8_tree_map = struct {
    pub const F64I8TreeMap = TreeMap(f64, i8);
};
pub const f64_i16_tree_map = struct {
    pub const F64I16TreeMap = TreeMap(f64, i16);
};
pub const f64_i32_tree_map = struct {
    pub const F64I32TreeMap = TreeMap(f64, i32);
};
pub const f64_i64_tree_map = struct {
    pub const F64I64TreeMap = TreeMap(f64, i64);
};
pub const i8_bool_tree_map = struct {
    pub const I8BoolTreeMap = TreeMap(i8, bool);
};
pub const i8_char_tree_map = struct {
    pub const I8CharTreeMap = TreeMap(i8, u21);
};
pub const i8_f32_tree_map = struct {
    pub const I8F32TreeMap = TreeMap(i8, f32);
};
pub const i8_f64_tree_map = struct {
    pub const I8F64TreeMap = TreeMap(i8, f64);
};
pub const i8_i8_tree_map = struct {
    pub const I8I8TreeMap = TreeMap(i8, i8);
};
pub const i8_i16_tree_map = struct {
    pub const I8I16TreeMap = TreeMap(i8, i16);
};
pub const i8_i32_tree_map = struct {
    pub const I8I32TreeMap = TreeMap(i8, i32);
};
pub const i8_i64_tree_map = struct {
    pub const I8I64TreeMap = TreeMap(i8, i64);
};
pub const i16_bool_tree_map = struct {
    pub const I16BoolTreeMap = TreeMap(i16, bool);
};
pub const i16_char_tree_map = struct {
    pub const I16CharTreeMap = TreeMap(i16, u21);
};
pub const i16_f32_tree_map = struct {
    pub const I16F32TreeMap = TreeMap(i16, f32);
};
pub const i16_f64_tree_map = struct {
    pub const I16F64TreeMap = TreeMap(i16, f64);
};
pub const i16_i8_tree_map = struct {
    pub const I16I8TreeMap = TreeMap(i16, i8);
};
pub const i16_i16_tree_map = struct {
    pub const I16I16TreeMap = TreeMap(i16, i16);
};
pub const i16_i32_tree_map = struct {
    pub const I16I32TreeMap = TreeMap(i16, i32);
};
pub const i16_i64_tree_map = struct {
    pub const I16I64TreeMap = TreeMap(i16, i64);
};
pub const i32_bool_tree_map = struct {
    pub const I32BoolTreeMap = TreeMap(i32, bool);
};
pub const i32_char_tree_map = struct {
    pub const I32CharTreeMap = TreeMap(i32, u21);
};
pub const i32_f32_tree_map = struct {
    pub const I32F32TreeMap = TreeMap(i32, f32);
};
pub const i32_f64_tree_map = struct {
    pub const I32F64TreeMap = TreeMap(i32, f64);
};
pub const i32_i8_tree_map = struct {
    pub const I32I8TreeMap = TreeMap(i32, i8);
};
pub const i32_i16_tree_map = struct {
    pub const I32I16TreeMap = TreeMap(i32, i16);
};
pub const i32_i32_tree_map = struct {
    pub const I32I32TreeMap = TreeMap(i32, i32);
};
pub const i32_i64_tree_map = struct {
    pub const I32I64TreeMap = TreeMap(i32, i64);
};
pub const i64_bool_tree_map = struct {
    pub const I64BoolTreeMap = TreeMap(i64, bool);
};
pub const i64_char_tree_map = struct {
    pub const I64CharTreeMap = TreeMap(i64, u21);
};
pub const i64_f32_tree_map = struct {
    pub const I64F32TreeMap = TreeMap(i64, f32);
};
pub const i64_f64_tree_map = struct {
    pub const I64F64TreeMap = TreeMap(i64, f64);
};
pub const i64_i8_tree_map = struct {
    pub const I64I8TreeMap = TreeMap(i64, i8);
};
pub const i64_i16_tree_map = struct {
    pub const I64I16TreeMap = TreeMap(i64, i16);
};
pub const i64_i32_tree_map = struct {
    pub const I64I32TreeMap = TreeMap(i64, i32);
};
pub const i64_i64_tree_map = struct {
    pub const I64I64TreeMap = TreeMap(i64, i64);
};

// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic hash map / bidirectional hash map types.
//!
//! `HashMap(K, V)` and `HashBiMap(K, V)` are single-source generics. This
//! module exposes the named `<K><V>HashMap` / `<K><V>HashBiMap` aliases that
//! the rest of the project (and the cross-language validate harness) consume,
//! and preserves the historical per-file lowercase namespaces for backward
//! compatibility (e.g. `hashmap.i32_i32_hash_map.I32I32HashMap`).

pub const HashMap = @import("hash_map.zig").HashMap;
pub const HashBiMap = @import("hash_bi_map.zig").HashBiMap;

// ---- Named plain-map aliases ----

pub const BoolBoolHashMap = HashMap(bool, bool);
pub const BoolCharHashMap = HashMap(bool, u21);
pub const BoolF32HashMap = HashMap(bool, f32);
pub const BoolF64HashMap = HashMap(bool, f64);
pub const BoolI8HashMap = HashMap(bool, i8);
pub const BoolI16HashMap = HashMap(bool, i16);
pub const BoolI32HashMap = HashMap(bool, i32);
pub const BoolI64HashMap = HashMap(bool, i64);
pub const CharBoolHashMap = HashMap(u21, bool);
pub const CharCharHashMap = HashMap(u21, u21);
pub const CharF32HashMap = HashMap(u21, f32);
pub const CharF64HashMap = HashMap(u21, f64);
pub const CharI8HashMap = HashMap(u21, i8);
pub const CharI16HashMap = HashMap(u21, i16);
pub const CharI32HashMap = HashMap(u21, i32);
pub const CharI64HashMap = HashMap(u21, i64);
pub const F32BoolHashMap = HashMap(f32, bool);
pub const F32CharHashMap = HashMap(f32, u21);
pub const F32F32HashMap = HashMap(f32, f32);
pub const F32F64HashMap = HashMap(f32, f64);
pub const F32I8HashMap = HashMap(f32, i8);
pub const F32I16HashMap = HashMap(f32, i16);
pub const F32I32HashMap = HashMap(f32, i32);
pub const F32I64HashMap = HashMap(f32, i64);
pub const F64BoolHashMap = HashMap(f64, bool);
pub const F64CharHashMap = HashMap(f64, u21);
pub const F64F32HashMap = HashMap(f64, f32);
pub const F64F64HashMap = HashMap(f64, f64);
pub const F64I8HashMap = HashMap(f64, i8);
pub const F64I16HashMap = HashMap(f64, i16);
pub const F64I32HashMap = HashMap(f64, i32);
pub const F64I64HashMap = HashMap(f64, i64);
pub const I8BoolHashMap = HashMap(i8, bool);
pub const I8CharHashMap = HashMap(i8, u21);
pub const I8F32HashMap = HashMap(i8, f32);
pub const I8F64HashMap = HashMap(i8, f64);
pub const I8I8HashMap = HashMap(i8, i8);
pub const I8I16HashMap = HashMap(i8, i16);
pub const I8I32HashMap = HashMap(i8, i32);
pub const I8I64HashMap = HashMap(i8, i64);
pub const I16BoolHashMap = HashMap(i16, bool);
pub const I16CharHashMap = HashMap(i16, u21);
pub const I16F32HashMap = HashMap(i16, f32);
pub const I16F64HashMap = HashMap(i16, f64);
pub const I16I8HashMap = HashMap(i16, i8);
pub const I16I16HashMap = HashMap(i16, i16);
pub const I16I32HashMap = HashMap(i16, i32);
pub const I16I64HashMap = HashMap(i16, i64);
pub const I32BoolHashMap = HashMap(i32, bool);
pub const I32CharHashMap = HashMap(i32, u21);
pub const I32F32HashMap = HashMap(i32, f32);
pub const I32F64HashMap = HashMap(i32, f64);
pub const I32I8HashMap = HashMap(i32, i8);
pub const I32I16HashMap = HashMap(i32, i16);
pub const I32I32HashMap = HashMap(i32, i32);
pub const I32I64HashMap = HashMap(i32, i64);
pub const I64BoolHashMap = HashMap(i64, bool);
pub const I64CharHashMap = HashMap(i64, u21);
pub const I64F32HashMap = HashMap(i64, f32);
pub const I64F64HashMap = HashMap(i64, f64);
pub const I64I8HashMap = HashMap(i64, i8);
pub const I64I16HashMap = HashMap(i64, i16);
pub const I64I32HashMap = HashMap(i64, i32);
pub const I64I64HashMap = HashMap(i64, i64);

// ---- Named bidirectional-map aliases ----

pub const BoolBoolHashBiMap = HashBiMap(bool, bool);
pub const BoolCharHashBiMap = HashBiMap(bool, u21);
pub const BoolF32HashBiMap = HashBiMap(bool, f32);
pub const BoolF64HashBiMap = HashBiMap(bool, f64);
pub const BoolI8HashBiMap = HashBiMap(bool, i8);
pub const BoolI16HashBiMap = HashBiMap(bool, i16);
pub const BoolI32HashBiMap = HashBiMap(bool, i32);
pub const BoolI64HashBiMap = HashBiMap(bool, i64);
pub const CharBoolHashBiMap = HashBiMap(u21, bool);
pub const CharCharHashBiMap = HashBiMap(u21, u21);
pub const CharF32HashBiMap = HashBiMap(u21, f32);
pub const CharF64HashBiMap = HashBiMap(u21, f64);
pub const CharI8HashBiMap = HashBiMap(u21, i8);
pub const CharI16HashBiMap = HashBiMap(u21, i16);
pub const CharI32HashBiMap = HashBiMap(u21, i32);
pub const CharI64HashBiMap = HashBiMap(u21, i64);
pub const F32BoolHashBiMap = HashBiMap(f32, bool);
pub const F32CharHashBiMap = HashBiMap(f32, u21);
pub const F32F32HashBiMap = HashBiMap(f32, f32);
pub const F32F64HashBiMap = HashBiMap(f32, f64);
pub const F32I8HashBiMap = HashBiMap(f32, i8);
pub const F32I16HashBiMap = HashBiMap(f32, i16);
pub const F32I32HashBiMap = HashBiMap(f32, i32);
pub const F32I64HashBiMap = HashBiMap(f32, i64);
pub const F64BoolHashBiMap = HashBiMap(f64, bool);
pub const F64CharHashBiMap = HashBiMap(f64, u21);
pub const F64F32HashBiMap = HashBiMap(f64, f32);
pub const F64F64HashBiMap = HashBiMap(f64, f64);
pub const F64I8HashBiMap = HashBiMap(f64, i8);
pub const F64I16HashBiMap = HashBiMap(f64, i16);
pub const F64I32HashBiMap = HashBiMap(f64, i32);
pub const F64I64HashBiMap = HashBiMap(f64, i64);
pub const I8BoolHashBiMap = HashBiMap(i8, bool);
pub const I8CharHashBiMap = HashBiMap(i8, u21);
pub const I8F32HashBiMap = HashBiMap(i8, f32);
pub const I8F64HashBiMap = HashBiMap(i8, f64);
pub const I8I8HashBiMap = HashBiMap(i8, i8);
pub const I8I16HashBiMap = HashBiMap(i8, i16);
pub const I8I32HashBiMap = HashBiMap(i8, i32);
pub const I8I64HashBiMap = HashBiMap(i8, i64);
pub const I16BoolHashBiMap = HashBiMap(i16, bool);
pub const I16CharHashBiMap = HashBiMap(i16, u21);
pub const I16F32HashBiMap = HashBiMap(i16, f32);
pub const I16F64HashBiMap = HashBiMap(i16, f64);
pub const I16I8HashBiMap = HashBiMap(i16, i8);
pub const I16I16HashBiMap = HashBiMap(i16, i16);
pub const I16I32HashBiMap = HashBiMap(i16, i32);
pub const I16I64HashBiMap = HashBiMap(i16, i64);
pub const I32BoolHashBiMap = HashBiMap(i32, bool);
pub const I32CharHashBiMap = HashBiMap(i32, u21);
pub const I32F32HashBiMap = HashBiMap(i32, f32);
pub const I32F64HashBiMap = HashBiMap(i32, f64);
pub const I32I8HashBiMap = HashBiMap(i32, i8);
pub const I32I16HashBiMap = HashBiMap(i32, i16);
pub const I32I32HashBiMap = HashBiMap(i32, i32);
pub const I32I64HashBiMap = HashBiMap(i32, i64);
pub const I64BoolHashBiMap = HashBiMap(i64, bool);
pub const I64CharHashBiMap = HashBiMap(i64, u21);
pub const I64F32HashBiMap = HashBiMap(i64, f32);
pub const I64F64HashBiMap = HashBiMap(i64, f64);
pub const I64I8HashBiMap = HashBiMap(i64, i8);
pub const I64I16HashBiMap = HashBiMap(i64, i16);
pub const I64I32HashBiMap = HashBiMap(i64, i32);
pub const I64I64HashBiMap = HashBiMap(i64, i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_bool_hash_map = struct {
    pub const BoolBoolHashMap = HashMap(bool, bool);
};
pub const bool_char_hash_map = struct {
    pub const BoolCharHashMap = HashMap(bool, u21);
};
pub const bool_f32_hash_map = struct {
    pub const BoolF32HashMap = HashMap(bool, f32);
};
pub const bool_f64_hash_map = struct {
    pub const BoolF64HashMap = HashMap(bool, f64);
};
pub const bool_i8_hash_map = struct {
    pub const BoolI8HashMap = HashMap(bool, i8);
};
pub const bool_i16_hash_map = struct {
    pub const BoolI16HashMap = HashMap(bool, i16);
};
pub const bool_i32_hash_map = struct {
    pub const BoolI32HashMap = HashMap(bool, i32);
};
pub const bool_i64_hash_map = struct {
    pub const BoolI64HashMap = HashMap(bool, i64);
};
pub const char_bool_hash_map = struct {
    pub const CharBoolHashMap = HashMap(u21, bool);
};
pub const char_char_hash_map = struct {
    pub const CharCharHashMap = HashMap(u21, u21);
};
pub const char_f32_hash_map = struct {
    pub const CharF32HashMap = HashMap(u21, f32);
};
pub const char_f64_hash_map = struct {
    pub const CharF64HashMap = HashMap(u21, f64);
};
pub const char_i8_hash_map = struct {
    pub const CharI8HashMap = HashMap(u21, i8);
};
pub const char_i16_hash_map = struct {
    pub const CharI16HashMap = HashMap(u21, i16);
};
pub const char_i32_hash_map = struct {
    pub const CharI32HashMap = HashMap(u21, i32);
};
pub const char_i64_hash_map = struct {
    pub const CharI64HashMap = HashMap(u21, i64);
};
pub const f32_bool_hash_map = struct {
    pub const F32BoolHashMap = HashMap(f32, bool);
};
pub const f32_char_hash_map = struct {
    pub const F32CharHashMap = HashMap(f32, u21);
};
pub const f32_f32_hash_map = struct {
    pub const F32F32HashMap = HashMap(f32, f32);
};
pub const f32_f64_hash_map = struct {
    pub const F32F64HashMap = HashMap(f32, f64);
};
pub const f32_i8_hash_map = struct {
    pub const F32I8HashMap = HashMap(f32, i8);
};
pub const f32_i16_hash_map = struct {
    pub const F32I16HashMap = HashMap(f32, i16);
};
pub const f32_i32_hash_map = struct {
    pub const F32I32HashMap = HashMap(f32, i32);
};
pub const f32_i64_hash_map = struct {
    pub const F32I64HashMap = HashMap(f32, i64);
};
pub const f64_bool_hash_map = struct {
    pub const F64BoolHashMap = HashMap(f64, bool);
};
pub const f64_char_hash_map = struct {
    pub const F64CharHashMap = HashMap(f64, u21);
};
pub const f64_f32_hash_map = struct {
    pub const F64F32HashMap = HashMap(f64, f32);
};
pub const f64_f64_hash_map = struct {
    pub const F64F64HashMap = HashMap(f64, f64);
};
pub const f64_i8_hash_map = struct {
    pub const F64I8HashMap = HashMap(f64, i8);
};
pub const f64_i16_hash_map = struct {
    pub const F64I16HashMap = HashMap(f64, i16);
};
pub const f64_i32_hash_map = struct {
    pub const F64I32HashMap = HashMap(f64, i32);
};
pub const f64_i64_hash_map = struct {
    pub const F64I64HashMap = HashMap(f64, i64);
};
pub const i8_bool_hash_map = struct {
    pub const I8BoolHashMap = HashMap(i8, bool);
};
pub const i8_char_hash_map = struct {
    pub const I8CharHashMap = HashMap(i8, u21);
};
pub const i8_f32_hash_map = struct {
    pub const I8F32HashMap = HashMap(i8, f32);
};
pub const i8_f64_hash_map = struct {
    pub const I8F64HashMap = HashMap(i8, f64);
};
pub const i8_i8_hash_map = struct {
    pub const I8I8HashMap = HashMap(i8, i8);
};
pub const i8_i16_hash_map = struct {
    pub const I8I16HashMap = HashMap(i8, i16);
};
pub const i8_i32_hash_map = struct {
    pub const I8I32HashMap = HashMap(i8, i32);
};
pub const i8_i64_hash_map = struct {
    pub const I8I64HashMap = HashMap(i8, i64);
};
pub const i16_bool_hash_map = struct {
    pub const I16BoolHashMap = HashMap(i16, bool);
};
pub const i16_char_hash_map = struct {
    pub const I16CharHashMap = HashMap(i16, u21);
};
pub const i16_f32_hash_map = struct {
    pub const I16F32HashMap = HashMap(i16, f32);
};
pub const i16_f64_hash_map = struct {
    pub const I16F64HashMap = HashMap(i16, f64);
};
pub const i16_i8_hash_map = struct {
    pub const I16I8HashMap = HashMap(i16, i8);
};
pub const i16_i16_hash_map = struct {
    pub const I16I16HashMap = HashMap(i16, i16);
};
pub const i16_i32_hash_map = struct {
    pub const I16I32HashMap = HashMap(i16, i32);
};
pub const i16_i64_hash_map = struct {
    pub const I16I64HashMap = HashMap(i16, i64);
};
pub const i32_bool_hash_map = struct {
    pub const I32BoolHashMap = HashMap(i32, bool);
};
pub const i32_char_hash_map = struct {
    pub const I32CharHashMap = HashMap(i32, u21);
};
pub const i32_f32_hash_map = struct {
    pub const I32F32HashMap = HashMap(i32, f32);
};
pub const i32_f64_hash_map = struct {
    pub const I32F64HashMap = HashMap(i32, f64);
};
pub const i32_i8_hash_map = struct {
    pub const I32I8HashMap = HashMap(i32, i8);
};
pub const i32_i16_hash_map = struct {
    pub const I32I16HashMap = HashMap(i32, i16);
};
pub const i32_i32_hash_map = struct {
    pub const I32I32HashMap = HashMap(i32, i32);
};
pub const i32_i64_hash_map = struct {
    pub const I32I64HashMap = HashMap(i32, i64);
};
pub const i64_bool_hash_map = struct {
    pub const I64BoolHashMap = HashMap(i64, bool);
};
pub const i64_char_hash_map = struct {
    pub const I64CharHashMap = HashMap(i64, u21);
};
pub const i64_f32_hash_map = struct {
    pub const I64F32HashMap = HashMap(i64, f32);
};
pub const i64_f64_hash_map = struct {
    pub const I64F64HashMap = HashMap(i64, f64);
};
pub const i64_i8_hash_map = struct {
    pub const I64I8HashMap = HashMap(i64, i8);
};
pub const i64_i16_hash_map = struct {
    pub const I64I16HashMap = HashMap(i64, i16);
};
pub const i64_i32_hash_map = struct {
    pub const I64I32HashMap = HashMap(i64, i32);
};
pub const i64_i64_hash_map = struct {
    pub const I64I64HashMap = HashMap(i64, i64);
};

pub const bool_bool_hash_bi_map = struct {
    pub const BoolBoolHashBiMap = HashBiMap(bool, bool);
};
pub const bool_char_hash_bi_map = struct {
    pub const BoolCharHashBiMap = HashBiMap(bool, u21);
};
pub const bool_f32_hash_bi_map = struct {
    pub const BoolF32HashBiMap = HashBiMap(bool, f32);
};
pub const bool_f64_hash_bi_map = struct {
    pub const BoolF64HashBiMap = HashBiMap(bool, f64);
};
pub const bool_i8_hash_bi_map = struct {
    pub const BoolI8HashBiMap = HashBiMap(bool, i8);
};
pub const bool_i16_hash_bi_map = struct {
    pub const BoolI16HashBiMap = HashBiMap(bool, i16);
};
pub const bool_i32_hash_bi_map = struct {
    pub const BoolI32HashBiMap = HashBiMap(bool, i32);
};
pub const bool_i64_hash_bi_map = struct {
    pub const BoolI64HashBiMap = HashBiMap(bool, i64);
};
pub const char_bool_hash_bi_map = struct {
    pub const CharBoolHashBiMap = HashBiMap(u21, bool);
};
pub const char_char_hash_bi_map = struct {
    pub const CharCharHashBiMap = HashBiMap(u21, u21);
};
pub const char_f32_hash_bi_map = struct {
    pub const CharF32HashBiMap = HashBiMap(u21, f32);
};
pub const char_f64_hash_bi_map = struct {
    pub const CharF64HashBiMap = HashBiMap(u21, f64);
};
pub const char_i8_hash_bi_map = struct {
    pub const CharI8HashBiMap = HashBiMap(u21, i8);
};
pub const char_i16_hash_bi_map = struct {
    pub const CharI16HashBiMap = HashBiMap(u21, i16);
};
pub const char_i32_hash_bi_map = struct {
    pub const CharI32HashBiMap = HashBiMap(u21, i32);
};
pub const char_i64_hash_bi_map = struct {
    pub const CharI64HashBiMap = HashBiMap(u21, i64);
};
pub const f32_bool_hash_bi_map = struct {
    pub const F32BoolHashBiMap = HashBiMap(f32, bool);
};
pub const f32_char_hash_bi_map = struct {
    pub const F32CharHashBiMap = HashBiMap(f32, u21);
};
pub const f32_f32_hash_bi_map = struct {
    pub const F32F32HashBiMap = HashBiMap(f32, f32);
};
pub const f32_f64_hash_bi_map = struct {
    pub const F32F64HashBiMap = HashBiMap(f32, f64);
};
pub const f32_i8_hash_bi_map = struct {
    pub const F32I8HashBiMap = HashBiMap(f32, i8);
};
pub const f32_i16_hash_bi_map = struct {
    pub const F32I16HashBiMap = HashBiMap(f32, i16);
};
pub const f32_i32_hash_bi_map = struct {
    pub const F32I32HashBiMap = HashBiMap(f32, i32);
};
pub const f32_i64_hash_bi_map = struct {
    pub const F32I64HashBiMap = HashBiMap(f32, i64);
};
pub const f64_bool_hash_bi_map = struct {
    pub const F64BoolHashBiMap = HashBiMap(f64, bool);
};
pub const f64_char_hash_bi_map = struct {
    pub const F64CharHashBiMap = HashBiMap(f64, u21);
};
pub const f64_f32_hash_bi_map = struct {
    pub const F64F32HashBiMap = HashBiMap(f64, f32);
};
pub const f64_f64_hash_bi_map = struct {
    pub const F64F64HashBiMap = HashBiMap(f64, f64);
};
pub const f64_i8_hash_bi_map = struct {
    pub const F64I8HashBiMap = HashBiMap(f64, i8);
};
pub const f64_i16_hash_bi_map = struct {
    pub const F64I16HashBiMap = HashBiMap(f64, i16);
};
pub const f64_i32_hash_bi_map = struct {
    pub const F64I32HashBiMap = HashBiMap(f64, i32);
};
pub const f64_i64_hash_bi_map = struct {
    pub const F64I64HashBiMap = HashBiMap(f64, i64);
};
pub const i8_bool_hash_bi_map = struct {
    pub const I8BoolHashBiMap = HashBiMap(i8, bool);
};
pub const i8_char_hash_bi_map = struct {
    pub const I8CharHashBiMap = HashBiMap(i8, u21);
};
pub const i8_f32_hash_bi_map = struct {
    pub const I8F32HashBiMap = HashBiMap(i8, f32);
};
pub const i8_f64_hash_bi_map = struct {
    pub const I8F64HashBiMap = HashBiMap(i8, f64);
};
pub const i8_i8_hash_bi_map = struct {
    pub const I8I8HashBiMap = HashBiMap(i8, i8);
};
pub const i8_i16_hash_bi_map = struct {
    pub const I8I16HashBiMap = HashBiMap(i8, i16);
};
pub const i8_i32_hash_bi_map = struct {
    pub const I8I32HashBiMap = HashBiMap(i8, i32);
};
pub const i8_i64_hash_bi_map = struct {
    pub const I8I64HashBiMap = HashBiMap(i8, i64);
};
pub const i16_bool_hash_bi_map = struct {
    pub const I16BoolHashBiMap = HashBiMap(i16, bool);
};
pub const i16_char_hash_bi_map = struct {
    pub const I16CharHashBiMap = HashBiMap(i16, u21);
};
pub const i16_f32_hash_bi_map = struct {
    pub const I16F32HashBiMap = HashBiMap(i16, f32);
};
pub const i16_f64_hash_bi_map = struct {
    pub const I16F64HashBiMap = HashBiMap(i16, f64);
};
pub const i16_i8_hash_bi_map = struct {
    pub const I16I8HashBiMap = HashBiMap(i16, i8);
};
pub const i16_i16_hash_bi_map = struct {
    pub const I16I16HashBiMap = HashBiMap(i16, i16);
};
pub const i16_i32_hash_bi_map = struct {
    pub const I16I32HashBiMap = HashBiMap(i16, i32);
};
pub const i16_i64_hash_bi_map = struct {
    pub const I16I64HashBiMap = HashBiMap(i16, i64);
};
pub const i32_bool_hash_bi_map = struct {
    pub const I32BoolHashBiMap = HashBiMap(i32, bool);
};
pub const i32_char_hash_bi_map = struct {
    pub const I32CharHashBiMap = HashBiMap(i32, u21);
};
pub const i32_f32_hash_bi_map = struct {
    pub const I32F32HashBiMap = HashBiMap(i32, f32);
};
pub const i32_f64_hash_bi_map = struct {
    pub const I32F64HashBiMap = HashBiMap(i32, f64);
};
pub const i32_i8_hash_bi_map = struct {
    pub const I32I8HashBiMap = HashBiMap(i32, i8);
};
pub const i32_i16_hash_bi_map = struct {
    pub const I32I16HashBiMap = HashBiMap(i32, i16);
};
pub const i32_i32_hash_bi_map = struct {
    pub const I32I32HashBiMap = HashBiMap(i32, i32);
};
pub const i32_i64_hash_bi_map = struct {
    pub const I32I64HashBiMap = HashBiMap(i32, i64);
};
pub const i64_bool_hash_bi_map = struct {
    pub const I64BoolHashBiMap = HashBiMap(i64, bool);
};
pub const i64_char_hash_bi_map = struct {
    pub const I64CharHashBiMap = HashBiMap(i64, u21);
};
pub const i64_f32_hash_bi_map = struct {
    pub const I64F32HashBiMap = HashBiMap(i64, f32);
};
pub const i64_f64_hash_bi_map = struct {
    pub const I64F64HashBiMap = HashBiMap(i64, f64);
};
pub const i64_i8_hash_bi_map = struct {
    pub const I64I8HashBiMap = HashBiMap(i64, i8);
};
pub const i64_i16_hash_bi_map = struct {
    pub const I64I16HashBiMap = HashBiMap(i64, i16);
};
pub const i64_i32_hash_bi_map = struct {
    pub const I64I32HashBiMap = HashBiMap(i64, i32);
};
pub const i64_i64_hash_bi_map = struct {
    pub const I64I64HashBiMap = HashBiMap(i64, i64);
};

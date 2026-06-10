// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic multimap types.
//!
//! `ListMultimap(K, V)` and `SetMultimap(K, V)` are single-source generics.
//! This module exposes the named `<K><V>ListMultimap` / `<K><V>SetMultimap`
//! aliases that the rest of the project (and the cross-language validate
//! harness) consume, and preserves the historical per-file lowercase
//! namespaces for backward compatibility (e.g.
//! `multimap.i32_i32_list_multimap.I32I32ListMultimap`).

pub const ListMultimap = @import("list_multimap.zig").ListMultimap;
pub const SetMultimap = @import("set_multimap.zig").SetMultimap;

// ---- Named list multimap aliases ----

pub const BoolBoolListMultimap = ListMultimap(bool, bool);
pub const BoolCharListMultimap = ListMultimap(bool, u21);
pub const BoolF32ListMultimap = ListMultimap(bool, f32);
pub const BoolF64ListMultimap = ListMultimap(bool, f64);
pub const BoolI8ListMultimap = ListMultimap(bool, i8);
pub const BoolI16ListMultimap = ListMultimap(bool, i16);
pub const BoolI32ListMultimap = ListMultimap(bool, i32);
pub const BoolI64ListMultimap = ListMultimap(bool, i64);
pub const CharBoolListMultimap = ListMultimap(u21, bool);
pub const CharCharListMultimap = ListMultimap(u21, u21);
pub const CharF32ListMultimap = ListMultimap(u21, f32);
pub const CharF64ListMultimap = ListMultimap(u21, f64);
pub const CharI8ListMultimap = ListMultimap(u21, i8);
pub const CharI16ListMultimap = ListMultimap(u21, i16);
pub const CharI32ListMultimap = ListMultimap(u21, i32);
pub const CharI64ListMultimap = ListMultimap(u21, i64);
pub const F32BoolListMultimap = ListMultimap(f32, bool);
pub const F32CharListMultimap = ListMultimap(f32, u21);
pub const F32F32ListMultimap = ListMultimap(f32, f32);
pub const F32F64ListMultimap = ListMultimap(f32, f64);
pub const F32I8ListMultimap = ListMultimap(f32, i8);
pub const F32I16ListMultimap = ListMultimap(f32, i16);
pub const F32I32ListMultimap = ListMultimap(f32, i32);
pub const F32I64ListMultimap = ListMultimap(f32, i64);
pub const F64BoolListMultimap = ListMultimap(f64, bool);
pub const F64CharListMultimap = ListMultimap(f64, u21);
pub const F64F32ListMultimap = ListMultimap(f64, f32);
pub const F64F64ListMultimap = ListMultimap(f64, f64);
pub const F64I8ListMultimap = ListMultimap(f64, i8);
pub const F64I16ListMultimap = ListMultimap(f64, i16);
pub const F64I32ListMultimap = ListMultimap(f64, i32);
pub const F64I64ListMultimap = ListMultimap(f64, i64);
pub const I8BoolListMultimap = ListMultimap(i8, bool);
pub const I8CharListMultimap = ListMultimap(i8, u21);
pub const I8F32ListMultimap = ListMultimap(i8, f32);
pub const I8F64ListMultimap = ListMultimap(i8, f64);
pub const I8I8ListMultimap = ListMultimap(i8, i8);
pub const I8I16ListMultimap = ListMultimap(i8, i16);
pub const I8I32ListMultimap = ListMultimap(i8, i32);
pub const I8I64ListMultimap = ListMultimap(i8, i64);
pub const I16BoolListMultimap = ListMultimap(i16, bool);
pub const I16CharListMultimap = ListMultimap(i16, u21);
pub const I16F32ListMultimap = ListMultimap(i16, f32);
pub const I16F64ListMultimap = ListMultimap(i16, f64);
pub const I16I8ListMultimap = ListMultimap(i16, i8);
pub const I16I16ListMultimap = ListMultimap(i16, i16);
pub const I16I32ListMultimap = ListMultimap(i16, i32);
pub const I16I64ListMultimap = ListMultimap(i16, i64);
pub const I32BoolListMultimap = ListMultimap(i32, bool);
pub const I32CharListMultimap = ListMultimap(i32, u21);
pub const I32F32ListMultimap = ListMultimap(i32, f32);
pub const I32F64ListMultimap = ListMultimap(i32, f64);
pub const I32I8ListMultimap = ListMultimap(i32, i8);
pub const I32I16ListMultimap = ListMultimap(i32, i16);
pub const I32I32ListMultimap = ListMultimap(i32, i32);
pub const I32I64ListMultimap = ListMultimap(i32, i64);
pub const I64BoolListMultimap = ListMultimap(i64, bool);
pub const I64CharListMultimap = ListMultimap(i64, u21);
pub const I64F32ListMultimap = ListMultimap(i64, f32);
pub const I64F64ListMultimap = ListMultimap(i64, f64);
pub const I64I8ListMultimap = ListMultimap(i64, i8);
pub const I64I16ListMultimap = ListMultimap(i64, i16);
pub const I64I32ListMultimap = ListMultimap(i64, i32);
pub const I64I64ListMultimap = ListMultimap(i64, i64);

// ---- Named set multimap aliases ----

pub const BoolBoolSetMultimap = SetMultimap(bool, bool);
pub const BoolCharSetMultimap = SetMultimap(bool, u21);
pub const BoolF32SetMultimap = SetMultimap(bool, f32);
pub const BoolF64SetMultimap = SetMultimap(bool, f64);
pub const BoolI8SetMultimap = SetMultimap(bool, i8);
pub const BoolI16SetMultimap = SetMultimap(bool, i16);
pub const BoolI32SetMultimap = SetMultimap(bool, i32);
pub const BoolI64SetMultimap = SetMultimap(bool, i64);
pub const CharBoolSetMultimap = SetMultimap(u21, bool);
pub const CharCharSetMultimap = SetMultimap(u21, u21);
pub const CharF32SetMultimap = SetMultimap(u21, f32);
pub const CharF64SetMultimap = SetMultimap(u21, f64);
pub const CharI8SetMultimap = SetMultimap(u21, i8);
pub const CharI16SetMultimap = SetMultimap(u21, i16);
pub const CharI32SetMultimap = SetMultimap(u21, i32);
pub const CharI64SetMultimap = SetMultimap(u21, i64);
pub const F32BoolSetMultimap = SetMultimap(f32, bool);
pub const F32CharSetMultimap = SetMultimap(f32, u21);
pub const F32F32SetMultimap = SetMultimap(f32, f32);
pub const F32F64SetMultimap = SetMultimap(f32, f64);
pub const F32I8SetMultimap = SetMultimap(f32, i8);
pub const F32I16SetMultimap = SetMultimap(f32, i16);
pub const F32I32SetMultimap = SetMultimap(f32, i32);
pub const F32I64SetMultimap = SetMultimap(f32, i64);
pub const F64BoolSetMultimap = SetMultimap(f64, bool);
pub const F64CharSetMultimap = SetMultimap(f64, u21);
pub const F64F32SetMultimap = SetMultimap(f64, f32);
pub const F64F64SetMultimap = SetMultimap(f64, f64);
pub const F64I8SetMultimap = SetMultimap(f64, i8);
pub const F64I16SetMultimap = SetMultimap(f64, i16);
pub const F64I32SetMultimap = SetMultimap(f64, i32);
pub const F64I64SetMultimap = SetMultimap(f64, i64);
pub const I8BoolSetMultimap = SetMultimap(i8, bool);
pub const I8CharSetMultimap = SetMultimap(i8, u21);
pub const I8F32SetMultimap = SetMultimap(i8, f32);
pub const I8F64SetMultimap = SetMultimap(i8, f64);
pub const I8I8SetMultimap = SetMultimap(i8, i8);
pub const I8I16SetMultimap = SetMultimap(i8, i16);
pub const I8I32SetMultimap = SetMultimap(i8, i32);
pub const I8I64SetMultimap = SetMultimap(i8, i64);
pub const I16BoolSetMultimap = SetMultimap(i16, bool);
pub const I16CharSetMultimap = SetMultimap(i16, u21);
pub const I16F32SetMultimap = SetMultimap(i16, f32);
pub const I16F64SetMultimap = SetMultimap(i16, f64);
pub const I16I8SetMultimap = SetMultimap(i16, i8);
pub const I16I16SetMultimap = SetMultimap(i16, i16);
pub const I16I32SetMultimap = SetMultimap(i16, i32);
pub const I16I64SetMultimap = SetMultimap(i16, i64);
pub const I32BoolSetMultimap = SetMultimap(i32, bool);
pub const I32CharSetMultimap = SetMultimap(i32, u21);
pub const I32F32SetMultimap = SetMultimap(i32, f32);
pub const I32F64SetMultimap = SetMultimap(i32, f64);
pub const I32I8SetMultimap = SetMultimap(i32, i8);
pub const I32I16SetMultimap = SetMultimap(i32, i16);
pub const I32I32SetMultimap = SetMultimap(i32, i32);
pub const I32I64SetMultimap = SetMultimap(i32, i64);
pub const I64BoolSetMultimap = SetMultimap(i64, bool);
pub const I64CharSetMultimap = SetMultimap(i64, u21);
pub const I64F32SetMultimap = SetMultimap(i64, f32);
pub const I64F64SetMultimap = SetMultimap(i64, f64);
pub const I64I8SetMultimap = SetMultimap(i64, i8);
pub const I64I16SetMultimap = SetMultimap(i64, i16);
pub const I64I32SetMultimap = SetMultimap(i64, i32);
pub const I64I64SetMultimap = SetMultimap(i64, i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_bool_list_multimap = struct {
    pub const BoolBoolListMultimap = ListMultimap(bool, bool);
};
pub const bool_char_list_multimap = struct {
    pub const BoolCharListMultimap = ListMultimap(bool, u21);
};
pub const bool_f32_list_multimap = struct {
    pub const BoolF32ListMultimap = ListMultimap(bool, f32);
};
pub const bool_f64_list_multimap = struct {
    pub const BoolF64ListMultimap = ListMultimap(bool, f64);
};
pub const bool_i8_list_multimap = struct {
    pub const BoolI8ListMultimap = ListMultimap(bool, i8);
};
pub const bool_i16_list_multimap = struct {
    pub const BoolI16ListMultimap = ListMultimap(bool, i16);
};
pub const bool_i32_list_multimap = struct {
    pub const BoolI32ListMultimap = ListMultimap(bool, i32);
};
pub const bool_i64_list_multimap = struct {
    pub const BoolI64ListMultimap = ListMultimap(bool, i64);
};
pub const char_bool_list_multimap = struct {
    pub const CharBoolListMultimap = ListMultimap(u21, bool);
};
pub const char_char_list_multimap = struct {
    pub const CharCharListMultimap = ListMultimap(u21, u21);
};
pub const char_f32_list_multimap = struct {
    pub const CharF32ListMultimap = ListMultimap(u21, f32);
};
pub const char_f64_list_multimap = struct {
    pub const CharF64ListMultimap = ListMultimap(u21, f64);
};
pub const char_i8_list_multimap = struct {
    pub const CharI8ListMultimap = ListMultimap(u21, i8);
};
pub const char_i16_list_multimap = struct {
    pub const CharI16ListMultimap = ListMultimap(u21, i16);
};
pub const char_i32_list_multimap = struct {
    pub const CharI32ListMultimap = ListMultimap(u21, i32);
};
pub const char_i64_list_multimap = struct {
    pub const CharI64ListMultimap = ListMultimap(u21, i64);
};
pub const f32_bool_list_multimap = struct {
    pub const F32BoolListMultimap = ListMultimap(f32, bool);
};
pub const f32_char_list_multimap = struct {
    pub const F32CharListMultimap = ListMultimap(f32, u21);
};
pub const f32_f32_list_multimap = struct {
    pub const F32F32ListMultimap = ListMultimap(f32, f32);
};
pub const f32_f64_list_multimap = struct {
    pub const F32F64ListMultimap = ListMultimap(f32, f64);
};
pub const f32_i8_list_multimap = struct {
    pub const F32I8ListMultimap = ListMultimap(f32, i8);
};
pub const f32_i16_list_multimap = struct {
    pub const F32I16ListMultimap = ListMultimap(f32, i16);
};
pub const f32_i32_list_multimap = struct {
    pub const F32I32ListMultimap = ListMultimap(f32, i32);
};
pub const f32_i64_list_multimap = struct {
    pub const F32I64ListMultimap = ListMultimap(f32, i64);
};
pub const f64_bool_list_multimap = struct {
    pub const F64BoolListMultimap = ListMultimap(f64, bool);
};
pub const f64_char_list_multimap = struct {
    pub const F64CharListMultimap = ListMultimap(f64, u21);
};
pub const f64_f32_list_multimap = struct {
    pub const F64F32ListMultimap = ListMultimap(f64, f32);
};
pub const f64_f64_list_multimap = struct {
    pub const F64F64ListMultimap = ListMultimap(f64, f64);
};
pub const f64_i8_list_multimap = struct {
    pub const F64I8ListMultimap = ListMultimap(f64, i8);
};
pub const f64_i16_list_multimap = struct {
    pub const F64I16ListMultimap = ListMultimap(f64, i16);
};
pub const f64_i32_list_multimap = struct {
    pub const F64I32ListMultimap = ListMultimap(f64, i32);
};
pub const f64_i64_list_multimap = struct {
    pub const F64I64ListMultimap = ListMultimap(f64, i64);
};
pub const i8_bool_list_multimap = struct {
    pub const I8BoolListMultimap = ListMultimap(i8, bool);
};
pub const i8_char_list_multimap = struct {
    pub const I8CharListMultimap = ListMultimap(i8, u21);
};
pub const i8_f32_list_multimap = struct {
    pub const I8F32ListMultimap = ListMultimap(i8, f32);
};
pub const i8_f64_list_multimap = struct {
    pub const I8F64ListMultimap = ListMultimap(i8, f64);
};
pub const i8_i8_list_multimap = struct {
    pub const I8I8ListMultimap = ListMultimap(i8, i8);
};
pub const i8_i16_list_multimap = struct {
    pub const I8I16ListMultimap = ListMultimap(i8, i16);
};
pub const i8_i32_list_multimap = struct {
    pub const I8I32ListMultimap = ListMultimap(i8, i32);
};
pub const i8_i64_list_multimap = struct {
    pub const I8I64ListMultimap = ListMultimap(i8, i64);
};
pub const i16_bool_list_multimap = struct {
    pub const I16BoolListMultimap = ListMultimap(i16, bool);
};
pub const i16_char_list_multimap = struct {
    pub const I16CharListMultimap = ListMultimap(i16, u21);
};
pub const i16_f32_list_multimap = struct {
    pub const I16F32ListMultimap = ListMultimap(i16, f32);
};
pub const i16_f64_list_multimap = struct {
    pub const I16F64ListMultimap = ListMultimap(i16, f64);
};
pub const i16_i8_list_multimap = struct {
    pub const I16I8ListMultimap = ListMultimap(i16, i8);
};
pub const i16_i16_list_multimap = struct {
    pub const I16I16ListMultimap = ListMultimap(i16, i16);
};
pub const i16_i32_list_multimap = struct {
    pub const I16I32ListMultimap = ListMultimap(i16, i32);
};
pub const i16_i64_list_multimap = struct {
    pub const I16I64ListMultimap = ListMultimap(i16, i64);
};
pub const i32_bool_list_multimap = struct {
    pub const I32BoolListMultimap = ListMultimap(i32, bool);
};
pub const i32_char_list_multimap = struct {
    pub const I32CharListMultimap = ListMultimap(i32, u21);
};
pub const i32_f32_list_multimap = struct {
    pub const I32F32ListMultimap = ListMultimap(i32, f32);
};
pub const i32_f64_list_multimap = struct {
    pub const I32F64ListMultimap = ListMultimap(i32, f64);
};
pub const i32_i8_list_multimap = struct {
    pub const I32I8ListMultimap = ListMultimap(i32, i8);
};
pub const i32_i16_list_multimap = struct {
    pub const I32I16ListMultimap = ListMultimap(i32, i16);
};
pub const i32_i32_list_multimap = struct {
    pub const I32I32ListMultimap = ListMultimap(i32, i32);
};
pub const i32_i64_list_multimap = struct {
    pub const I32I64ListMultimap = ListMultimap(i32, i64);
};
pub const i64_bool_list_multimap = struct {
    pub const I64BoolListMultimap = ListMultimap(i64, bool);
};
pub const i64_char_list_multimap = struct {
    pub const I64CharListMultimap = ListMultimap(i64, u21);
};
pub const i64_f32_list_multimap = struct {
    pub const I64F32ListMultimap = ListMultimap(i64, f32);
};
pub const i64_f64_list_multimap = struct {
    pub const I64F64ListMultimap = ListMultimap(i64, f64);
};
pub const i64_i8_list_multimap = struct {
    pub const I64I8ListMultimap = ListMultimap(i64, i8);
};
pub const i64_i16_list_multimap = struct {
    pub const I64I16ListMultimap = ListMultimap(i64, i16);
};
pub const i64_i32_list_multimap = struct {
    pub const I64I32ListMultimap = ListMultimap(i64, i32);
};
pub const i64_i64_list_multimap = struct {
    pub const I64I64ListMultimap = ListMultimap(i64, i64);
};
pub const bool_bool_set_multimap = struct {
    pub const BoolBoolSetMultimap = SetMultimap(bool, bool);
};
pub const bool_char_set_multimap = struct {
    pub const BoolCharSetMultimap = SetMultimap(bool, u21);
};
pub const bool_f32_set_multimap = struct {
    pub const BoolF32SetMultimap = SetMultimap(bool, f32);
};
pub const bool_f64_set_multimap = struct {
    pub const BoolF64SetMultimap = SetMultimap(bool, f64);
};
pub const bool_i8_set_multimap = struct {
    pub const BoolI8SetMultimap = SetMultimap(bool, i8);
};
pub const bool_i16_set_multimap = struct {
    pub const BoolI16SetMultimap = SetMultimap(bool, i16);
};
pub const bool_i32_set_multimap = struct {
    pub const BoolI32SetMultimap = SetMultimap(bool, i32);
};
pub const bool_i64_set_multimap = struct {
    pub const BoolI64SetMultimap = SetMultimap(bool, i64);
};
pub const char_bool_set_multimap = struct {
    pub const CharBoolSetMultimap = SetMultimap(u21, bool);
};
pub const char_char_set_multimap = struct {
    pub const CharCharSetMultimap = SetMultimap(u21, u21);
};
pub const char_f32_set_multimap = struct {
    pub const CharF32SetMultimap = SetMultimap(u21, f32);
};
pub const char_f64_set_multimap = struct {
    pub const CharF64SetMultimap = SetMultimap(u21, f64);
};
pub const char_i8_set_multimap = struct {
    pub const CharI8SetMultimap = SetMultimap(u21, i8);
};
pub const char_i16_set_multimap = struct {
    pub const CharI16SetMultimap = SetMultimap(u21, i16);
};
pub const char_i32_set_multimap = struct {
    pub const CharI32SetMultimap = SetMultimap(u21, i32);
};
pub const char_i64_set_multimap = struct {
    pub const CharI64SetMultimap = SetMultimap(u21, i64);
};
pub const f32_bool_set_multimap = struct {
    pub const F32BoolSetMultimap = SetMultimap(f32, bool);
};
pub const f32_char_set_multimap = struct {
    pub const F32CharSetMultimap = SetMultimap(f32, u21);
};
pub const f32_f32_set_multimap = struct {
    pub const F32F32SetMultimap = SetMultimap(f32, f32);
};
pub const f32_f64_set_multimap = struct {
    pub const F32F64SetMultimap = SetMultimap(f32, f64);
};
pub const f32_i8_set_multimap = struct {
    pub const F32I8SetMultimap = SetMultimap(f32, i8);
};
pub const f32_i16_set_multimap = struct {
    pub const F32I16SetMultimap = SetMultimap(f32, i16);
};
pub const f32_i32_set_multimap = struct {
    pub const F32I32SetMultimap = SetMultimap(f32, i32);
};
pub const f32_i64_set_multimap = struct {
    pub const F32I64SetMultimap = SetMultimap(f32, i64);
};
pub const f64_bool_set_multimap = struct {
    pub const F64BoolSetMultimap = SetMultimap(f64, bool);
};
pub const f64_char_set_multimap = struct {
    pub const F64CharSetMultimap = SetMultimap(f64, u21);
};
pub const f64_f32_set_multimap = struct {
    pub const F64F32SetMultimap = SetMultimap(f64, f32);
};
pub const f64_f64_set_multimap = struct {
    pub const F64F64SetMultimap = SetMultimap(f64, f64);
};
pub const f64_i8_set_multimap = struct {
    pub const F64I8SetMultimap = SetMultimap(f64, i8);
};
pub const f64_i16_set_multimap = struct {
    pub const F64I16SetMultimap = SetMultimap(f64, i16);
};
pub const f64_i32_set_multimap = struct {
    pub const F64I32SetMultimap = SetMultimap(f64, i32);
};
pub const f64_i64_set_multimap = struct {
    pub const F64I64SetMultimap = SetMultimap(f64, i64);
};
pub const i8_bool_set_multimap = struct {
    pub const I8BoolSetMultimap = SetMultimap(i8, bool);
};
pub const i8_char_set_multimap = struct {
    pub const I8CharSetMultimap = SetMultimap(i8, u21);
};
pub const i8_f32_set_multimap = struct {
    pub const I8F32SetMultimap = SetMultimap(i8, f32);
};
pub const i8_f64_set_multimap = struct {
    pub const I8F64SetMultimap = SetMultimap(i8, f64);
};
pub const i8_i8_set_multimap = struct {
    pub const I8I8SetMultimap = SetMultimap(i8, i8);
};
pub const i8_i16_set_multimap = struct {
    pub const I8I16SetMultimap = SetMultimap(i8, i16);
};
pub const i8_i32_set_multimap = struct {
    pub const I8I32SetMultimap = SetMultimap(i8, i32);
};
pub const i8_i64_set_multimap = struct {
    pub const I8I64SetMultimap = SetMultimap(i8, i64);
};
pub const i16_bool_set_multimap = struct {
    pub const I16BoolSetMultimap = SetMultimap(i16, bool);
};
pub const i16_char_set_multimap = struct {
    pub const I16CharSetMultimap = SetMultimap(i16, u21);
};
pub const i16_f32_set_multimap = struct {
    pub const I16F32SetMultimap = SetMultimap(i16, f32);
};
pub const i16_f64_set_multimap = struct {
    pub const I16F64SetMultimap = SetMultimap(i16, f64);
};
pub const i16_i8_set_multimap = struct {
    pub const I16I8SetMultimap = SetMultimap(i16, i8);
};
pub const i16_i16_set_multimap = struct {
    pub const I16I16SetMultimap = SetMultimap(i16, i16);
};
pub const i16_i32_set_multimap = struct {
    pub const I16I32SetMultimap = SetMultimap(i16, i32);
};
pub const i16_i64_set_multimap = struct {
    pub const I16I64SetMultimap = SetMultimap(i16, i64);
};
pub const i32_bool_set_multimap = struct {
    pub const I32BoolSetMultimap = SetMultimap(i32, bool);
};
pub const i32_char_set_multimap = struct {
    pub const I32CharSetMultimap = SetMultimap(i32, u21);
};
pub const i32_f32_set_multimap = struct {
    pub const I32F32SetMultimap = SetMultimap(i32, f32);
};
pub const i32_f64_set_multimap = struct {
    pub const I32F64SetMultimap = SetMultimap(i32, f64);
};
pub const i32_i8_set_multimap = struct {
    pub const I32I8SetMultimap = SetMultimap(i32, i8);
};
pub const i32_i16_set_multimap = struct {
    pub const I32I16SetMultimap = SetMultimap(i32, i16);
};
pub const i32_i32_set_multimap = struct {
    pub const I32I32SetMultimap = SetMultimap(i32, i32);
};
pub const i32_i64_set_multimap = struct {
    pub const I32I64SetMultimap = SetMultimap(i32, i64);
};
pub const i64_bool_set_multimap = struct {
    pub const I64BoolSetMultimap = SetMultimap(i64, bool);
};
pub const i64_char_set_multimap = struct {
    pub const I64CharSetMultimap = SetMultimap(i64, u21);
};
pub const i64_f32_set_multimap = struct {
    pub const I64F32SetMultimap = SetMultimap(i64, f32);
};
pub const i64_f64_set_multimap = struct {
    pub const I64F64SetMultimap = SetMultimap(i64, f64);
};
pub const i64_i8_set_multimap = struct {
    pub const I64I8SetMultimap = SetMultimap(i64, i8);
};
pub const i64_i16_set_multimap = struct {
    pub const I64I16SetMultimap = SetMultimap(i64, i16);
};
pub const i64_i32_set_multimap = struct {
    pub const I64I32SetMultimap = SetMultimap(i64, i32);
};
pub const i64_i64_set_multimap = struct {
    pub const I64I64SetMultimap = SetMultimap(i64, i64);
};

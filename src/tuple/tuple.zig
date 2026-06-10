// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic immutable pair type.
//!
//! `Pair(A, B)` is a single-source generic (see pair.zig) replacing the 64
//! per-type `<K><V>Pair` wrappers. This module exposes the named `<A><B>Pair`
//! aliases the rest of the project consumes, and preserves the historical
//! per-file lowercase namespaces for backward compatibility (e.g.
//! `tuple.i32_i32_pair.I32I32Pair`). `swap()` returns the transposed alias,
//! which comptime memoization resolves to the matching `<B><A>Pair`.

pub const Pair = @import("pair.zig").Pair;

// ---- Named pair aliases ----

pub const BoolBoolPair = Pair(bool, bool);
pub const BoolCharPair = Pair(bool, u21);
pub const BoolF32Pair = Pair(bool, f32);
pub const BoolF64Pair = Pair(bool, f64);
pub const BoolI8Pair = Pair(bool, i8);
pub const BoolI16Pair = Pair(bool, i16);
pub const BoolI32Pair = Pair(bool, i32);
pub const BoolI64Pair = Pair(bool, i64);
pub const CharBoolPair = Pair(u21, bool);
pub const CharCharPair = Pair(u21, u21);
pub const CharF32Pair = Pair(u21, f32);
pub const CharF64Pair = Pair(u21, f64);
pub const CharI8Pair = Pair(u21, i8);
pub const CharI16Pair = Pair(u21, i16);
pub const CharI32Pair = Pair(u21, i32);
pub const CharI64Pair = Pair(u21, i64);
pub const F32BoolPair = Pair(f32, bool);
pub const F32CharPair = Pair(f32, u21);
pub const F32F32Pair = Pair(f32, f32);
pub const F32F64Pair = Pair(f32, f64);
pub const F32I8Pair = Pair(f32, i8);
pub const F32I16Pair = Pair(f32, i16);
pub const F32I32Pair = Pair(f32, i32);
pub const F32I64Pair = Pair(f32, i64);
pub const F64BoolPair = Pair(f64, bool);
pub const F64CharPair = Pair(f64, u21);
pub const F64F32Pair = Pair(f64, f32);
pub const F64F64Pair = Pair(f64, f64);
pub const F64I8Pair = Pair(f64, i8);
pub const F64I16Pair = Pair(f64, i16);
pub const F64I32Pair = Pair(f64, i32);
pub const F64I64Pair = Pair(f64, i64);
pub const I8BoolPair = Pair(i8, bool);
pub const I8CharPair = Pair(i8, u21);
pub const I8F32Pair = Pair(i8, f32);
pub const I8F64Pair = Pair(i8, f64);
pub const I8I8Pair = Pair(i8, i8);
pub const I8I16Pair = Pair(i8, i16);
pub const I8I32Pair = Pair(i8, i32);
pub const I8I64Pair = Pair(i8, i64);
pub const I16BoolPair = Pair(i16, bool);
pub const I16CharPair = Pair(i16, u21);
pub const I16F32Pair = Pair(i16, f32);
pub const I16F64Pair = Pair(i16, f64);
pub const I16I8Pair = Pair(i16, i8);
pub const I16I16Pair = Pair(i16, i16);
pub const I16I32Pair = Pair(i16, i32);
pub const I16I64Pair = Pair(i16, i64);
pub const I32BoolPair = Pair(i32, bool);
pub const I32CharPair = Pair(i32, u21);
pub const I32F32Pair = Pair(i32, f32);
pub const I32F64Pair = Pair(i32, f64);
pub const I32I8Pair = Pair(i32, i8);
pub const I32I16Pair = Pair(i32, i16);
pub const I32I32Pair = Pair(i32, i32);
pub const I32I64Pair = Pair(i32, i64);
pub const I64BoolPair = Pair(i64, bool);
pub const I64CharPair = Pair(i64, u21);
pub const I64F32Pair = Pair(i64, f32);
pub const I64F64Pair = Pair(i64, f64);
pub const I64I8Pair = Pair(i64, i8);
pub const I64I16Pair = Pair(i64, i16);
pub const I64I32Pair = Pair(i64, i32);
pub const I64I64Pair = Pair(i64, i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_bool_pair = struct {
    pub const BoolBoolPair = Pair(bool, bool);
};
pub const bool_char_pair = struct {
    pub const BoolCharPair = Pair(bool, u21);
};
pub const bool_f32_pair = struct {
    pub const BoolF32Pair = Pair(bool, f32);
};
pub const bool_f64_pair = struct {
    pub const BoolF64Pair = Pair(bool, f64);
};
pub const bool_i8_pair = struct {
    pub const BoolI8Pair = Pair(bool, i8);
};
pub const bool_i16_pair = struct {
    pub const BoolI16Pair = Pair(bool, i16);
};
pub const bool_i32_pair = struct {
    pub const BoolI32Pair = Pair(bool, i32);
};
pub const bool_i64_pair = struct {
    pub const BoolI64Pair = Pair(bool, i64);
};
pub const char_bool_pair = struct {
    pub const CharBoolPair = Pair(u21, bool);
};
pub const char_char_pair = struct {
    pub const CharCharPair = Pair(u21, u21);
};
pub const char_f32_pair = struct {
    pub const CharF32Pair = Pair(u21, f32);
};
pub const char_f64_pair = struct {
    pub const CharF64Pair = Pair(u21, f64);
};
pub const char_i8_pair = struct {
    pub const CharI8Pair = Pair(u21, i8);
};
pub const char_i16_pair = struct {
    pub const CharI16Pair = Pair(u21, i16);
};
pub const char_i32_pair = struct {
    pub const CharI32Pair = Pair(u21, i32);
};
pub const char_i64_pair = struct {
    pub const CharI64Pair = Pair(u21, i64);
};
pub const f32_bool_pair = struct {
    pub const F32BoolPair = Pair(f32, bool);
};
pub const f32_char_pair = struct {
    pub const F32CharPair = Pair(f32, u21);
};
pub const f32_f32_pair = struct {
    pub const F32F32Pair = Pair(f32, f32);
};
pub const f32_f64_pair = struct {
    pub const F32F64Pair = Pair(f32, f64);
};
pub const f32_i8_pair = struct {
    pub const F32I8Pair = Pair(f32, i8);
};
pub const f32_i16_pair = struct {
    pub const F32I16Pair = Pair(f32, i16);
};
pub const f32_i32_pair = struct {
    pub const F32I32Pair = Pair(f32, i32);
};
pub const f32_i64_pair = struct {
    pub const F32I64Pair = Pair(f32, i64);
};
pub const f64_bool_pair = struct {
    pub const F64BoolPair = Pair(f64, bool);
};
pub const f64_char_pair = struct {
    pub const F64CharPair = Pair(f64, u21);
};
pub const f64_f32_pair = struct {
    pub const F64F32Pair = Pair(f64, f32);
};
pub const f64_f64_pair = struct {
    pub const F64F64Pair = Pair(f64, f64);
};
pub const f64_i8_pair = struct {
    pub const F64I8Pair = Pair(f64, i8);
};
pub const f64_i16_pair = struct {
    pub const F64I16Pair = Pair(f64, i16);
};
pub const f64_i32_pair = struct {
    pub const F64I32Pair = Pair(f64, i32);
};
pub const f64_i64_pair = struct {
    pub const F64I64Pair = Pair(f64, i64);
};
pub const i8_bool_pair = struct {
    pub const I8BoolPair = Pair(i8, bool);
};
pub const i8_char_pair = struct {
    pub const I8CharPair = Pair(i8, u21);
};
pub const i8_f32_pair = struct {
    pub const I8F32Pair = Pair(i8, f32);
};
pub const i8_f64_pair = struct {
    pub const I8F64Pair = Pair(i8, f64);
};
pub const i8_i8_pair = struct {
    pub const I8I8Pair = Pair(i8, i8);
};
pub const i8_i16_pair = struct {
    pub const I8I16Pair = Pair(i8, i16);
};
pub const i8_i32_pair = struct {
    pub const I8I32Pair = Pair(i8, i32);
};
pub const i8_i64_pair = struct {
    pub const I8I64Pair = Pair(i8, i64);
};
pub const i16_bool_pair = struct {
    pub const I16BoolPair = Pair(i16, bool);
};
pub const i16_char_pair = struct {
    pub const I16CharPair = Pair(i16, u21);
};
pub const i16_f32_pair = struct {
    pub const I16F32Pair = Pair(i16, f32);
};
pub const i16_f64_pair = struct {
    pub const I16F64Pair = Pair(i16, f64);
};
pub const i16_i8_pair = struct {
    pub const I16I8Pair = Pair(i16, i8);
};
pub const i16_i16_pair = struct {
    pub const I16I16Pair = Pair(i16, i16);
};
pub const i16_i32_pair = struct {
    pub const I16I32Pair = Pair(i16, i32);
};
pub const i16_i64_pair = struct {
    pub const I16I64Pair = Pair(i16, i64);
};
pub const i32_bool_pair = struct {
    pub const I32BoolPair = Pair(i32, bool);
};
pub const i32_char_pair = struct {
    pub const I32CharPair = Pair(i32, u21);
};
pub const i32_f32_pair = struct {
    pub const I32F32Pair = Pair(i32, f32);
};
pub const i32_f64_pair = struct {
    pub const I32F64Pair = Pair(i32, f64);
};
pub const i32_i8_pair = struct {
    pub const I32I8Pair = Pair(i32, i8);
};
pub const i32_i16_pair = struct {
    pub const I32I16Pair = Pair(i32, i16);
};
pub const i32_i32_pair = struct {
    pub const I32I32Pair = Pair(i32, i32);
};
pub const i32_i64_pair = struct {
    pub const I32I64Pair = Pair(i32, i64);
};
pub const i64_bool_pair = struct {
    pub const I64BoolPair = Pair(i64, bool);
};
pub const i64_char_pair = struct {
    pub const I64CharPair = Pair(i64, u21);
};
pub const i64_f32_pair = struct {
    pub const I64F32Pair = Pair(i64, f32);
};
pub const i64_f64_pair = struct {
    pub const I64F64Pair = Pair(i64, f64);
};
pub const i64_i8_pair = struct {
    pub const I64I8Pair = Pair(i64, i8);
};
pub const i64_i16_pair = struct {
    pub const I64I16Pair = Pair(i64, i16);
};
pub const i64_i32_pair = struct {
    pub const I64I32Pair = Pair(i64, i32);
};
pub const i64_i64_pair = struct {
    pub const I64I64Pair = Pair(i64, i64);
};

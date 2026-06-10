// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the immutable collection types.
//!
//! Each shape is a single-source generic (`ImmutableHashMap(K, V)`,
//! `ImmutableArrayList(T)`, etc.). This module exposes the named
//! `Immutable<K><V>HashMap` / `Immutable<T><Shape>` aliases that the rest of
//! the project (and the cross-language validate harness) consume, and
//! preserves the historical per-file lowercase namespaces for backward
//! compatibility (e.g. `immutable.immutable_i32_i32_hash_map.ImmutableI32I32HashMap`).
//! `immutable_bit_set` is standalone (not type-specialized) and kept as-is.

pub const ImmutableHashMap = @import("immutable_hash_map.zig").ImmutableHashMap;
pub const ImmutableHashSet = @import("immutable_hash_set.zig").ImmutableHashSet;
pub const ImmutableHashBag = @import("immutable_hash_bag.zig").ImmutableHashBag;
pub const ImmutableArrayList = @import("immutable_array_list.zig").ImmutableArrayList;
pub const ImmutableArrayStack = @import("immutable_array_stack.zig").ImmutableArrayStack;
pub const ImmutableArrayDeque = @import("immutable_array_deque.zig").ImmutableArrayDeque;
pub const ImmutablePriorityQueue = @import("immutable_priority_queue.zig").ImmutablePriorityQueue;

pub const immutable_bit_set = @import("immutable_bit_set.zig");

// ---- Named immutable hash map aliases ----

pub const ImmutableBoolBoolHashMap = ImmutableHashMap(bool, bool);
pub const ImmutableBoolCharHashMap = ImmutableHashMap(bool, u21);
pub const ImmutableBoolF32HashMap = ImmutableHashMap(bool, f32);
pub const ImmutableBoolF64HashMap = ImmutableHashMap(bool, f64);
pub const ImmutableBoolI8HashMap = ImmutableHashMap(bool, i8);
pub const ImmutableBoolI16HashMap = ImmutableHashMap(bool, i16);
pub const ImmutableBoolI32HashMap = ImmutableHashMap(bool, i32);
pub const ImmutableBoolI64HashMap = ImmutableHashMap(bool, i64);
pub const ImmutableCharBoolHashMap = ImmutableHashMap(u21, bool);
pub const ImmutableCharCharHashMap = ImmutableHashMap(u21, u21);
pub const ImmutableCharF32HashMap = ImmutableHashMap(u21, f32);
pub const ImmutableCharF64HashMap = ImmutableHashMap(u21, f64);
pub const ImmutableCharI8HashMap = ImmutableHashMap(u21, i8);
pub const ImmutableCharI16HashMap = ImmutableHashMap(u21, i16);
pub const ImmutableCharI32HashMap = ImmutableHashMap(u21, i32);
pub const ImmutableCharI64HashMap = ImmutableHashMap(u21, i64);
pub const ImmutableF32BoolHashMap = ImmutableHashMap(f32, bool);
pub const ImmutableF32CharHashMap = ImmutableHashMap(f32, u21);
pub const ImmutableF32F32HashMap = ImmutableHashMap(f32, f32);
pub const ImmutableF32F64HashMap = ImmutableHashMap(f32, f64);
pub const ImmutableF32I8HashMap = ImmutableHashMap(f32, i8);
pub const ImmutableF32I16HashMap = ImmutableHashMap(f32, i16);
pub const ImmutableF32I32HashMap = ImmutableHashMap(f32, i32);
pub const ImmutableF32I64HashMap = ImmutableHashMap(f32, i64);
pub const ImmutableF64BoolHashMap = ImmutableHashMap(f64, bool);
pub const ImmutableF64CharHashMap = ImmutableHashMap(f64, u21);
pub const ImmutableF64F32HashMap = ImmutableHashMap(f64, f32);
pub const ImmutableF64F64HashMap = ImmutableHashMap(f64, f64);
pub const ImmutableF64I8HashMap = ImmutableHashMap(f64, i8);
pub const ImmutableF64I16HashMap = ImmutableHashMap(f64, i16);
pub const ImmutableF64I32HashMap = ImmutableHashMap(f64, i32);
pub const ImmutableF64I64HashMap = ImmutableHashMap(f64, i64);
pub const ImmutableI8BoolHashMap = ImmutableHashMap(i8, bool);
pub const ImmutableI8CharHashMap = ImmutableHashMap(i8, u21);
pub const ImmutableI8F32HashMap = ImmutableHashMap(i8, f32);
pub const ImmutableI8F64HashMap = ImmutableHashMap(i8, f64);
pub const ImmutableI8I8HashMap = ImmutableHashMap(i8, i8);
pub const ImmutableI8I16HashMap = ImmutableHashMap(i8, i16);
pub const ImmutableI8I32HashMap = ImmutableHashMap(i8, i32);
pub const ImmutableI8I64HashMap = ImmutableHashMap(i8, i64);
pub const ImmutableI16BoolHashMap = ImmutableHashMap(i16, bool);
pub const ImmutableI16CharHashMap = ImmutableHashMap(i16, u21);
pub const ImmutableI16F32HashMap = ImmutableHashMap(i16, f32);
pub const ImmutableI16F64HashMap = ImmutableHashMap(i16, f64);
pub const ImmutableI16I8HashMap = ImmutableHashMap(i16, i8);
pub const ImmutableI16I16HashMap = ImmutableHashMap(i16, i16);
pub const ImmutableI16I32HashMap = ImmutableHashMap(i16, i32);
pub const ImmutableI16I64HashMap = ImmutableHashMap(i16, i64);
pub const ImmutableI32BoolHashMap = ImmutableHashMap(i32, bool);
pub const ImmutableI32CharHashMap = ImmutableHashMap(i32, u21);
pub const ImmutableI32F32HashMap = ImmutableHashMap(i32, f32);
pub const ImmutableI32F64HashMap = ImmutableHashMap(i32, f64);
pub const ImmutableI32I8HashMap = ImmutableHashMap(i32, i8);
pub const ImmutableI32I16HashMap = ImmutableHashMap(i32, i16);
pub const ImmutableI32I32HashMap = ImmutableHashMap(i32, i32);
pub const ImmutableI32I64HashMap = ImmutableHashMap(i32, i64);
pub const ImmutableI64BoolHashMap = ImmutableHashMap(i64, bool);
pub const ImmutableI64CharHashMap = ImmutableHashMap(i64, u21);
pub const ImmutableI64F32HashMap = ImmutableHashMap(i64, f32);
pub const ImmutableI64F64HashMap = ImmutableHashMap(i64, f64);
pub const ImmutableI64I8HashMap = ImmutableHashMap(i64, i8);
pub const ImmutableI64I16HashMap = ImmutableHashMap(i64, i16);
pub const ImmutableI64I32HashMap = ImmutableHashMap(i64, i32);
pub const ImmutableI64I64HashMap = ImmutableHashMap(i64, i64);

// ---- Named immutable HashSet aliases ----

pub const ImmutableBoolHashSet = ImmutableHashSet(bool);
pub const ImmutableCharHashSet = ImmutableHashSet(u21);
pub const ImmutableF32HashSet = ImmutableHashSet(f32);
pub const ImmutableF64HashSet = ImmutableHashSet(f64);
pub const ImmutableI8HashSet = ImmutableHashSet(i8);
pub const ImmutableI16HashSet = ImmutableHashSet(i16);
pub const ImmutableI32HashSet = ImmutableHashSet(i32);
pub const ImmutableI64HashSet = ImmutableHashSet(i64);

// ---- Named immutable HashBag aliases ----

pub const ImmutableBoolHashBag = ImmutableHashBag(bool);
pub const ImmutableCharHashBag = ImmutableHashBag(u21);
pub const ImmutableF32HashBag = ImmutableHashBag(f32);
pub const ImmutableF64HashBag = ImmutableHashBag(f64);
pub const ImmutableI8HashBag = ImmutableHashBag(i8);
pub const ImmutableI16HashBag = ImmutableHashBag(i16);
pub const ImmutableI32HashBag = ImmutableHashBag(i32);
pub const ImmutableI64HashBag = ImmutableHashBag(i64);

// ---- Named immutable ArrayList aliases ----

pub const ImmutableBoolArrayList = ImmutableArrayList(bool);
pub const ImmutableCharArrayList = ImmutableArrayList(u21);
pub const ImmutableF32ArrayList = ImmutableArrayList(f32);
pub const ImmutableF64ArrayList = ImmutableArrayList(f64);
pub const ImmutableI8ArrayList = ImmutableArrayList(i8);
pub const ImmutableI16ArrayList = ImmutableArrayList(i16);
pub const ImmutableI32ArrayList = ImmutableArrayList(i32);
pub const ImmutableI64ArrayList = ImmutableArrayList(i64);

// ---- Named immutable ArrayStack aliases ----

pub const ImmutableBoolArrayStack = ImmutableArrayStack(bool);
pub const ImmutableCharArrayStack = ImmutableArrayStack(u21);
pub const ImmutableF32ArrayStack = ImmutableArrayStack(f32);
pub const ImmutableF64ArrayStack = ImmutableArrayStack(f64);
pub const ImmutableI8ArrayStack = ImmutableArrayStack(i8);
pub const ImmutableI16ArrayStack = ImmutableArrayStack(i16);
pub const ImmutableI32ArrayStack = ImmutableArrayStack(i32);
pub const ImmutableI64ArrayStack = ImmutableArrayStack(i64);

// ---- Named immutable ArrayDeque aliases ----

pub const ImmutableBoolArrayDeque = ImmutableArrayDeque(bool);
pub const ImmutableCharArrayDeque = ImmutableArrayDeque(u21);
pub const ImmutableF32ArrayDeque = ImmutableArrayDeque(f32);
pub const ImmutableF64ArrayDeque = ImmutableArrayDeque(f64);
pub const ImmutableI8ArrayDeque = ImmutableArrayDeque(i8);
pub const ImmutableI16ArrayDeque = ImmutableArrayDeque(i16);
pub const ImmutableI32ArrayDeque = ImmutableArrayDeque(i32);
pub const ImmutableI64ArrayDeque = ImmutableArrayDeque(i64);

// ---- Named immutable PriorityQueue aliases ----

pub const ImmutableBoolPriorityQueue = ImmutablePriorityQueue(bool);
pub const ImmutableCharPriorityQueue = ImmutablePriorityQueue(u21);
pub const ImmutableF32PriorityQueue = ImmutablePriorityQueue(f32);
pub const ImmutableF64PriorityQueue = ImmutablePriorityQueue(f64);
pub const ImmutableI8PriorityQueue = ImmutablePriorityQueue(i8);
pub const ImmutableI16PriorityQueue = ImmutablePriorityQueue(i16);
pub const ImmutableI32PriorityQueue = ImmutablePriorityQueue(i32);
pub const ImmutableI64PriorityQueue = ImmutablePriorityQueue(i64);

// ---- Backward-compat per-file namespaces ----

pub const immutable_bool_bool_hash_map = struct {
    pub const ImmutableBoolBoolHashMap = ImmutableHashMap(bool, bool);
};
pub const immutable_bool_char_hash_map = struct {
    pub const ImmutableBoolCharHashMap = ImmutableHashMap(bool, u21);
};
pub const immutable_bool_f32_hash_map = struct {
    pub const ImmutableBoolF32HashMap = ImmutableHashMap(bool, f32);
};
pub const immutable_bool_f64_hash_map = struct {
    pub const ImmutableBoolF64HashMap = ImmutableHashMap(bool, f64);
};
pub const immutable_bool_i8_hash_map = struct {
    pub const ImmutableBoolI8HashMap = ImmutableHashMap(bool, i8);
};
pub const immutable_bool_i16_hash_map = struct {
    pub const ImmutableBoolI16HashMap = ImmutableHashMap(bool, i16);
};
pub const immutable_bool_i32_hash_map = struct {
    pub const ImmutableBoolI32HashMap = ImmutableHashMap(bool, i32);
};
pub const immutable_bool_i64_hash_map = struct {
    pub const ImmutableBoolI64HashMap = ImmutableHashMap(bool, i64);
};
pub const immutable_char_bool_hash_map = struct {
    pub const ImmutableCharBoolHashMap = ImmutableHashMap(u21, bool);
};
pub const immutable_char_char_hash_map = struct {
    pub const ImmutableCharCharHashMap = ImmutableHashMap(u21, u21);
};
pub const immutable_char_f32_hash_map = struct {
    pub const ImmutableCharF32HashMap = ImmutableHashMap(u21, f32);
};
pub const immutable_char_f64_hash_map = struct {
    pub const ImmutableCharF64HashMap = ImmutableHashMap(u21, f64);
};
pub const immutable_char_i8_hash_map = struct {
    pub const ImmutableCharI8HashMap = ImmutableHashMap(u21, i8);
};
pub const immutable_char_i16_hash_map = struct {
    pub const ImmutableCharI16HashMap = ImmutableHashMap(u21, i16);
};
pub const immutable_char_i32_hash_map = struct {
    pub const ImmutableCharI32HashMap = ImmutableHashMap(u21, i32);
};
pub const immutable_char_i64_hash_map = struct {
    pub const ImmutableCharI64HashMap = ImmutableHashMap(u21, i64);
};
pub const immutable_f32_bool_hash_map = struct {
    pub const ImmutableF32BoolHashMap = ImmutableHashMap(f32, bool);
};
pub const immutable_f32_char_hash_map = struct {
    pub const ImmutableF32CharHashMap = ImmutableHashMap(f32, u21);
};
pub const immutable_f32_f32_hash_map = struct {
    pub const ImmutableF32F32HashMap = ImmutableHashMap(f32, f32);
};
pub const immutable_f32_f64_hash_map = struct {
    pub const ImmutableF32F64HashMap = ImmutableHashMap(f32, f64);
};
pub const immutable_f32_i8_hash_map = struct {
    pub const ImmutableF32I8HashMap = ImmutableHashMap(f32, i8);
};
pub const immutable_f32_i16_hash_map = struct {
    pub const ImmutableF32I16HashMap = ImmutableHashMap(f32, i16);
};
pub const immutable_f32_i32_hash_map = struct {
    pub const ImmutableF32I32HashMap = ImmutableHashMap(f32, i32);
};
pub const immutable_f32_i64_hash_map = struct {
    pub const ImmutableF32I64HashMap = ImmutableHashMap(f32, i64);
};
pub const immutable_f64_bool_hash_map = struct {
    pub const ImmutableF64BoolHashMap = ImmutableHashMap(f64, bool);
};
pub const immutable_f64_char_hash_map = struct {
    pub const ImmutableF64CharHashMap = ImmutableHashMap(f64, u21);
};
pub const immutable_f64_f32_hash_map = struct {
    pub const ImmutableF64F32HashMap = ImmutableHashMap(f64, f32);
};
pub const immutable_f64_f64_hash_map = struct {
    pub const ImmutableF64F64HashMap = ImmutableHashMap(f64, f64);
};
pub const immutable_f64_i8_hash_map = struct {
    pub const ImmutableF64I8HashMap = ImmutableHashMap(f64, i8);
};
pub const immutable_f64_i16_hash_map = struct {
    pub const ImmutableF64I16HashMap = ImmutableHashMap(f64, i16);
};
pub const immutable_f64_i32_hash_map = struct {
    pub const ImmutableF64I32HashMap = ImmutableHashMap(f64, i32);
};
pub const immutable_f64_i64_hash_map = struct {
    pub const ImmutableF64I64HashMap = ImmutableHashMap(f64, i64);
};
pub const immutable_i8_bool_hash_map = struct {
    pub const ImmutableI8BoolHashMap = ImmutableHashMap(i8, bool);
};
pub const immutable_i8_char_hash_map = struct {
    pub const ImmutableI8CharHashMap = ImmutableHashMap(i8, u21);
};
pub const immutable_i8_f32_hash_map = struct {
    pub const ImmutableI8F32HashMap = ImmutableHashMap(i8, f32);
};
pub const immutable_i8_f64_hash_map = struct {
    pub const ImmutableI8F64HashMap = ImmutableHashMap(i8, f64);
};
pub const immutable_i8_i8_hash_map = struct {
    pub const ImmutableI8I8HashMap = ImmutableHashMap(i8, i8);
};
pub const immutable_i8_i16_hash_map = struct {
    pub const ImmutableI8I16HashMap = ImmutableHashMap(i8, i16);
};
pub const immutable_i8_i32_hash_map = struct {
    pub const ImmutableI8I32HashMap = ImmutableHashMap(i8, i32);
};
pub const immutable_i8_i64_hash_map = struct {
    pub const ImmutableI8I64HashMap = ImmutableHashMap(i8, i64);
};
pub const immutable_i16_bool_hash_map = struct {
    pub const ImmutableI16BoolHashMap = ImmutableHashMap(i16, bool);
};
pub const immutable_i16_char_hash_map = struct {
    pub const ImmutableI16CharHashMap = ImmutableHashMap(i16, u21);
};
pub const immutable_i16_f32_hash_map = struct {
    pub const ImmutableI16F32HashMap = ImmutableHashMap(i16, f32);
};
pub const immutable_i16_f64_hash_map = struct {
    pub const ImmutableI16F64HashMap = ImmutableHashMap(i16, f64);
};
pub const immutable_i16_i8_hash_map = struct {
    pub const ImmutableI16I8HashMap = ImmutableHashMap(i16, i8);
};
pub const immutable_i16_i16_hash_map = struct {
    pub const ImmutableI16I16HashMap = ImmutableHashMap(i16, i16);
};
pub const immutable_i16_i32_hash_map = struct {
    pub const ImmutableI16I32HashMap = ImmutableHashMap(i16, i32);
};
pub const immutable_i16_i64_hash_map = struct {
    pub const ImmutableI16I64HashMap = ImmutableHashMap(i16, i64);
};
pub const immutable_i32_bool_hash_map = struct {
    pub const ImmutableI32BoolHashMap = ImmutableHashMap(i32, bool);
};
pub const immutable_i32_char_hash_map = struct {
    pub const ImmutableI32CharHashMap = ImmutableHashMap(i32, u21);
};
pub const immutable_i32_f32_hash_map = struct {
    pub const ImmutableI32F32HashMap = ImmutableHashMap(i32, f32);
};
pub const immutable_i32_f64_hash_map = struct {
    pub const ImmutableI32F64HashMap = ImmutableHashMap(i32, f64);
};
pub const immutable_i32_i8_hash_map = struct {
    pub const ImmutableI32I8HashMap = ImmutableHashMap(i32, i8);
};
pub const immutable_i32_i16_hash_map = struct {
    pub const ImmutableI32I16HashMap = ImmutableHashMap(i32, i16);
};
pub const immutable_i32_i32_hash_map = struct {
    pub const ImmutableI32I32HashMap = ImmutableHashMap(i32, i32);
};
pub const immutable_i32_i64_hash_map = struct {
    pub const ImmutableI32I64HashMap = ImmutableHashMap(i32, i64);
};
pub const immutable_i64_bool_hash_map = struct {
    pub const ImmutableI64BoolHashMap = ImmutableHashMap(i64, bool);
};
pub const immutable_i64_char_hash_map = struct {
    pub const ImmutableI64CharHashMap = ImmutableHashMap(i64, u21);
};
pub const immutable_i64_f32_hash_map = struct {
    pub const ImmutableI64F32HashMap = ImmutableHashMap(i64, f32);
};
pub const immutable_i64_f64_hash_map = struct {
    pub const ImmutableI64F64HashMap = ImmutableHashMap(i64, f64);
};
pub const immutable_i64_i8_hash_map = struct {
    pub const ImmutableI64I8HashMap = ImmutableHashMap(i64, i8);
};
pub const immutable_i64_i16_hash_map = struct {
    pub const ImmutableI64I16HashMap = ImmutableHashMap(i64, i16);
};
pub const immutable_i64_i32_hash_map = struct {
    pub const ImmutableI64I32HashMap = ImmutableHashMap(i64, i32);
};
pub const immutable_i64_i64_hash_map = struct {
    pub const ImmutableI64I64HashMap = ImmutableHashMap(i64, i64);
};
pub const immutable_bool_hash_set = struct {
    pub const ImmutableBoolHashSet = ImmutableHashSet(bool);
};
pub const immutable_char_hash_set = struct {
    pub const ImmutableCharHashSet = ImmutableHashSet(u21);
};
pub const immutable_f32_hash_set = struct {
    pub const ImmutableF32HashSet = ImmutableHashSet(f32);
};
pub const immutable_f64_hash_set = struct {
    pub const ImmutableF64HashSet = ImmutableHashSet(f64);
};
pub const immutable_i8_hash_set = struct {
    pub const ImmutableI8HashSet = ImmutableHashSet(i8);
};
pub const immutable_i16_hash_set = struct {
    pub const ImmutableI16HashSet = ImmutableHashSet(i16);
};
pub const immutable_i32_hash_set = struct {
    pub const ImmutableI32HashSet = ImmutableHashSet(i32);
};
pub const immutable_i64_hash_set = struct {
    pub const ImmutableI64HashSet = ImmutableHashSet(i64);
};
pub const immutable_bool_hash_bag = struct {
    pub const ImmutableBoolHashBag = ImmutableHashBag(bool);
};
pub const immutable_char_hash_bag = struct {
    pub const ImmutableCharHashBag = ImmutableHashBag(u21);
};
pub const immutable_f32_hash_bag = struct {
    pub const ImmutableF32HashBag = ImmutableHashBag(f32);
};
pub const immutable_f64_hash_bag = struct {
    pub const ImmutableF64HashBag = ImmutableHashBag(f64);
};
pub const immutable_i8_hash_bag = struct {
    pub const ImmutableI8HashBag = ImmutableHashBag(i8);
};
pub const immutable_i16_hash_bag = struct {
    pub const ImmutableI16HashBag = ImmutableHashBag(i16);
};
pub const immutable_i32_hash_bag = struct {
    pub const ImmutableI32HashBag = ImmutableHashBag(i32);
};
pub const immutable_i64_hash_bag = struct {
    pub const ImmutableI64HashBag = ImmutableHashBag(i64);
};
pub const immutable_bool_array_list = struct {
    pub const ImmutableBoolArrayList = ImmutableArrayList(bool);
};
pub const immutable_char_array_list = struct {
    pub const ImmutableCharArrayList = ImmutableArrayList(u21);
};
pub const immutable_f32_array_list = struct {
    pub const ImmutableF32ArrayList = ImmutableArrayList(f32);
};
pub const immutable_f64_array_list = struct {
    pub const ImmutableF64ArrayList = ImmutableArrayList(f64);
};
pub const immutable_i8_array_list = struct {
    pub const ImmutableI8ArrayList = ImmutableArrayList(i8);
};
pub const immutable_i16_array_list = struct {
    pub const ImmutableI16ArrayList = ImmutableArrayList(i16);
};
pub const immutable_i32_array_list = struct {
    pub const ImmutableI32ArrayList = ImmutableArrayList(i32);
};
pub const immutable_i64_array_list = struct {
    pub const ImmutableI64ArrayList = ImmutableArrayList(i64);
};
pub const immutable_bool_array_stack = struct {
    pub const ImmutableBoolArrayStack = ImmutableArrayStack(bool);
};
pub const immutable_char_array_stack = struct {
    pub const ImmutableCharArrayStack = ImmutableArrayStack(u21);
};
pub const immutable_f32_array_stack = struct {
    pub const ImmutableF32ArrayStack = ImmutableArrayStack(f32);
};
pub const immutable_f64_array_stack = struct {
    pub const ImmutableF64ArrayStack = ImmutableArrayStack(f64);
};
pub const immutable_i8_array_stack = struct {
    pub const ImmutableI8ArrayStack = ImmutableArrayStack(i8);
};
pub const immutable_i16_array_stack = struct {
    pub const ImmutableI16ArrayStack = ImmutableArrayStack(i16);
};
pub const immutable_i32_array_stack = struct {
    pub const ImmutableI32ArrayStack = ImmutableArrayStack(i32);
};
pub const immutable_i64_array_stack = struct {
    pub const ImmutableI64ArrayStack = ImmutableArrayStack(i64);
};
pub const immutable_bool_array_deque = struct {
    pub const ImmutableBoolArrayDeque = ImmutableArrayDeque(bool);
};
pub const immutable_char_array_deque = struct {
    pub const ImmutableCharArrayDeque = ImmutableArrayDeque(u21);
};
pub const immutable_f32_array_deque = struct {
    pub const ImmutableF32ArrayDeque = ImmutableArrayDeque(f32);
};
pub const immutable_f64_array_deque = struct {
    pub const ImmutableF64ArrayDeque = ImmutableArrayDeque(f64);
};
pub const immutable_i8_array_deque = struct {
    pub const ImmutableI8ArrayDeque = ImmutableArrayDeque(i8);
};
pub const immutable_i16_array_deque = struct {
    pub const ImmutableI16ArrayDeque = ImmutableArrayDeque(i16);
};
pub const immutable_i32_array_deque = struct {
    pub const ImmutableI32ArrayDeque = ImmutableArrayDeque(i32);
};
pub const immutable_i64_array_deque = struct {
    pub const ImmutableI64ArrayDeque = ImmutableArrayDeque(i64);
};
pub const immutable_bool_priority_queue = struct {
    pub const ImmutableBoolPriorityQueue = ImmutablePriorityQueue(bool);
};
pub const immutable_char_priority_queue = struct {
    pub const ImmutableCharPriorityQueue = ImmutablePriorityQueue(u21);
};
pub const immutable_f32_priority_queue = struct {
    pub const ImmutableF32PriorityQueue = ImmutablePriorityQueue(f32);
};
pub const immutable_f64_priority_queue = struct {
    pub const ImmutableF64PriorityQueue = ImmutablePriorityQueue(f64);
};
pub const immutable_i8_priority_queue = struct {
    pub const ImmutableI8PriorityQueue = ImmutablePriorityQueue(i8);
};
pub const immutable_i16_priority_queue = struct {
    pub const ImmutableI16PriorityQueue = ImmutablePriorityQueue(i16);
};
pub const immutable_i32_priority_queue = struct {
    pub const ImmutableI32PriorityQueue = ImmutablePriorityQueue(i32);
};
pub const immutable_i64_priority_queue = struct {
    pub const ImmutableI64PriorityQueue = ImmutablePriorityQueue(i64);
};

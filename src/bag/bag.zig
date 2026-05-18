// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


pub const bool_hash_bag = @import("bool_hash_bag.zig");
pub const bool_tree_bag = @import("bool_tree_bag.zig");
pub const char_hash_bag = @import("char_hash_bag.zig");
pub const char_tree_bag = @import("char_tree_bag.zig");
pub const f32_hash_bag = @import("f32_hash_bag.zig");
pub const f32_tree_bag = @import("f32_tree_bag.zig");
pub const f64_hash_bag = @import("f64_hash_bag.zig");
pub const f64_tree_bag = @import("f64_tree_bag.zig");
pub const i16_hash_bag = @import("i16_hash_bag.zig");
pub const i16_tree_bag = @import("i16_tree_bag.zig");
pub const i32_hash_bag = @import("i32_hash_bag.zig");
pub const i32_tree_bag = @import("i32_tree_bag.zig");
pub const i64_hash_bag = @import("i64_hash_bag.zig");
pub const i64_tree_bag = @import("i64_tree_bag.zig");
pub const i8_hash_bag = @import("i8_hash_bag.zig");
pub const i8_tree_bag = @import("i8_tree_bag.zig");

comptime {
    _ = @import("bool_hash_bag.zig");
    _ = @import("bool_tree_bag.zig");
    _ = @import("char_hash_bag.zig");
    _ = @import("char_tree_bag.zig");
    _ = @import("f32_hash_bag.zig");
    _ = @import("f32_tree_bag.zig");
    _ = @import("f64_hash_bag.zig");
    _ = @import("f64_tree_bag.zig");
    _ = @import("i16_hash_bag.zig");
    _ = @import("i16_tree_bag.zig");
    _ = @import("i32_hash_bag.zig");
    _ = @import("i32_tree_bag.zig");
    _ = @import("i64_hash_bag.zig");
    _ = @import("i64_tree_bag.zig");
    _ = @import("i8_hash_bag.zig");
    _ = @import("i8_tree_bag.zig");
}

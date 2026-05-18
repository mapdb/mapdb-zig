// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


pub const bool_tree_set = @import("bool_tree_set.zig");
pub const char_tree_set = @import("char_tree_set.zig");
pub const f32_tree_set = @import("f32_tree_set.zig");
pub const f64_tree_set = @import("f64_tree_set.zig");
pub const i16_tree_set = @import("i16_tree_set.zig");
pub const i32_tree_set = @import("i32_tree_set.zig");
pub const i64_tree_set = @import("i64_tree_set.zig");
pub const i8_tree_set = @import("i8_tree_set.zig");

comptime {
    _ = @import("bool_tree_set.zig");
    _ = @import("char_tree_set.zig");
    _ = @import("f32_tree_set.zig");
    _ = @import("f64_tree_set.zig");
    _ = @import("i16_tree_set.zig");
    _ = @import("i32_tree_set.zig");
    _ = @import("i64_tree_set.zig");
    _ = @import("i8_tree_set.zig");
}

// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


pub const bool_array_stack = @import("bool_array_stack.zig");
pub const char_array_stack = @import("char_array_stack.zig");
pub const f32_array_stack = @import("f32_array_stack.zig");
pub const f64_array_stack = @import("f64_array_stack.zig");
pub const i16_array_stack = @import("i16_array_stack.zig");
pub const i32_array_stack = @import("i32_array_stack.zig");
pub const i64_array_stack = @import("i64_array_stack.zig");
pub const i8_array_stack = @import("i8_array_stack.zig");

comptime {
    _ = @import("bool_array_stack.zig");
    _ = @import("char_array_stack.zig");
    _ = @import("f32_array_stack.zig");
    _ = @import("f64_array_stack.zig");
    _ = @import("i16_array_stack.zig");
    _ = @import("i32_array_stack.zig");
    _ = @import("i64_array_stack.zig");
    _ = @import("i8_array_stack.zig");
}

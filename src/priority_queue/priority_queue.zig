// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


pub const bool_priority_queue = @import("bool_priority_queue.zig");
pub const char_priority_queue = @import("char_priority_queue.zig");
pub const f32_priority_queue = @import("f32_priority_queue.zig");
pub const f64_priority_queue = @import("f64_priority_queue.zig");
pub const i16_priority_queue = @import("i16_priority_queue.zig");
pub const i32_priority_queue = @import("i32_priority_queue.zig");
pub const i64_priority_queue = @import("i64_priority_queue.zig");
pub const i8_priority_queue = @import("i8_priority_queue.zig");

comptime {
    _ = @import("bool_priority_queue.zig");
    _ = @import("char_priority_queue.zig");
    _ = @import("f32_priority_queue.zig");
    _ = @import("f64_priority_queue.zig");
    _ = @import("i16_priority_queue.zig");
    _ = @import("i32_priority_queue.zig");
    _ = @import("i64_priority_queue.zig");
    _ = @import("i8_priority_queue.zig");
}

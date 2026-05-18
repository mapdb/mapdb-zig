// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


pub const bool_interval = @import("bool_interval.zig");
pub const char_interval = @import("char_interval.zig");
pub const f32_interval = @import("f32_interval.zig");
pub const f64_interval = @import("f64_interval.zig");
pub const i16_interval = @import("i16_interval.zig");
pub const i32_interval = @import("i32_interval.zig");
pub const i64_interval = @import("i64_interval.zig");
pub const i8_interval = @import("i8_interval.zig");

comptime {
    _ = @import("bool_interval.zig");
    _ = @import("char_interval.zig");
    _ = @import("f32_interval.zig");
    _ = @import("f64_interval.zig");
    _ = @import("i16_interval.zig");
    _ = @import("i32_interval.zig");
    _ = @import("i64_interval.zig");
    _ = @import("i8_interval.zig");
}

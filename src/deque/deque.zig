
pub const bool_array_deque = @import("bool_array_deque.zig");
pub const char_array_deque = @import("char_array_deque.zig");
pub const f32_array_deque = @import("f32_array_deque.zig");
pub const f64_array_deque = @import("f64_array_deque.zig");
pub const i16_array_deque = @import("i16_array_deque.zig");
pub const i32_array_deque = @import("i32_array_deque.zig");
pub const i64_array_deque = @import("i64_array_deque.zig");
pub const i8_array_deque = @import("i8_array_deque.zig");

comptime {
    _ = @import("bool_array_deque.zig");
    _ = @import("char_array_deque.zig");
    _ = @import("f32_array_deque.zig");
    _ = @import("f64_array_deque.zig");
    _ = @import("i16_array_deque.zig");
    _ = @import("i32_array_deque.zig");
    _ = @import("i64_array_deque.zig");
    _ = @import("i8_array_deque.zig");
}

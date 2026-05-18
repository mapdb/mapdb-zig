
pub const bool_array_list = @import("bool_array_list.zig");
pub const char_array_list = @import("char_array_list.zig");
pub const f32_array_list = @import("f32_array_list.zig");
pub const f64_array_list = @import("f64_array_list.zig");
pub const i16_array_list = @import("i16_array_list.zig");
pub const i32_array_list = @import("i32_array_list.zig");
pub const i64_array_list = @import("i64_array_list.zig");
pub const i8_array_list = @import("i8_array_list.zig");

comptime {
    _ = @import("bool_array_list.zig");
    _ = @import("char_array_list.zig");
    _ = @import("f32_array_list.zig");
    _ = @import("f64_array_list.zig");
    _ = @import("i16_array_list.zig");
    _ = @import("i32_array_list.zig");
    _ = @import("i64_array_list.zig");
    _ = @import("i8_array_list.zig");
}


pub const bool_hash_set = @import("bool_hash_set.zig");
pub const char_hash_set = @import("char_hash_set.zig");
pub const f32_hash_set = @import("f32_hash_set.zig");
pub const f64_hash_set = @import("f64_hash_set.zig");
pub const i16_hash_set = @import("i16_hash_set.zig");
pub const i32_hash_set = @import("i32_hash_set.zig");
pub const i64_hash_set = @import("i64_hash_set.zig");
pub const i8_hash_set = @import("i8_hash_set.zig");

comptime {
    _ = @import("bool_hash_set.zig");
    _ = @import("char_hash_set.zig");
    _ = @import("f32_hash_set.zig");
    _ = @import("f64_hash_set.zig");
    _ = @import("i16_hash_set.zig");
    _ = @import("i32_hash_set.zig");
    _ = @import("i64_hash_set.zig");
    _ = @import("i8_hash_set.zig");
}

const fixint = @import("fixint.zig").fixint;
const builtin = @import("builtin");

pub extern fn __fixsfti(a: f32) i128 {
    @setRuntimeSafety(builtin.is_test);
    return fixint(f32, i128, a);
}

test "import fixsfti" {
    _ = @import("fixsfti_test.zig");
}

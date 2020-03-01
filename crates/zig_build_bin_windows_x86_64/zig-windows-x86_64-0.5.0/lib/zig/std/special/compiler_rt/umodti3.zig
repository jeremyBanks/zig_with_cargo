const udivmodti4 = @import("udivmodti4.zig");
const builtin = @import("builtin");
const compiler_rt = @import("../compiler_rt.zig");

pub extern fn __umodti3(a: u128, b: u128) u128 {
    @setRuntimeSafety(builtin.is_test);
    var r: u128 = undefined;
    _ = udivmodti4.__udivmodti4(a, b, &r);
    return r;
}

const v128 = @Vector(2, u64);
pub extern fn __umodti3_windows_x86_64(a: v128, b: v128) v128 {
    return @bitCast(v128, @inlineCall(__umodti3, @bitCast(u128, a), @bitCast(u128, b)));
}

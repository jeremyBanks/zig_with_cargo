const std = @import("../std.zig");
const math = std.math;
const expect = std.testing.expect;
const maxInt = std.math.maxInt;

// Returns whether x has a normalized representation (i.e. integer part of mantissa is 1).
pub fn isNormal(x: var) bool {
    const T = @typeOf(x);
    switch (T) {
        f16 => {
            const bits = @bitCast(u16, x);
            return (bits + 1024) & 0x7FFF >= 2048;
        },
        f32 => {
            const bits = @bitCast(u32, x);
            return (bits + 0x00800000) & 0x7FFFFFFF >= 0x01000000;
        },
        f64 => {
            const bits = @bitCast(u64, x);
            return (bits + (1 << 52)) & (maxInt(u64) >> 1) >= (1 << 53);
        },
        else => {
            @compileError("isNormal not implemented for " ++ @typeName(T));
        },
    }
}

test "math.isNormal" {
    expect(!isNormal(math.nan(f16)));
    expect(!isNormal(math.nan(f32)));
    expect(!isNormal(math.nan(f64)));
    expect(!isNormal(f16(0)));
    expect(!isNormal(f32(0)));
    expect(!isNormal(f64(0)));
    expect(isNormal(f16(1.0)));
    expect(isNormal(f32(1.0)));
    expect(isNormal(f64(1.0)));
}

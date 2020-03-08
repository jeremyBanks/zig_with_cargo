const std = @import("../std.zig");
const math = std.math;
const expect = std.testing.expect;

/// Returns whether x is negative or negative 0.
pub fn signbit(x: var) bool {
    const T = @TypeOf(x);
    return switch (T) {
        f16 => signbit16(x),
        f32 => signbit32(x),
        f64 => signbit64(x),
        else => @compileError("signbit not implemented for " ++ @typeName(T)),
    };
}

fn signbit16(x: f16) bool {
    const bits = @bitCast(u16, x);
    return bits >> 15 != 0;
}

fn signbit32(x: f32) bool {
    const bits = @bitCast(u32, x);
    return bits >> 31 != 0;
}

fn signbit64(x: f64) bool {
    const bits = @bitCast(u64, x);
    return bits >> 63 != 0;
}

test "math.signbit" {
    expect(signbit(@as(f16, 4.0)) == signbit16(4.0));
    expect(signbit(@as(f32, 4.0)) == signbit32(4.0));
    expect(signbit(@as(f64, 4.0)) == signbit64(4.0));
}

test "math.signbit16" {
    expect(!signbit16(4.0));
    expect(signbit16(-3.0));
}

test "math.signbit32" {
    expect(!signbit32(4.0));
    expect(signbit32(-3.0));
}

test "math.signbit64" {
    expect(!signbit64(4.0));
    expect(signbit64(-3.0));
}

const std = @import("../std.zig");
const math = std.math;
const expect = std.testing.expect;
const maxInt = std.math.maxInt;

/// Returns whether x is an infinity, ignoring sign.
pub fn isInf(x: var) bool {
    const T = @typeOf(x);
    switch (T) {
        f16 => {
            const bits = @bitCast(u16, x);
            return bits & 0x7FFF == 0x7C00;
        },
        f32 => {
            const bits = @bitCast(u32, x);
            return bits & 0x7FFFFFFF == 0x7F800000;
        },
        f64 => {
            const bits = @bitCast(u64, x);
            return bits & (maxInt(u64) >> 1) == (0x7FF << 52);
        },
        f128 => {
            const bits = @bitCast(u128, x);
            return bits & (maxInt(u128) >> 1) == (0x7FFF << 112);
        },
        else => {
            @compileError("isInf not implemented for " ++ @typeName(T));
        },
    }
}

/// Returns whether x is an infinity with a positive sign.
pub fn isPositiveInf(x: var) bool {
    const T = @typeOf(x);
    switch (T) {
        f16 => {
            return @bitCast(u16, x) == 0x7C00;
        },
        f32 => {
            return @bitCast(u32, x) == 0x7F800000;
        },
        f64 => {
            return @bitCast(u64, x) == 0x7FF << 52;
        },
        f128 => {
            return @bitCast(u128, x) == 0x7FFF << 112;
        },
        else => {
            @compileError("isPositiveInf not implemented for " ++ @typeName(T));
        },
    }
}

/// Returns whether x is an infinity with a negative sign.
pub fn isNegativeInf(x: var) bool {
    const T = @typeOf(x);
    switch (T) {
        f16 => {
            return @bitCast(u16, x) == 0xFC00;
        },
        f32 => {
            return @bitCast(u32, x) == 0xFF800000;
        },
        f64 => {
            return @bitCast(u64, x) == 0xFFF << 52;
        },
        f128 => {
            return @bitCast(u128, x) == 0xFFFF << 112;
        },
        else => {
            @compileError("isNegativeInf not implemented for " ++ @typeName(T));
        },
    }
}

test "math.isInf" {
    expect(!isInf(f16(0.0)));
    expect(!isInf(f16(-0.0)));
    expect(!isInf(f32(0.0)));
    expect(!isInf(f32(-0.0)));
    expect(!isInf(f64(0.0)));
    expect(!isInf(f64(-0.0)));
    expect(!isInf(f128(0.0)));
    expect(!isInf(f128(-0.0)));
    expect(isInf(math.inf(f16)));
    expect(isInf(-math.inf(f16)));
    expect(isInf(math.inf(f32)));
    expect(isInf(-math.inf(f32)));
    expect(isInf(math.inf(f64)));
    expect(isInf(-math.inf(f64)));
    expect(isInf(math.inf(f128)));
    expect(isInf(-math.inf(f128)));
}

test "math.isPositiveInf" {
    expect(!isPositiveInf(f16(0.0)));
    expect(!isPositiveInf(f16(-0.0)));
    expect(!isPositiveInf(f32(0.0)));
    expect(!isPositiveInf(f32(-0.0)));
    expect(!isPositiveInf(f64(0.0)));
    expect(!isPositiveInf(f64(-0.0)));
    expect(!isPositiveInf(f128(0.0)));
    expect(!isPositiveInf(f128(-0.0)));
    expect(isPositiveInf(math.inf(f16)));
    expect(!isPositiveInf(-math.inf(f16)));
    expect(isPositiveInf(math.inf(f32)));
    expect(!isPositiveInf(-math.inf(f32)));
    expect(isPositiveInf(math.inf(f64)));
    expect(!isPositiveInf(-math.inf(f64)));
    expect(isPositiveInf(math.inf(f128)));
    expect(!isPositiveInf(-math.inf(f128)));
}

test "math.isNegativeInf" {
    expect(!isNegativeInf(f16(0.0)));
    expect(!isNegativeInf(f16(-0.0)));
    expect(!isNegativeInf(f32(0.0)));
    expect(!isNegativeInf(f32(-0.0)));
    expect(!isNegativeInf(f64(0.0)));
    expect(!isNegativeInf(f64(-0.0)));
    expect(!isNegativeInf(f128(0.0)));
    expect(!isNegativeInf(f128(-0.0)));
    expect(!isNegativeInf(math.inf(f16)));
    expect(isNegativeInf(-math.inf(f16)));
    expect(!isNegativeInf(math.inf(f32)));
    expect(isNegativeInf(-math.inf(f32)));
    expect(!isNegativeInf(math.inf(f64)));
    expect(isNegativeInf(-math.inf(f64)));
    expect(!isNegativeInf(math.inf(f128)));
    expect(isNegativeInf(-math.inf(f128)));
}

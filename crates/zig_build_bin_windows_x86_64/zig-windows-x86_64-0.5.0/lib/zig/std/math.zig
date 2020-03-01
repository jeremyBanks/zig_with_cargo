const builtin = @import("builtin");
const std = @import("std.zig");
const TypeId = builtin.TypeId;
const assert = std.debug.assert;
const testing = std.testing;

pub const e = 2.71828182845904523536028747135266249775724709369995;
pub const pi = 3.14159265358979323846264338327950288419716939937510;

// From a small c++ [program using boost float128](https://github.com/winksaville/cpp_boost_float128)
pub const f128_true_min = @bitCast(f128, u128(0x00000000000000000000000000000001));
pub const f128_min = @bitCast(f128, u128(0x00010000000000000000000000000000));
pub const f128_max = @bitCast(f128, u128(0x7FFEFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
pub const f128_epsilon = @bitCast(f128, u128(0x3F8F0000000000000000000000000000));
pub const f128_toint = 1.0 / f128_epsilon;

// float.h details
pub const f64_true_min = 4.94065645841246544177e-324;
pub const f64_min = 2.2250738585072014e-308;
pub const f64_max = 1.79769313486231570815e+308;
pub const f64_epsilon = 2.22044604925031308085e-16;
pub const f64_toint = 1.0 / f64_epsilon;

pub const f32_true_min = 1.40129846432481707092e-45;
pub const f32_min = 1.17549435082228750797e-38;
pub const f32_max = 3.40282346638528859812e+38;
pub const f32_epsilon = 1.1920928955078125e-07;
pub const f32_toint = 1.0 / f32_epsilon;

pub const f16_true_min = 0.000000059604644775390625; // 2**-24
pub const f16_min = 0.00006103515625; // 2**-14
pub const f16_max = 65504;
pub const f16_epsilon = 0.0009765625; // 2**-10
pub const f16_toint = 1.0 / f16_epsilon;

pub const nan_u16 = u16(0x7C01);
pub const nan_f16 = @bitCast(f16, nan_u16);

pub const inf_u16 = u16(0x7C00);
pub const inf_f16 = @bitCast(f16, inf_u16);

pub const nan_u32 = u32(0x7F800001);
pub const nan_f32 = @bitCast(f32, nan_u32);

pub const inf_u32 = u32(0x7F800000);
pub const inf_f32 = @bitCast(f32, inf_u32);

pub const nan_u64 = u64(0x7FF << 52) | 1;
pub const nan_f64 = @bitCast(f64, nan_u64);

pub const inf_u64 = u64(0x7FF << 52);
pub const inf_f64 = @bitCast(f64, inf_u64);

pub const nan_u128 = u128(0x7fff0000000000000000000000000001);
pub const nan_f128 = @bitCast(f128, nan_u128);

pub const inf_u128 = u128(0x7fff0000000000000000000000000000);
pub const inf_f128 = @bitCast(f128, inf_u128);

pub const nan = @import("math/nan.zig").nan;
pub const snan = @import("math/nan.zig").snan;
pub const inf = @import("math/inf.zig").inf;

pub fn approxEq(comptime T: type, x: T, y: T, epsilon: T) bool {
    assert(@typeId(T) == TypeId.Float);
    return fabs(x - y) < epsilon;
}

// TODO: Hide the following in an internal module.
pub fn forceEval(value: var) void {
    const T = @typeOf(value);
    switch (T) {
        f16 => {
            var x: f16 = undefined;
            const p = @ptrCast(*volatile f16, &x);
            p.* = x;
        },
        f32 => {
            var x: f32 = undefined;
            const p = @ptrCast(*volatile f32, &x);
            p.* = x;
        },
        f64 => {
            var x: f64 = undefined;
            const p = @ptrCast(*volatile f64, &x);
            p.* = x;
        },
        else => {
            @compileError("forceEval not implemented for " ++ @typeName(T));
        },
    }
}

pub fn raiseInvalid() void {
    // Raise INVALID fpu exception
}

pub fn raiseUnderflow() void {
    // Raise UNDERFLOW fpu exception
}

pub fn raiseOverflow() void {
    // Raise OVERFLOW fpu exception
}

pub fn raiseInexact() void {
    // Raise INEXACT fpu exception
}

pub fn raiseDivByZero() void {
    // Raise INEXACT fpu exception
}

pub const isNan = @import("math/isnan.zig").isNan;
pub const isSignalNan = @import("math/isnan.zig").isSignalNan;
pub const fabs = @import("math/fabs.zig").fabs;
pub const ceil = @import("math/ceil.zig").ceil;
pub const floor = @import("math/floor.zig").floor;
pub const trunc = @import("math/trunc.zig").trunc;
pub const round = @import("math/round.zig").round;
pub const frexp = @import("math/frexp.zig").frexp;
pub const frexp32_result = @import("math/frexp.zig").frexp32_result;
pub const frexp64_result = @import("math/frexp.zig").frexp64_result;
pub const modf = @import("math/modf.zig").modf;
pub const modf32_result = @import("math/modf.zig").modf32_result;
pub const modf64_result = @import("math/modf.zig").modf64_result;
pub const copysign = @import("math/copysign.zig").copysign;
pub const isFinite = @import("math/isfinite.zig").isFinite;
pub const isInf = @import("math/isinf.zig").isInf;
pub const isPositiveInf = @import("math/isinf.zig").isPositiveInf;
pub const isNegativeInf = @import("math/isinf.zig").isNegativeInf;
pub const isNormal = @import("math/isnormal.zig").isNormal;
pub const signbit = @import("math/signbit.zig").signbit;
pub const scalbn = @import("math/scalbn.zig").scalbn;
pub const pow = @import("math/pow.zig").pow;
pub const powi = @import("math/powi.zig").powi;
pub const sqrt = @import("math/sqrt.zig").sqrt;
pub const cbrt = @import("math/cbrt.zig").cbrt;
pub const acos = @import("math/acos.zig").acos;
pub const asin = @import("math/asin.zig").asin;
pub const atan = @import("math/atan.zig").atan;
pub const atan2 = @import("math/atan2.zig").atan2;
pub const hypot = @import("math/hypot.zig").hypot;
pub const exp = @import("math/exp.zig").exp;
pub const exp2 = @import("math/exp2.zig").exp2;
pub const expm1 = @import("math/expm1.zig").expm1;
pub const ilogb = @import("math/ilogb.zig").ilogb;
pub const ln = @import("math/ln.zig").ln;
pub const log = @import("math/log.zig").log;
pub const log2 = @import("math/log2.zig").log2;
pub const log10 = @import("math/log10.zig").log10;
pub const log1p = @import("math/log1p.zig").log1p;
pub const fma = @import("math/fma.zig").fma;
pub const asinh = @import("math/asinh.zig").asinh;
pub const acosh = @import("math/acosh.zig").acosh;
pub const atanh = @import("math/atanh.zig").atanh;
pub const sinh = @import("math/sinh.zig").sinh;
pub const cosh = @import("math/cosh.zig").cosh;
pub const tanh = @import("math/tanh.zig").tanh;
pub const cos = @import("math/cos.zig").cos;
pub const sin = @import("math/sin.zig").sin;
pub const tan = @import("math/tan.zig").tan;

pub const complex = @import("math/complex.zig");
pub const Complex = complex.Complex;

pub const big = @import("math/big.zig");

test "math" {
    _ = @import("math/nan.zig");
    _ = @import("math/isnan.zig");
    _ = @import("math/fabs.zig");
    _ = @import("math/ceil.zig");
    _ = @import("math/floor.zig");
    _ = @import("math/trunc.zig");
    _ = @import("math/round.zig");
    _ = @import("math/frexp.zig");
    _ = @import("math/modf.zig");
    _ = @import("math/copysign.zig");
    _ = @import("math/isfinite.zig");
    _ = @import("math/isinf.zig");
    _ = @import("math/isnormal.zig");
    _ = @import("math/signbit.zig");
    _ = @import("math/scalbn.zig");
    _ = @import("math/pow.zig");
    _ = @import("math/powi.zig");
    _ = @import("math/sqrt.zig");
    _ = @import("math/cbrt.zig");
    _ = @import("math/acos.zig");
    _ = @import("math/asin.zig");
    _ = @import("math/atan.zig");
    _ = @import("math/atan2.zig");
    _ = @import("math/hypot.zig");
    _ = @import("math/exp.zig");
    _ = @import("math/exp2.zig");
    _ = @import("math/expm1.zig");
    _ = @import("math/ilogb.zig");
    _ = @import("math/ln.zig");
    _ = @import("math/log.zig");
    _ = @import("math/log2.zig");
    _ = @import("math/log10.zig");
    _ = @import("math/log1p.zig");
    _ = @import("math/fma.zig");
    _ = @import("math/asinh.zig");
    _ = @import("math/acosh.zig");
    _ = @import("math/atanh.zig");
    _ = @import("math/sinh.zig");
    _ = @import("math/cosh.zig");
    _ = @import("math/tanh.zig");
    _ = @import("math/sin.zig");
    _ = @import("math/cos.zig");
    _ = @import("math/tan.zig");

    _ = @import("math/complex.zig");

    _ = @import("math/big.zig");
}

pub fn floatMantissaBits(comptime T: type) comptime_int {
    assert(@typeId(T) == builtin.TypeId.Float);

    return switch (T.bit_count) {
        16 => 10,
        32 => 23,
        64 => 52,
        80 => 64,
        128 => 112,
        else => @compileError("unknown floating point type " ++ @typeName(T)),
    };
}

pub fn floatExponentBits(comptime T: type) comptime_int {
    assert(@typeId(T) == builtin.TypeId.Float);

    return switch (T.bit_count) {
        16 => 5,
        32 => 8,
        64 => 11,
        80 => 15,
        128 => 15,
        else => @compileError("unknown floating point type " ++ @typeName(T)),
    };
}

/// Given two types, returns the smallest one which is capable of holding the
/// full range of the minimum value.
pub fn Min(comptime A: type, comptime B: type) type {
    switch (@typeInfo(A)) {
        .Int => |a_info| switch (@typeInfo(B)) {
            .Int => |b_info| if (!a_info.is_signed and !b_info.is_signed) {
                if (a_info.bits < b_info.bits) {
                    return A;
                } else {
                    return B;
                }
            },
            else => {},
        },
        else => {},
    }
    return @typeOf(A(0) + B(0));
}

/// Returns the smaller number. When one of the parameter's type's full range fits in the other,
/// the return type is the smaller type.
pub fn min(x: var, y: var) Min(@typeOf(x), @typeOf(y)) {
    const Result = Min(@typeOf(x), @typeOf(y));
    if (x < y) {
        // TODO Zig should allow this as an implicit cast because x is immutable and in this
        // scope it is known to fit in the return type.
        switch (@typeInfo(Result)) {
            .Int => return @intCast(Result, x),
            else => return x,
        }
    } else {
        // TODO Zig should allow this as an implicit cast because y is immutable and in this
        // scope it is known to fit in the return type.
        switch (@typeInfo(Result)) {
            .Int => return @intCast(Result, y),
            else => return y,
        }
    }
}

test "math.min" {
    testing.expect(min(i32(-1), i32(2)) == -1);
    {
        var a: u16 = 999;
        var b: u32 = 10;
        var result = min(a, b);
        testing.expect(@typeOf(result) == u16);
        testing.expect(result == 10);
    }
    {
        var a: f64 = 10.34;
        var b: f32 = 999.12;
        var result = min(a, b);
        testing.expect(@typeOf(result) == f64);
        testing.expect(result == 10.34);
    }
    {
        var a: i8 = -127;
        var b: i16 = -200;
        var result = min(a, b);
        testing.expect(@typeOf(result) == i16);
        testing.expect(result == -200);
    }
    {
        const a = 10.34;
        var b: f32 = 999.12;
        var result = min(a, b);
        testing.expect(@typeOf(result) == f32);
        testing.expect(result == 10.34);
    }
}

pub fn max(x: var, y: var) @typeOf(x + y) {
    return if (x > y) x else y;
}

test "math.max" {
    testing.expect(max(i32(-1), i32(2)) == 2);
}

pub fn mul(comptime T: type, a: T, b: T) (error{Overflow}!T) {
    var answer: T = undefined;
    return if (@mulWithOverflow(T, a, b, &answer)) error.Overflow else answer;
}

pub fn add(comptime T: type, a: T, b: T) (error{Overflow}!T) {
    var answer: T = undefined;
    return if (@addWithOverflow(T, a, b, &answer)) error.Overflow else answer;
}

pub fn sub(comptime T: type, a: T, b: T) (error{Overflow}!T) {
    var answer: T = undefined;
    return if (@subWithOverflow(T, a, b, &answer)) error.Overflow else answer;
}

pub fn negate(x: var) !@typeOf(x) {
    return sub(@typeOf(x), 0, x);
}

pub fn shlExact(comptime T: type, a: T, shift_amt: Log2Int(T)) !T {
    var answer: T = undefined;
    return if (@shlWithOverflow(T, a, shift_amt, &answer)) error.Overflow else answer;
}

/// Shifts left. Overflowed bits are truncated.
/// A negative shift amount results in a right shift.
pub fn shl(comptime T: type, a: T, shift_amt: var) T {
    const abs_shift_amt = absCast(shift_amt);
    const casted_shift_amt = if (abs_shift_amt >= T.bit_count) return 0 else @intCast(Log2Int(T), abs_shift_amt);

    if (@typeOf(shift_amt) == comptime_int or @typeOf(shift_amt).is_signed) {
        if (shift_amt < 0) {
            return a >> casted_shift_amt;
        }
    }

    return a << casted_shift_amt;
}

test "math.shl" {
    testing.expect(shl(u8, 0b11111111, usize(3)) == 0b11111000);
    testing.expect(shl(u8, 0b11111111, usize(8)) == 0);
    testing.expect(shl(u8, 0b11111111, usize(9)) == 0);
    testing.expect(shl(u8, 0b11111111, isize(-2)) == 0b00111111);
    testing.expect(shl(u8, 0b11111111, 3) == 0b11111000);
    testing.expect(shl(u8, 0b11111111, 8) == 0);
    testing.expect(shl(u8, 0b11111111, 9) == 0);
    testing.expect(shl(u8, 0b11111111, -2) == 0b00111111);
}

/// Shifts right. Overflowed bits are truncated.
/// A negative shift amount results in a left shift.
pub fn shr(comptime T: type, a: T, shift_amt: var) T {
    const abs_shift_amt = absCast(shift_amt);
    const casted_shift_amt = if (abs_shift_amt >= T.bit_count) return 0 else @intCast(Log2Int(T), abs_shift_amt);

    if (@typeOf(shift_amt) == comptime_int or @typeOf(shift_amt).is_signed) {
        if (shift_amt >= 0) {
            return a >> casted_shift_amt;
        } else {
            return a << casted_shift_amt;
        }
    }

    return a >> casted_shift_amt;
}

test "math.shr" {
    testing.expect(shr(u8, 0b11111111, usize(3)) == 0b00011111);
    testing.expect(shr(u8, 0b11111111, usize(8)) == 0);
    testing.expect(shr(u8, 0b11111111, usize(9)) == 0);
    testing.expect(shr(u8, 0b11111111, isize(-2)) == 0b11111100);
    testing.expect(shr(u8, 0b11111111, 3) == 0b00011111);
    testing.expect(shr(u8, 0b11111111, 8) == 0);
    testing.expect(shr(u8, 0b11111111, 9) == 0);
    testing.expect(shr(u8, 0b11111111, -2) == 0b11111100);
}

/// Rotates right. Only unsigned values can be rotated.
/// Negative shift values results in shift modulo the bit count.
pub fn rotr(comptime T: type, x: T, r: var) T {
    if (T.is_signed) {
        @compileError("cannot rotate signed integer");
    } else {
        const ar = @mod(r, T.bit_count);
        return shr(T, x, ar) | shl(T, x, T.bit_count - ar);
    }
}

test "math.rotr" {
    testing.expect(rotr(u8, 0b00000001, usize(0)) == 0b00000001);
    testing.expect(rotr(u8, 0b00000001, usize(9)) == 0b10000000);
    testing.expect(rotr(u8, 0b00000001, usize(8)) == 0b00000001);
    testing.expect(rotr(u8, 0b00000001, usize(4)) == 0b00010000);
    testing.expect(rotr(u8, 0b00000001, isize(-1)) == 0b00000010);
}

/// Rotates left. Only unsigned values can be rotated.
/// Negative shift values results in shift modulo the bit count.
pub fn rotl(comptime T: type, x: T, r: var) T {
    if (T.is_signed) {
        @compileError("cannot rotate signed integer");
    } else {
        const ar = @mod(r, T.bit_count);
        return shl(T, x, ar) | shr(T, x, T.bit_count - ar);
    }
}

test "math.rotl" {
    testing.expect(rotl(u8, 0b00000001, usize(0)) == 0b00000001);
    testing.expect(rotl(u8, 0b00000001, usize(9)) == 0b00000010);
    testing.expect(rotl(u8, 0b00000001, usize(8)) == 0b00000001);
    testing.expect(rotl(u8, 0b00000001, usize(4)) == 0b00010000);
    testing.expect(rotl(u8, 0b00000001, isize(-1)) == 0b10000000);
}

pub fn Log2Int(comptime T: type) type {
    // comptime ceil log2
    comptime var count = 0;
    comptime var s = T.bit_count - 1;
    inline while (s != 0) : (s >>= 1) {
        count += 1;
    }

    return @IntType(false, count);
}

pub fn IntFittingRange(comptime from: comptime_int, comptime to: comptime_int) type {
    assert(from <= to);
    if (from == 0 and to == 0) {
        return u0;
    }
    const is_signed = from < 0;
    const largest_positive_integer = max(if (from < 0) (-from) - 1 else from, to); // two's complement
    const base = log2(largest_positive_integer);
    const upper = (1 << base) - 1;
    var magnitude_bits = if (upper >= largest_positive_integer) base else base + 1;
    if (is_signed) {
        magnitude_bits += 1;
    }
    return @IntType(is_signed, magnitude_bits);
}

test "math.IntFittingRange" {
    testing.expect(IntFittingRange(0, 0) == u0);
    testing.expect(IntFittingRange(0, 1) == u1);
    testing.expect(IntFittingRange(0, 2) == u2);
    testing.expect(IntFittingRange(0, 3) == u2);
    testing.expect(IntFittingRange(0, 4) == u3);
    testing.expect(IntFittingRange(0, 7) == u3);
    testing.expect(IntFittingRange(0, 8) == u4);
    testing.expect(IntFittingRange(0, 9) == u4);
    testing.expect(IntFittingRange(0, 15) == u4);
    testing.expect(IntFittingRange(0, 16) == u5);
    testing.expect(IntFittingRange(0, 17) == u5);
    testing.expect(IntFittingRange(0, 4095) == u12);
    testing.expect(IntFittingRange(2000, 4095) == u12);
    testing.expect(IntFittingRange(0, 4096) == u13);
    testing.expect(IntFittingRange(2000, 4096) == u13);
    testing.expect(IntFittingRange(0, 4097) == u13);
    testing.expect(IntFittingRange(2000, 4097) == u13);
    testing.expect(IntFittingRange(0, 123456789123456798123456789) == u87);
    testing.expect(IntFittingRange(0, 123456789123456798123456789123456789123456798123456789) == u177);

    testing.expect(IntFittingRange(-1, -1) == i1);
    testing.expect(IntFittingRange(-1, 0) == i1);
    testing.expect(IntFittingRange(-1, 1) == i2);
    testing.expect(IntFittingRange(-2, -2) == i2);
    testing.expect(IntFittingRange(-2, -1) == i2);
    testing.expect(IntFittingRange(-2, 0) == i2);
    testing.expect(IntFittingRange(-2, 1) == i2);
    testing.expect(IntFittingRange(-2, 2) == i3);
    testing.expect(IntFittingRange(-1, 2) == i3);
    testing.expect(IntFittingRange(-1, 3) == i3);
    testing.expect(IntFittingRange(-1, 4) == i4);
    testing.expect(IntFittingRange(-1, 7) == i4);
    testing.expect(IntFittingRange(-1, 8) == i5);
    testing.expect(IntFittingRange(-1, 9) == i5);
    testing.expect(IntFittingRange(-1, 15) == i5);
    testing.expect(IntFittingRange(-1, 16) == i6);
    testing.expect(IntFittingRange(-1, 17) == i6);
    testing.expect(IntFittingRange(-1, 4095) == i13);
    testing.expect(IntFittingRange(-4096, 4095) == i13);
    testing.expect(IntFittingRange(-1, 4096) == i14);
    testing.expect(IntFittingRange(-4097, 4095) == i14);
    testing.expect(IntFittingRange(-1, 4097) == i14);
    testing.expect(IntFittingRange(-1, 123456789123456798123456789) == i88);
    testing.expect(IntFittingRange(-1, 123456789123456798123456789123456789123456798123456789) == i178);
}

test "math overflow functions" {
    testOverflow();
    comptime testOverflow();
}

fn testOverflow() void {
    testing.expect((mul(i32, 3, 4) catch unreachable) == 12);
    testing.expect((add(i32, 3, 4) catch unreachable) == 7);
    testing.expect((sub(i32, 3, 4) catch unreachable) == -1);
    testing.expect((shlExact(i32, 0b11, 4) catch unreachable) == 0b110000);
}

pub fn absInt(x: var) !@typeOf(x) {
    const T = @typeOf(x);
    comptime assert(@typeId(T) == builtin.TypeId.Int); // must pass an integer to absInt
    comptime assert(T.is_signed); // must pass a signed integer to absInt

    if (x == minInt(@typeOf(x))) {
        return error.Overflow;
    } else {
        @setRuntimeSafety(false);
        return if (x < 0) -x else x;
    }
}

test "math.absInt" {
    testAbsInt();
    comptime testAbsInt();
}
fn testAbsInt() void {
    testing.expect((absInt(i32(-10)) catch unreachable) == 10);
    testing.expect((absInt(i32(10)) catch unreachable) == 10);
}

pub const absFloat = fabs;

test "math.absFloat" {
    testAbsFloat();
    comptime testAbsFloat();
}
fn testAbsFloat() void {
    testing.expect(absFloat(f32(-10.05)) == 10.05);
    testing.expect(absFloat(f32(10.05)) == 10.05);
}

pub fn divTrunc(comptime T: type, numerator: T, denominator: T) !T {
    @setRuntimeSafety(false);
    if (denominator == 0) return error.DivisionByZero;
    if (@typeId(T) == builtin.TypeId.Int and T.is_signed and numerator == minInt(T) and denominator == -1) return error.Overflow;
    return @divTrunc(numerator, denominator);
}

test "math.divTrunc" {
    testDivTrunc();
    comptime testDivTrunc();
}
fn testDivTrunc() void {
    testing.expect((divTrunc(i32, 5, 3) catch unreachable) == 1);
    testing.expect((divTrunc(i32, -5, 3) catch unreachable) == -1);
    testing.expectError(error.DivisionByZero, divTrunc(i8, -5, 0));
    testing.expectError(error.Overflow, divTrunc(i8, -128, -1));

    testing.expect((divTrunc(f32, 5.0, 3.0) catch unreachable) == 1.0);
    testing.expect((divTrunc(f32, -5.0, 3.0) catch unreachable) == -1.0);
}

pub fn divFloor(comptime T: type, numerator: T, denominator: T) !T {
    @setRuntimeSafety(false);
    if (denominator == 0) return error.DivisionByZero;
    if (@typeId(T) == builtin.TypeId.Int and T.is_signed and numerator == minInt(T) and denominator == -1) return error.Overflow;
    return @divFloor(numerator, denominator);
}

test "math.divFloor" {
    testDivFloor();
    comptime testDivFloor();
}
fn testDivFloor() void {
    testing.expect((divFloor(i32, 5, 3) catch unreachable) == 1);
    testing.expect((divFloor(i32, -5, 3) catch unreachable) == -2);
    testing.expectError(error.DivisionByZero, divFloor(i8, -5, 0));
    testing.expectError(error.Overflow, divFloor(i8, -128, -1));

    testing.expect((divFloor(f32, 5.0, 3.0) catch unreachable) == 1.0);
    testing.expect((divFloor(f32, -5.0, 3.0) catch unreachable) == -2.0);
}

pub fn divExact(comptime T: type, numerator: T, denominator: T) !T {
    @setRuntimeSafety(false);
    if (denominator == 0) return error.DivisionByZero;
    if (@typeId(T) == builtin.TypeId.Int and T.is_signed and numerator == minInt(T) and denominator == -1) return error.Overflow;
    const result = @divTrunc(numerator, denominator);
    if (result * denominator != numerator) return error.UnexpectedRemainder;
    return result;
}

test "math.divExact" {
    testDivExact();
    comptime testDivExact();
}
fn testDivExact() void {
    testing.expect((divExact(i32, 10, 5) catch unreachable) == 2);
    testing.expect((divExact(i32, -10, 5) catch unreachable) == -2);
    testing.expectError(error.DivisionByZero, divExact(i8, -5, 0));
    testing.expectError(error.Overflow, divExact(i8, -128, -1));
    testing.expectError(error.UnexpectedRemainder, divExact(i32, 5, 2));

    testing.expect((divExact(f32, 10.0, 5.0) catch unreachable) == 2.0);
    testing.expect((divExact(f32, -10.0, 5.0) catch unreachable) == -2.0);
    testing.expectError(error.UnexpectedRemainder, divExact(f32, 5.0, 2.0));
}

pub fn mod(comptime T: type, numerator: T, denominator: T) !T {
    @setRuntimeSafety(false);
    if (denominator == 0) return error.DivisionByZero;
    if (denominator < 0) return error.NegativeDenominator;
    return @mod(numerator, denominator);
}

test "math.mod" {
    testMod();
    comptime testMod();
}
fn testMod() void {
    testing.expect((mod(i32, -5, 3) catch unreachable) == 1);
    testing.expect((mod(i32, 5, 3) catch unreachable) == 2);
    testing.expectError(error.NegativeDenominator, mod(i32, 10, -1));
    testing.expectError(error.DivisionByZero, mod(i32, 10, 0));

    testing.expect((mod(f32, -5, 3) catch unreachable) == 1);
    testing.expect((mod(f32, 5, 3) catch unreachable) == 2);
    testing.expectError(error.NegativeDenominator, mod(f32, 10, -1));
    testing.expectError(error.DivisionByZero, mod(f32, 10, 0));
}

pub fn rem(comptime T: type, numerator: T, denominator: T) !T {
    @setRuntimeSafety(false);
    if (denominator == 0) return error.DivisionByZero;
    if (denominator < 0) return error.NegativeDenominator;
    return @rem(numerator, denominator);
}

test "math.rem" {
    testRem();
    comptime testRem();
}
fn testRem() void {
    testing.expect((rem(i32, -5, 3) catch unreachable) == -2);
    testing.expect((rem(i32, 5, 3) catch unreachable) == 2);
    testing.expectError(error.NegativeDenominator, rem(i32, 10, -1));
    testing.expectError(error.DivisionByZero, rem(i32, 10, 0));

    testing.expect((rem(f32, -5, 3) catch unreachable) == -2);
    testing.expect((rem(f32, 5, 3) catch unreachable) == 2);
    testing.expectError(error.NegativeDenominator, rem(f32, 10, -1));
    testing.expectError(error.DivisionByZero, rem(f32, 10, 0));
}

/// Returns the absolute value of the integer parameter.
/// Result is an unsigned integer.
pub fn absCast(x: var) t: {
    if (@typeOf(x) == comptime_int) {
        break :t comptime_int;
    } else {
        break :t @IntType(false, @typeOf(x).bit_count);
    }
} {
    if (@typeOf(x) == comptime_int) {
        return if (x < 0) -x else x;
    }
    const uint = @IntType(false, @typeOf(x).bit_count);
    if (x >= 0) return @intCast(uint, x);

    return @intCast(uint, -(x + 1)) + 1;
}

test "math.absCast" {
    testing.expect(absCast(i32(-999)) == 999);
    testing.expect(@typeOf(absCast(i32(-999))) == u32);

    testing.expect(absCast(i32(999)) == 999);
    testing.expect(@typeOf(absCast(i32(999))) == u32);

    testing.expect(absCast(i32(minInt(i32))) == -minInt(i32));
    testing.expect(@typeOf(absCast(i32(minInt(i32)))) == u32);

    testing.expect(absCast(-999) == 999);
}

/// Returns the negation of the integer parameter.
/// Result is a signed integer.
pub fn negateCast(x: var) !@IntType(true, @typeOf(x).bit_count) {
    if (@typeOf(x).is_signed) return negate(x);

    const int = @IntType(true, @typeOf(x).bit_count);
    if (x > -minInt(int)) return error.Overflow;

    if (x == -minInt(int)) return minInt(int);

    return -@intCast(int, x);
}

test "math.negateCast" {
    testing.expect((negateCast(u32(999)) catch unreachable) == -999);
    testing.expect(@typeOf(negateCast(u32(999)) catch unreachable) == i32);

    testing.expect((negateCast(u32(-minInt(i32))) catch unreachable) == minInt(i32));
    testing.expect(@typeOf(negateCast(u32(-minInt(i32))) catch unreachable) == i32);

    testing.expectError(error.Overflow, negateCast(u32(maxInt(i32) + 10)));
}

/// Cast an integer to a different integer type. If the value doesn't fit,
/// return an error.
pub fn cast(comptime T: type, x: var) (error{Overflow}!T) {
    comptime assert(@typeId(T) == builtin.TypeId.Int); // must pass an integer
    comptime assert(@typeId(@typeOf(x)) == builtin.TypeId.Int); // must pass an integer
    if (maxInt(@typeOf(x)) > maxInt(T) and x > maxInt(T)) {
        return error.Overflow;
    } else if (minInt(@typeOf(x)) < minInt(T) and x < minInt(T)) {
        return error.Overflow;
    } else {
        return @intCast(T, x);
    }
}

test "math.cast" {
    testing.expectError(error.Overflow, cast(u8, u32(300)));
    testing.expectError(error.Overflow, cast(i8, i32(-200)));
    testing.expectError(error.Overflow, cast(u8, i8(-1)));
    testing.expectError(error.Overflow, cast(u64, i8(-1)));

    testing.expect((try cast(u8, u32(255))) == u8(255));
    testing.expect(@typeOf(try cast(u8, u32(255))) == u8);
}

pub const AlignCastError = error{UnalignedMemory};

/// Align cast a pointer but return an error if it's the wrong alignment
pub fn alignCast(comptime alignment: u29, ptr: var) AlignCastError!@typeOf(@alignCast(alignment, ptr)) {
    const addr = @ptrToInt(ptr);
    if (addr % alignment != 0) {
        return error.UnalignedMemory;
    }
    return @alignCast(alignment, ptr);
}

pub fn isPowerOfTwo(v: var) bool {
    assert(v != 0);
    return (v & (v - 1)) == 0;
}

pub fn floorPowerOfTwo(comptime T: type, value: T) T {
    var x = value;

    comptime var i = 1;
    inline while (T.bit_count > i) : (i *= 2) {
        x |= (x >> i);
    }

    return x - (x >> 1);
}

test "math.floorPowerOfTwo" {
    testFloorPowerOfTwo();
    comptime testFloorPowerOfTwo();
}

fn testFloorPowerOfTwo() void {
    testing.expect(floorPowerOfTwo(u32, 63) == 32);
    testing.expect(floorPowerOfTwo(u32, 64) == 64);
    testing.expect(floorPowerOfTwo(u32, 65) == 64);
    testing.expect(floorPowerOfTwo(u4, 7) == 4);
    testing.expect(floorPowerOfTwo(u4, 8) == 8);
    testing.expect(floorPowerOfTwo(u4, 9) == 8);
}

/// Returns the next power of two (if the value is not already a power of two).
/// Only unsigned integers can be used. Zero is not an allowed input.
/// Result is a type with 1 more bit than the input type.
pub fn ceilPowerOfTwoPromote(comptime T: type, value: T) @IntType(T.is_signed, T.bit_count + 1) {
    comptime assert(@typeId(T) == builtin.TypeId.Int);
    comptime assert(!T.is_signed);
    assert(value != 0);
    comptime const promotedType = @IntType(T.is_signed, T.bit_count + 1);
    comptime const shiftType = std.math.Log2Int(promotedType);
    return promotedType(1) << @intCast(shiftType, T.bit_count - @clz(T, value - 1));
}

/// Returns the next power of two (if the value is not already a power of two).
/// Only unsigned integers can be used. Zero is not an allowed input.
/// If the value doesn't fit, returns an error.
pub fn ceilPowerOfTwo(comptime T: type, value: T) (error{Overflow}!T) {
    comptime assert(@typeId(T) == builtin.TypeId.Int);
    comptime assert(!T.is_signed);
    comptime const promotedType = @IntType(T.is_signed, T.bit_count + 1);
    comptime const overflowBit = promotedType(1) << T.bit_count;
    var x = ceilPowerOfTwoPromote(T, value);
    if (overflowBit & x != 0) {
        return error.Overflow;
    }
    return @intCast(T, x);
}

test "math.ceilPowerOfTwoPromote" {
    testCeilPowerOfTwoPromote();
    comptime testCeilPowerOfTwoPromote();
}

fn testCeilPowerOfTwoPromote() void {
    testing.expectEqual(u33(1), ceilPowerOfTwoPromote(u32, 1));
    testing.expectEqual(u33(2), ceilPowerOfTwoPromote(u32, 2));
    testing.expectEqual(u33(64), ceilPowerOfTwoPromote(u32, 63));
    testing.expectEqual(u33(64), ceilPowerOfTwoPromote(u32, 64));
    testing.expectEqual(u33(128), ceilPowerOfTwoPromote(u32, 65));
    testing.expectEqual(u6(8), ceilPowerOfTwoPromote(u5, 7));
    testing.expectEqual(u6(8), ceilPowerOfTwoPromote(u5, 8));
    testing.expectEqual(u6(16), ceilPowerOfTwoPromote(u5, 9));
    testing.expectEqual(u5(16), ceilPowerOfTwoPromote(u4, 9));
}

test "math.ceilPowerOfTwo" {
    try testCeilPowerOfTwo();
    comptime try testCeilPowerOfTwo();
}

fn testCeilPowerOfTwo() !void {
    testing.expectEqual(u32(1), try ceilPowerOfTwo(u32, 1));
    testing.expectEqual(u32(2), try ceilPowerOfTwo(u32, 2));
    testing.expectEqual(u32(64), try ceilPowerOfTwo(u32, 63));
    testing.expectEqual(u32(64), try ceilPowerOfTwo(u32, 64));
    testing.expectEqual(u32(128), try ceilPowerOfTwo(u32, 65));
    testing.expectEqual(u5(8), try ceilPowerOfTwo(u5, 7));
    testing.expectEqual(u5(8), try ceilPowerOfTwo(u5, 8));
    testing.expectEqual(u5(16), try ceilPowerOfTwo(u5, 9));
    testing.expectError(error.Overflow, ceilPowerOfTwo(u4, 9));
}

pub fn log2_int(comptime T: type, x: T) Log2Int(T) {
    assert(x != 0);
    return @intCast(Log2Int(T), T.bit_count - 1 - @clz(T, x));
}

pub fn log2_int_ceil(comptime T: type, x: T) Log2Int(T) {
    assert(x != 0);
    const log2_val = log2_int(T, x);
    if (T(1) << log2_val == x)
        return log2_val;
    return log2_val + 1;
}

test "std.math.log2_int_ceil" {
    testing.expect(log2_int_ceil(u32, 1) == 0);
    testing.expect(log2_int_ceil(u32, 2) == 1);
    testing.expect(log2_int_ceil(u32, 3) == 2);
    testing.expect(log2_int_ceil(u32, 4) == 2);
    testing.expect(log2_int_ceil(u32, 5) == 3);
    testing.expect(log2_int_ceil(u32, 6) == 3);
    testing.expect(log2_int_ceil(u32, 7) == 3);
    testing.expect(log2_int_ceil(u32, 8) == 3);
    testing.expect(log2_int_ceil(u32, 9) == 4);
    testing.expect(log2_int_ceil(u32, 10) == 4);
}

pub fn lossyCast(comptime T: type, value: var) T {
    switch (@typeInfo(@typeOf(value))) {
        builtin.TypeId.Int => return @intToFloat(T, value),
        builtin.TypeId.Float => return @floatCast(T, value),
        builtin.TypeId.ComptimeInt => return T(value),
        builtin.TypeId.ComptimeFloat => return T(value),
        else => @compileError("bad type"),
    }
}

test "math.f64_min" {
    const f64_min_u64 = 0x0010000000000000;
    const fmin: f64 = f64_min;
    testing.expect(@bitCast(u64, fmin) == f64_min_u64);
}

pub fn maxInt(comptime T: type) comptime_int {
    const info = @typeInfo(T);
    const bit_count = info.Int.bits;
    if (bit_count == 0) return 0;
    return (1 << (bit_count - @boolToInt(info.Int.is_signed))) - 1;
}

pub fn minInt(comptime T: type) comptime_int {
    const info = @typeInfo(T);
    const bit_count = info.Int.bits;
    if (!info.Int.is_signed) return 0;
    if (bit_count == 0) return 0;
    return -(1 << (bit_count - 1));
}

test "minInt and maxInt" {
    testing.expect(maxInt(u0) == 0);
    testing.expect(maxInt(u1) == 1);
    testing.expect(maxInt(u8) == 255);
    testing.expect(maxInt(u16) == 65535);
    testing.expect(maxInt(u32) == 4294967295);
    testing.expect(maxInt(u64) == 18446744073709551615);
    testing.expect(maxInt(u128) == 340282366920938463463374607431768211455);

    testing.expect(maxInt(i0) == 0);
    testing.expect(maxInt(i1) == 0);
    testing.expect(maxInt(i8) == 127);
    testing.expect(maxInt(i16) == 32767);
    testing.expect(maxInt(i32) == 2147483647);
    testing.expect(maxInt(i63) == 4611686018427387903);
    testing.expect(maxInt(i64) == 9223372036854775807);
    testing.expect(maxInt(i128) == 170141183460469231731687303715884105727);

    testing.expect(minInt(u0) == 0);
    testing.expect(minInt(u1) == 0);
    testing.expect(minInt(u8) == 0);
    testing.expect(minInt(u16) == 0);
    testing.expect(minInt(u32) == 0);
    testing.expect(minInt(u63) == 0);
    testing.expect(minInt(u64) == 0);
    testing.expect(minInt(u128) == 0);

    testing.expect(minInt(i0) == 0);
    testing.expect(minInt(i1) == -1);
    testing.expect(minInt(i8) == -128);
    testing.expect(minInt(i16) == -32768);
    testing.expect(minInt(i32) == -2147483648);
    testing.expect(minInt(i63) == -4611686018427387904);
    testing.expect(minInt(i64) == -9223372036854775808);
    testing.expect(minInt(i128) == -170141183460469231731687303715884105728);
}

test "max value type" {
    // If the type of maxInt(i32) was i32 then this implicit cast to
    // u32 would not work. But since the value is a number literal,
    // it works fine.
    const x: u32 = maxInt(i32);
    testing.expect(x == 2147483647);
}

pub fn mulWide(comptime T: type, a: T, b: T) @IntType(T.is_signed, T.bit_count * 2) {
    const ResultInt = @IntType(T.is_signed, T.bit_count * 2);
    return ResultInt(a) * ResultInt(b);
}

test "math.mulWide" {
    testing.expect(mulWide(u8, 5, 5) == 25);
    testing.expect(mulWide(i8, 5, -5) == -25);
    testing.expect(mulWide(u8, 100, 100) == 10000);
}

// Ported from go, which is licensed under a BSD-3 license.
// https://golang.org/LICENSE
//
// https://golang.org/src/math/pow.go

const builtin = @import("builtin");
const std = @import("../std.zig");
const math = std.math;
const expect = std.testing.expect;

/// Returns x raised to the power of y (x^y).
///
/// Special Cases:
///  - pow(x, +-0)    = 1 for any x
///  - pow(1, y)      = 1 for any y
///  - pow(x, 1)      = x for any x
///  - pow(nan, y)    = nan
///  - pow(x, nan)    = nan
///  - pow(+-0, y)    = +-inf for y an odd integer < 0
///  - pow(+-0, -inf) = +inf
///  - pow(+-0, +inf) = +0
///  - pow(+-0, y)    = +inf for finite y < 0 and not an odd integer
///  - pow(+-0, y)    = +-0 for y an odd integer > 0
///  - pow(+-0, y)    = +0 for finite y > 0 and not an odd integer
///  - pow(-1, +-inf) = 1
///  - pow(x, +inf)   = +inf for |x| > 1
///  - pow(x, -inf)   = +0 for |x| > 1
///  - pow(x, +inf)   = +0 for |x| < 1
///  - pow(x, -inf)   = +inf for |x| < 1
///  - pow(+inf, y)   = +inf for y > 0
///  - pow(+inf, y)   = +0 for y < 0
///  - pow(-inf, y)   = pow(-0, -y)
///  - pow(x, y)      = nan for finite x < 0 and finite non-integer y
pub fn pow(comptime T: type, x: T, y: T) T {
    if (@typeInfo(T) == builtin.TypeId.Int) {
        return math.powi(T, x, y) catch unreachable;
    }

    if (T != f32 and T != f64) {
        @compileError("pow not implemented for " ++ @typeName(T));
    }

    // pow(x, +-0) = 1      for all x
    // pow(1, y) = 1        for all y
    if (y == 0 or x == 1) {
        return 1;
    }

    // pow(nan, y) = nan    for all y
    // pow(x, nan) = nan    for all x
    if (math.isNan(x) or math.isNan(y)) {
        return math.nan(T);
    }

    // pow(x, 1) = x        for all x
    if (y == 1) {
        return x;
    }

    if (x == 0) {
        if (y < 0) {
            // pow(+-0, y) = +- 0   for y an odd integer
            if (isOddInteger(y)) {
                return math.copysign(T, math.inf(T), x);
            }
            // pow(+-0, y) = +inf   for y an even integer
            else {
                return math.inf(T);
            }
        } else {
            if (isOddInteger(y)) {
                return x;
            } else {
                return 0;
            }
        }
    }

    if (math.isInf(y)) {
        // pow(-1, inf) = 1     for all x
        if (x == -1) {
            return 1.0;
        }
        // pow(x, +inf) = +0    for |x| < 1
        // pow(x, -inf) = +0    for |x| > 1
        else if ((math.fabs(x) < 1) == math.isPositiveInf(y)) {
            return 0;
        }
        // pow(x, -inf) = +inf  for |x| < 1
        // pow(x, +inf) = +inf  for |x| > 1
        else {
            return math.inf(T);
        }
    }

    if (math.isInf(x)) {
        if (math.isNegativeInf(x)) {
            return pow(T, 1 / x, -y);
        }
        // pow(+inf, y) = +0    for y < 0
        else if (y < 0) {
            return 0;
        }
        // pow(+inf, y) = +0    for y > 0
        else if (y > 0) {
            return math.inf(T);
        }
    }

    // special case sqrt
    if (y == 0.5) {
        return math.sqrt(x);
    }

    if (y == -0.5) {
        return 1 / math.sqrt(x);
    }

    const r1 = math.modf(math.fabs(y));
    var yi = r1.ipart;
    var yf = r1.fpart;

    if (yf != 0 and x < 0) {
        return math.nan(T);
    }
    if (yi >= 1 << (T.bit_count - 1)) {
        return math.exp(y * math.ln(x));
    }

    // a = a1 * 2^ae
    var a1: T = 1.0;
    var ae: i32 = 0;

    // a *= x^yf
    if (yf != 0) {
        if (yf > 0.5) {
            yf -= 1;
            yi += 1;
        }
        a1 = math.exp(yf * math.ln(x));
    }

    // a *= x^yi
    const r2 = math.frexp(x);
    var xe = r2.exponent;
    var x1 = r2.significand;

    var i = @floatToInt(@IntType(true, T.bit_count), yi);
    while (i != 0) : (i >>= 1) {
        const overflow_shift = math.floatExponentBits(T) + 1;
        if (xe < -(1 << overflow_shift) or (1 << overflow_shift) < xe) {
            // catch xe before it overflows the left shift below
            // Since i != 0 it has at least one bit still set, so ae will accumulate xe
            // on at least one more iteration, ae += xe is a lower bound on ae
            // the lower bound on ae exceeds the size of a float exp
            // so the final call to Ldexp will produce under/overflow (0/Inf)
            ae += xe;
            break;
        }
        if (i & 1 == 1) {
            a1 *= x1;
            ae += xe;
        }
        x1 *= x1;
        xe <<= 1;
        if (x1 < 0.5) {
            x1 += x1;
            xe -= 1;
        }
    }

    // a *= a1 * 2^ae
    if (y < 0) {
        a1 = 1 / a1;
        ae = -ae;
    }

    return math.scalbn(a1, ae);
}

fn isOddInteger(x: f64) bool {
    const r = math.modf(x);
    return r.fpart == 0.0 and @floatToInt(i64, r.ipart) & 1 == 1;
}

test "math.pow" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    const epsilon = 0.000001;

    expect(math.approxEq(f32, pow(f32, 0.0, 3.3), 0.0, epsilon));
    expect(math.approxEq(f32, pow(f32, 0.8923, 3.3), 0.686572, epsilon));
    expect(math.approxEq(f32, pow(f32, 0.2, 3.3), 0.004936, epsilon));
    expect(math.approxEq(f32, pow(f32, 1.5, 3.3), 3.811546, epsilon));
    expect(math.approxEq(f32, pow(f32, 37.45, 3.3), 155736.703125, epsilon));
    expect(math.approxEq(f32, pow(f32, 89.123, 3.3), 2722489.5, epsilon));

    expect(math.approxEq(f64, pow(f64, 0.0, 3.3), 0.0, epsilon));
    expect(math.approxEq(f64, pow(f64, 0.8923, 3.3), 0.686572, epsilon));
    expect(math.approxEq(f64, pow(f64, 0.2, 3.3), 0.004936, epsilon));
    expect(math.approxEq(f64, pow(f64, 1.5, 3.3), 3.811546, epsilon));
    expect(math.approxEq(f64, pow(f64, 37.45, 3.3), 155736.7160616, epsilon));
    expect(math.approxEq(f64, pow(f64, 89.123, 3.3), 2722490.231436, epsilon));
}

test "math.pow.special" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    const epsilon = 0.000001;

    expect(pow(f32, 4, 0.0) == 1.0);
    expect(pow(f32, 7, -0.0) == 1.0);
    expect(pow(f32, 45, 1.0) == 45);
    expect(pow(f32, -45, 1.0) == -45);
    expect(math.isNan(pow(f32, math.nan(f32), 5.0)));
    expect(math.isPositiveInf(pow(f32, -math.inf(f32), 0.5)));
    expect(math.isPositiveInf(pow(f32, -0, -0.5)));
    expect(pow(f32, -0, 0.5) == 0);
    expect(math.isNan(pow(f32, 5.0, math.nan(f32))));
    expect(math.isPositiveInf(pow(f32, 0.0, -1.0)));
    //expect(math.isNegativeInf(pow(f32, -0.0, -3.0))); TODO is this required?
    expect(math.isPositiveInf(pow(f32, 0.0, -math.inf(f32))));
    expect(math.isPositiveInf(pow(f32, -0.0, -math.inf(f32))));
    expect(pow(f32, 0.0, math.inf(f32)) == 0.0);
    expect(pow(f32, -0.0, math.inf(f32)) == 0.0);
    expect(math.isPositiveInf(pow(f32, 0.0, -2.0)));
    expect(math.isPositiveInf(pow(f32, -0.0, -2.0)));
    expect(pow(f32, 0.0, 1.0) == 0.0);
    expect(pow(f32, -0.0, 1.0) == -0.0);
    expect(pow(f32, 0.0, 2.0) == 0.0);
    expect(pow(f32, -0.0, 2.0) == 0.0);
    expect(math.approxEq(f32, pow(f32, -1.0, math.inf(f32)), 1.0, epsilon));
    expect(math.approxEq(f32, pow(f32, -1.0, -math.inf(f32)), 1.0, epsilon));
    expect(math.isPositiveInf(pow(f32, 1.2, math.inf(f32))));
    expect(math.isPositiveInf(pow(f32, -1.2, math.inf(f32))));
    expect(pow(f32, 1.2, -math.inf(f32)) == 0.0);
    expect(pow(f32, -1.2, -math.inf(f32)) == 0.0);
    expect(pow(f32, 0.2, math.inf(f32)) == 0.0);
    expect(pow(f32, -0.2, math.inf(f32)) == 0.0);
    expect(math.isPositiveInf(pow(f32, 0.2, -math.inf(f32))));
    expect(math.isPositiveInf(pow(f32, -0.2, -math.inf(f32))));
    expect(math.isPositiveInf(pow(f32, math.inf(f32), 1.0)));
    expect(pow(f32, math.inf(f32), -1.0) == 0.0);
    //expect(pow(f32, -math.inf(f32), 5.0) == pow(f32, -0.0, -5.0)); TODO support negative 0?
    expect(pow(f32, -math.inf(f32), -5.2) == pow(f32, -0.0, 5.2));
    expect(math.isNan(pow(f32, -1.0, 1.2)));
    expect(math.isNan(pow(f32, -12.4, 78.5)));
}

test "math.pow.overflow" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    expect(math.isPositiveInf(pow(f64, 2, 1 << 32)));
    expect(pow(f64, 2, -(1 << 32)) == 0);
    expect(math.isNegativeInf(pow(f64, -2, (1 << 32) + 1)));
    expect(pow(f64, 0.5, 1 << 45) == 0);
    expect(math.isPositiveInf(pow(f64, 0.5, -(1 << 45))));
}

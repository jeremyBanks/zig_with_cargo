const std = @import("../../std.zig");
const testing = std.testing;
const math = std.math;
const cmath = math.complex;
const Complex = cmath.Complex;

/// Returns the hyperbolic arc-cosine of z.
pub fn acosh(z: var) Complex(@typeOf(z.re)) {
    const T = @typeOf(z.re);
    const q = cmath.acos(z);
    return Complex(T).new(-q.im, q.re);
}

const epsilon = 0.0001;

test "complex.cacosh" {
    const a = Complex(f32).new(5, 3);
    const c = acosh(a);

    testing.expect(math.approxEq(f32, c.re, 2.452914, epsilon));
    testing.expect(math.approxEq(f32, c.im, 0.546975, epsilon));
}

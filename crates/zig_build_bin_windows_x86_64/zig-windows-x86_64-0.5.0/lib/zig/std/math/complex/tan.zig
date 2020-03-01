const std = @import("../../std.zig");
const testing = std.testing;
const math = std.math;
const cmath = math.complex;
const Complex = cmath.Complex;

/// Returns the tanget of z.
pub fn tan(z: var) Complex(@typeOf(z.re)) {
    const T = @typeOf(z.re);
    const q = Complex(T).new(-z.im, z.re);
    const r = cmath.tanh(q);
    return Complex(T).new(r.im, -r.re);
}

const epsilon = 0.0001;

test "complex.ctan" {
    const a = Complex(f32).new(5, 3);
    const c = tan(a);

    testing.expect(math.approxEq(f32, c.re, -0.002708233, epsilon));
    testing.expect(math.approxEq(f32, c.im, 1.004165, epsilon));
}

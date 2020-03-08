const std = @import("../../std.zig");
const testing = std.testing;
const math = std.math;
const cmath = math.complex;
const Complex = cmath.Complex;

/// Returns the cosine of z.
pub fn cos(z: var) Complex(@TypeOf(z.re)) {
    const T = @TypeOf(z.re);
    const p = Complex(T).new(-z.im, z.re);
    return cmath.cosh(p);
}

const epsilon = 0.0001;

test "complex.ccos" {
    const a = Complex(f32).new(5, 3);
    const c = cos(a);

    testing.expect(math.approxEq(f32, c.re, 2.855815, epsilon));
    testing.expect(math.approxEq(f32, c.im, 9.606383, epsilon));
}

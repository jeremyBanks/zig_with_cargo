// Adapted from https://github.com/grzegorz-kraszewski/stringtofloat.

// MIT License
//
// Copyright (c) 2016 Grzegorz Kraszewski
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

// Be aware that this implementation has the following limitations:
//
// - Is not round-trip accurate for all values
// - Only supports round-to-zero
// - Does not handle denormals

const std = @import("../std.zig");

const max_digits = 25;

const f64_plus_zero: u64 = 0x0000000000000000;
const f64_minus_zero: u64 = 0x8000000000000000;
const f64_plus_infinity: u64 = 0x7FF0000000000000;
const f64_minus_infinity: u64 = 0xFFF0000000000000;

const Z96 = struct {
    d0: u32,
    d1: u32,
    d2: u32,

    // d = s >> 1
    inline fn shiftRight1(d: *Z96, s: Z96) void {
        d.d0 = (s.d0 >> 1) | ((s.d1 & 1) << 31);
        d.d1 = (s.d1 >> 1) | ((s.d2 & 1) << 31);
        d.d2 = s.d2 >> 1;
    }

    // d = s << 1
    inline fn shiftLeft1(d: *Z96, s: Z96) void {
        d.d2 = (s.d2 << 1) | ((s.d1 & (1 << 31)) >> 31);
        d.d1 = (s.d1 << 1) | ((s.d0 & (1 << 31)) >> 31);
        d.d0 = s.d0 << 1;
    }

    // d += s
    inline fn add(d: *Z96, s: Z96) void {
        var w = @as(u64, d.d0) + @as(u64, s.d0);
        d.d0 = @truncate(u32, w);

        w >>= 32;
        w += @as(u64, d.d1) + @as(u64, s.d1);
        d.d1 = @truncate(u32, w);

        w >>= 32;
        w += @as(u64, d.d2) + @as(u64, s.d2);
        d.d2 = @truncate(u32, w);
    }

    // d -= s
    inline fn sub(d: *Z96, s: Z96) void {
        var w = @as(u64, d.d0) -% @as(u64, s.d0);
        d.d0 = @truncate(u32, w);

        w >>= 32;
        w += @as(u64, d.d1) -% @as(u64, s.d1);
        d.d1 = @truncate(u32, w);

        w >>= 32;
        w += @as(u64, d.d2) -% @as(u64, s.d2);
        d.d2 = @truncate(u32, w);
    }
};

const FloatRepr = struct {
    negative: bool,
    exponent: i32,
    mantissa: u64,
};

fn convertRepr(comptime T: type, n: FloatRepr) T {
    const mask28: u32 = 0xf << 28;

    var s: Z96 = undefined;
    var q: Z96 = undefined;
    var r: Z96 = undefined;

    s.d0 = @truncate(u32, n.mantissa);
    s.d1 = @truncate(u32, n.mantissa >> 32);
    s.d2 = 0;

    var binary_exponent: i32 = 92;
    var exp = n.exponent;

    while (exp > 0) : (exp -= 1) {
        q.shiftLeft1(s); // q = p << 1
        r.shiftLeft1(q); // r = p << 2
        s.shiftLeft1(r); // p = p << 3
        s.add(q); // p = (p << 3) + (p << 1)

        while (s.d2 & mask28 != 0) {
            q.shiftRight1(s);
            binary_exponent += 1;
            s = q;
        }
    }

    while (exp < 0) {
        while (s.d2 & (1 << 31) == 0) {
            q.shiftLeft1(s);
            binary_exponent -= 1;
            s = q;
        }

        q.d2 = s.d2 / 10;
        r.d1 = s.d2 % 10;
        r.d2 = (s.d1 >> 8) | (r.d1 << 24);
        q.d1 = r.d2 / 10;
        r.d1 = r.d2 % 10;
        r.d2 = ((s.d1 & 0xff) << 16) | (s.d0 >> 16) | (r.d1 << 24);
        r.d0 = r.d2 / 10;
        r.d1 = r.d2 % 10;
        q.d1 = (q.d1 << 8) | ((r.d0 & 0x00ff0000) >> 16);
        q.d0 = r.d0 << 16;
        r.d2 = (s.d0 *% 0xffff) | (r.d1 << 16);
        q.d0 |= r.d2 / 10;
        s = q;

        exp += 1;
    }

    if (s.d0 != 0 or s.d1 != 0 or s.d2 != 0) {
        while (s.d2 & mask28 == 0) {
            q.shiftLeft1(s);
            binary_exponent -= 1;
            s = q;
        }
    }

    binary_exponent += 1023;

    const repr: u64 = blk: {
        if (binary_exponent > 2046) {
            break :blk if (n.negative) f64_minus_infinity else f64_plus_infinity;
        } else if (binary_exponent < 1) {
            break :blk if (n.negative) f64_minus_zero else f64_plus_zero;
        } else if (s.d2 != 0) {
            const binexs2 = @intCast(u64, binary_exponent) << 52;
            const rr = (@as(u64, s.d2 & ~mask28) << 24) | ((@as(u64, s.d1) + 128) >> 8) | binexs2;
            break :blk if (n.negative) rr | (1 << 63) else rr;
        } else {
            break :blk 0;
        }
    };

    const f = @bitCast(f64, repr);
    return @floatCast(T, f);
}

const State = enum {
    MaybeSign,
    LeadingMantissaZeros,
    LeadingFractionalZeros,
    MantissaIntegral,
    MantissaFractional,
    ExponentSign,
    LeadingExponentZeros,
    Exponent,
};

const ParseResult = enum {
    Ok,
    PlusZero,
    MinusZero,
    PlusInf,
    MinusInf,
};

inline fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

inline fn isSpace(c: u8) bool {
    return (c >= 0x09 and c <= 0x13) or c == 0x20;
}

fn parseRepr(s: []const u8, n: *FloatRepr) !ParseResult {
    var digit_index: usize = 0;
    var negative = false;
    var negative_exp = false;
    var exponent: i32 = 0;

    var state = State.MaybeSign;

    var i: usize = 0;
    loop: while (i < s.len) {
        const c = s[i];

        switch (state) {
            State.MaybeSign => {
                state = State.LeadingMantissaZeros;

                if (c == '+') {
                    i += 1;
                } else if (c == '-') {
                    n.negative = true;
                    i += 1;
                } else if (isDigit(c) or c == '.') {
                    // continue
                } else {
                    return error.InvalidCharacter;
                }
            },

            State.LeadingMantissaZeros => {
                if (c == '0') {
                    i += 1;
                } else if (c == '.') {
                    i += 1;
                    state = State.LeadingFractionalZeros;
                } else {
                    state = State.MantissaIntegral;
                }
            },

            State.LeadingFractionalZeros => {
                if (c == '0') {
                    i += 1;
                    if (n.exponent > std.math.minInt(i32)) {
                        n.exponent -= 1;
                    }
                } else {
                    state = State.MantissaFractional;
                }
            },

            State.MantissaIntegral => {
                if (isDigit(c)) {
                    if (digit_index < max_digits) {
                        n.mantissa *%= 10;
                        n.mantissa += s[i] - '0';
                        digit_index += 1;
                    } else if (n.exponent < std.math.maxInt(i32)) {
                        n.exponent += 1;
                    }

                    i += 1;
                } else if (c == '.') {
                    i += 1;
                    state = State.MantissaFractional;
                } else {
                    state = State.MantissaFractional;
                }
            },

            State.MantissaFractional => {
                if (isDigit(c)) {
                    if (digit_index < max_digits) {
                        n.mantissa *%= 10;
                        n.mantissa += c - '0';
                        n.exponent -%= 1;
                        digit_index += 1;
                    }

                    i += 1;
                } else if (c == 'e' or c == 'E') {
                    i += 1;
                    state = State.ExponentSign;
                } else {
                    state = State.ExponentSign;
                }
            },

            State.ExponentSign => {
                if (c == '+') {
                    i += 1;
                } else if (c == '-') {
                    negative_exp = true;
                    i += 1;
                }

                state = State.LeadingExponentZeros;
            },

            State.LeadingExponentZeros => {
                if (c == '0') {
                    i += 1;
                } else {
                    state = State.Exponent;
                }
            },

            State.Exponent => {
                if (isDigit(c)) {
                    if (exponent < std.math.maxInt(i32)) {
                        exponent *= 10;
                        exponent += @intCast(i32, c - '0');
                    }

                    i += 1;
                } else {
                    return error.InvalidCharacter;
                }
            },
        }
    }

    if (negative_exp) exponent = -exponent;
    n.exponent += exponent;

    if (n.mantissa == 0) {
        return if (n.negative) ParseResult.MinusZero else ParseResult.PlusZero;
    } else if (n.exponent > 309) {
        return if (n.negative) ParseResult.MinusInf else ParseResult.PlusInf;
    } else if (n.exponent < -328) {
        return if (n.negative) ParseResult.MinusZero else ParseResult.PlusZero;
    }

    return ParseResult.Ok;
}

inline fn isLower(c: u8) bool {
    return c -% 'a' < 26;
}

inline fn toUpper(c: u8) u8 {
    return if (isLower(c)) (c & 0x5f) else c;
}

fn caseInEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;

    for (a) |_, i| {
        if (toUpper(a[i]) != toUpper(b[i])) {
            return false;
        }
    }

    return true;
}

pub fn parseFloat(comptime T: type, s: []const u8) !T {
    if (s.len == 0) {
        return error.InvalidCharacter;
    }

    if (caseInEql(s, "nan")) {
        return std.math.nan(T);
    } else if (caseInEql(s, "inf") or caseInEql(s, "+inf")) {
        return std.math.inf(T);
    } else if (caseInEql(s, "-inf")) {
        return -std.math.inf(T);
    }

    var r = FloatRepr{
        .negative = false,
        .exponent = 0,
        .mantissa = 0,
    };

    return switch (try parseRepr(s, &r)) {
        ParseResult.Ok => convertRepr(T, r),
        ParseResult.PlusZero => 0.0,
        ParseResult.MinusZero => -@as(T, 0.0),
        ParseResult.PlusInf => std.math.inf(T),
        ParseResult.MinusInf => -std.math.inf(T),
    };
}

test "fmt.parseFloat" {
    if (std.Target.current.os.tag == .windows) {
        // TODO https://github.com/ziglang/zig/issues/508
        return error.SkipZigTest;
    }
    const testing = std.testing;
    const expect = testing.expect;
    const expectEqual = testing.expectEqual;
    const approxEq = std.math.approxEq;
    const epsilon = 1e-7;

    inline for ([_]type{ f16, f32, f64, f128 }) |T| {
        const Z = std.meta.IntType(false, T.bit_count);

        testing.expectError(error.InvalidCharacter, parseFloat(T, ""));
        testing.expectError(error.InvalidCharacter, parseFloat(T, "   1"));
        testing.expectError(error.InvalidCharacter, parseFloat(T, "1abc"));

        expectEqual(try parseFloat(T, "0"), 0.0);
        expectEqual((try parseFloat(T, "0")), 0.0);
        expectEqual((try parseFloat(T, "+0")), 0.0);
        expectEqual((try parseFloat(T, "-0")), 0.0);

        expectEqual((try parseFloat(T, "0e0")), 0);
        expectEqual((try parseFloat(T, "2e3")), 2000.0);
        expectEqual((try parseFloat(T, "1e0")), 1.0);
        expectEqual((try parseFloat(T, "-2e3")), -2000.0);
        expectEqual((try parseFloat(T, "-1e0")), -1.0);
        expectEqual((try parseFloat(T, "1.234e3")), 1234);

        expect(approxEq(T, try parseFloat(T, "3.141"), 3.141, epsilon));
        expect(approxEq(T, try parseFloat(T, "-3.141"), -3.141, epsilon));

        expectEqual((try parseFloat(T, "1e-700")), 0);
        expectEqual((try parseFloat(T, "1e+700")), std.math.inf(T));

        expectEqual(@bitCast(Z, try parseFloat(T, "nAn")), @bitCast(Z, std.math.nan(T)));
        expectEqual((try parseFloat(T, "inF")), std.math.inf(T));
        expectEqual((try parseFloat(T, "-INF")), -std.math.inf(T));

        if (T != f16) {
            expect(approxEq(T, try parseFloat(T, "1e-2"), 0.01, epsilon));
            expect(approxEq(T, try parseFloat(T, "1234e-2"), 12.34, epsilon));

            expect(approxEq(T, try parseFloat(T, "123142.1"), 123142.1, epsilon));
            expect(approxEq(T, try parseFloat(T, "-123142.1124"), @as(T, -123142.1124), epsilon));
            expect(approxEq(T, try parseFloat(T, "0.7062146892655368"), @as(T, 0.7062146892655368), epsilon));
        }
    }
}

const mem = @import("../mem.zig");
const math = @import("../math.zig");
const endian = @import("../endian.zig");
const debug = @import("../debug.zig");
const builtin = @import("builtin");

const RoundParam = struct {
    a: usize,
    b: usize,
    c: usize,
    d: usize,
    e: usize,
    i: u32,
};

fn Rp(a: usize, b: usize, c: usize, d: usize, e: usize, i: u32) RoundParam {
    return RoundParam{
        .a = a,
        .b = b,
        .c = c,
        .d = d,
        .e = e,
        .i = i,
    };
}

pub const Sha1 = struct {
    const Self = @This();
    pub const block_length = 64;
    pub const digest_length = 20;

    s: [5]u32,
    // Streaming Cache
    buf: [64]u8,
    buf_len: u8,
    total_len: u64,

    pub fn init() Self {
        var d: Self = undefined;
        d.reset();
        return d;
    }

    pub fn reset(d: *Self) void {
        d.s[0] = 0x67452301;
        d.s[1] = 0xEFCDAB89;
        d.s[2] = 0x98BADCFE;
        d.s[3] = 0x10325476;
        d.s[4] = 0xC3D2E1F0;
        d.buf_len = 0;
        d.total_len = 0;
    }

    pub fn hash(b: []const u8, out: []u8) void {
        var d = Sha1.init();
        d.update(b);
        d.final(out);
    }

    pub fn update(d: *Self, b: []const u8) void {
        var off: usize = 0;

        // Partial buffer exists from previous update. Copy into buffer then hash.
        if (d.buf_len != 0 and d.buf_len + b.len >= 64) {
            off += 64 - d.buf_len;
            mem.copy(u8, d.buf[d.buf_len..], b[0..off]);

            d.round(d.buf[0..]);
            d.buf_len = 0;
        }

        // Full middle blocks.
        while (off + 64 <= b.len) : (off += 64) {
            d.round(b[off .. off + 64]);
        }

        // Copy any remainder for next pass.
        mem.copy(u8, d.buf[d.buf_len..], b[off..]);
        d.buf_len += @intCast(u8, b[off..].len);

        d.total_len += b.len;
    }

    pub fn final(d: *Self, out: []u8) void {
        debug.assert(out.len >= 20);

        // The buffer here will never be completely full.
        mem.set(u8, d.buf[d.buf_len..], 0);

        // Append padding bits.
        d.buf[d.buf_len] = 0x80;
        d.buf_len += 1;

        // > 448 mod 512 so need to add an extra round to wrap around.
        if (64 - d.buf_len < 8) {
            d.round(d.buf[0..]);
            mem.set(u8, d.buf[0..], 0);
        }

        // Append message length.
        var i: usize = 1;
        var len = d.total_len >> 5;
        d.buf[63] = @intCast(u8, d.total_len & 0x1f) << 3;
        while (i < 8) : (i += 1) {
            d.buf[63 - i] = @intCast(u8, len & 0xff);
            len >>= 8;
        }

        d.round(d.buf[0..]);

        for (d.s) |s, j| {
            // TODO https://github.com/ziglang/zig/issues/863
            mem.writeIntSliceBig(u32, out[4 * j .. 4 * j + 4], s);
        }
    }

    fn round(d: *Self, b: []const u8) void {
        debug.assert(b.len == 64);

        var s: [16]u32 = undefined;

        var v: [5]u32 = [_]u32{
            d.s[0],
            d.s[1],
            d.s[2],
            d.s[3],
            d.s[4],
        };

        const round0a = comptime [_]RoundParam{
            Rp(0, 1, 2, 3, 4, 0),
            Rp(4, 0, 1, 2, 3, 1),
            Rp(3, 4, 0, 1, 2, 2),
            Rp(2, 3, 4, 0, 1, 3),
            Rp(1, 2, 3, 4, 0, 4),
            Rp(0, 1, 2, 3, 4, 5),
            Rp(4, 0, 1, 2, 3, 6),
            Rp(3, 4, 0, 1, 2, 7),
            Rp(2, 3, 4, 0, 1, 8),
            Rp(1, 2, 3, 4, 0, 9),
            Rp(0, 1, 2, 3, 4, 10),
            Rp(4, 0, 1, 2, 3, 11),
            Rp(3, 4, 0, 1, 2, 12),
            Rp(2, 3, 4, 0, 1, 13),
            Rp(1, 2, 3, 4, 0, 14),
            Rp(0, 1, 2, 3, 4, 15),
        };
        inline for (round0a) |r| {
            s[r.i] = (@as(u32, b[r.i * 4 + 0]) << 24) | (@as(u32, b[r.i * 4 + 1]) << 16) | (@as(u32, b[r.i * 4 + 2]) << 8) | (@as(u32, b[r.i * 4 + 3]) << 0);

            v[r.e] = v[r.e] +% math.rotl(u32, v[r.a], @as(u32, 5)) +% 0x5A827999 +% s[r.i & 0xf] +% ((v[r.b] & v[r.c]) | (~v[r.b] & v[r.d]));
            v[r.b] = math.rotl(u32, v[r.b], @as(u32, 30));
        }

        const round0b = comptime [_]RoundParam{
            Rp(4, 0, 1, 2, 3, 16),
            Rp(3, 4, 0, 1, 2, 17),
            Rp(2, 3, 4, 0, 1, 18),
            Rp(1, 2, 3, 4, 0, 19),
        };
        inline for (round0b) |r| {
            const t = s[(r.i - 3) & 0xf] ^ s[(r.i - 8) & 0xf] ^ s[(r.i - 14) & 0xf] ^ s[(r.i - 16) & 0xf];
            s[r.i & 0xf] = math.rotl(u32, t, @as(u32, 1));

            v[r.e] = v[r.e] +% math.rotl(u32, v[r.a], @as(u32, 5)) +% 0x5A827999 +% s[r.i & 0xf] +% ((v[r.b] & v[r.c]) | (~v[r.b] & v[r.d]));
            v[r.b] = math.rotl(u32, v[r.b], @as(u32, 30));
        }

        const round1 = comptime [_]RoundParam{
            Rp(0, 1, 2, 3, 4, 20),
            Rp(4, 0, 1, 2, 3, 21),
            Rp(3, 4, 0, 1, 2, 22),
            Rp(2, 3, 4, 0, 1, 23),
            Rp(1, 2, 3, 4, 0, 24),
            Rp(0, 1, 2, 3, 4, 25),
            Rp(4, 0, 1, 2, 3, 26),
            Rp(3, 4, 0, 1, 2, 27),
            Rp(2, 3, 4, 0, 1, 28),
            Rp(1, 2, 3, 4, 0, 29),
            Rp(0, 1, 2, 3, 4, 30),
            Rp(4, 0, 1, 2, 3, 31),
            Rp(3, 4, 0, 1, 2, 32),
            Rp(2, 3, 4, 0, 1, 33),
            Rp(1, 2, 3, 4, 0, 34),
            Rp(0, 1, 2, 3, 4, 35),
            Rp(4, 0, 1, 2, 3, 36),
            Rp(3, 4, 0, 1, 2, 37),
            Rp(2, 3, 4, 0, 1, 38),
            Rp(1, 2, 3, 4, 0, 39),
        };
        inline for (round1) |r| {
            const t = s[(r.i - 3) & 0xf] ^ s[(r.i - 8) & 0xf] ^ s[(r.i - 14) & 0xf] ^ s[(r.i - 16) & 0xf];
            s[r.i & 0xf] = math.rotl(u32, t, @as(u32, 1));

            v[r.e] = v[r.e] +% math.rotl(u32, v[r.a], @as(u32, 5)) +% 0x6ED9EBA1 +% s[r.i & 0xf] +% (v[r.b] ^ v[r.c] ^ v[r.d]);
            v[r.b] = math.rotl(u32, v[r.b], @as(u32, 30));
        }

        const round2 = comptime [_]RoundParam{
            Rp(0, 1, 2, 3, 4, 40),
            Rp(4, 0, 1, 2, 3, 41),
            Rp(3, 4, 0, 1, 2, 42),
            Rp(2, 3, 4, 0, 1, 43),
            Rp(1, 2, 3, 4, 0, 44),
            Rp(0, 1, 2, 3, 4, 45),
            Rp(4, 0, 1, 2, 3, 46),
            Rp(3, 4, 0, 1, 2, 47),
            Rp(2, 3, 4, 0, 1, 48),
            Rp(1, 2, 3, 4, 0, 49),
            Rp(0, 1, 2, 3, 4, 50),
            Rp(4, 0, 1, 2, 3, 51),
            Rp(3, 4, 0, 1, 2, 52),
            Rp(2, 3, 4, 0, 1, 53),
            Rp(1, 2, 3, 4, 0, 54),
            Rp(0, 1, 2, 3, 4, 55),
            Rp(4, 0, 1, 2, 3, 56),
            Rp(3, 4, 0, 1, 2, 57),
            Rp(2, 3, 4, 0, 1, 58),
            Rp(1, 2, 3, 4, 0, 59),
        };
        inline for (round2) |r| {
            const t = s[(r.i - 3) & 0xf] ^ s[(r.i - 8) & 0xf] ^ s[(r.i - 14) & 0xf] ^ s[(r.i - 16) & 0xf];
            s[r.i & 0xf] = math.rotl(u32, t, @as(u32, 1));

            v[r.e] = v[r.e] +% math.rotl(u32, v[r.a], @as(u32, 5)) +% 0x8F1BBCDC +% s[r.i & 0xf] +% ((v[r.b] & v[r.c]) ^ (v[r.b] & v[r.d]) ^ (v[r.c] & v[r.d]));
            v[r.b] = math.rotl(u32, v[r.b], @as(u32, 30));
        }

        const round3 = comptime [_]RoundParam{
            Rp(0, 1, 2, 3, 4, 60),
            Rp(4, 0, 1, 2, 3, 61),
            Rp(3, 4, 0, 1, 2, 62),
            Rp(2, 3, 4, 0, 1, 63),
            Rp(1, 2, 3, 4, 0, 64),
            Rp(0, 1, 2, 3, 4, 65),
            Rp(4, 0, 1, 2, 3, 66),
            Rp(3, 4, 0, 1, 2, 67),
            Rp(2, 3, 4, 0, 1, 68),
            Rp(1, 2, 3, 4, 0, 69),
            Rp(0, 1, 2, 3, 4, 70),
            Rp(4, 0, 1, 2, 3, 71),
            Rp(3, 4, 0, 1, 2, 72),
            Rp(2, 3, 4, 0, 1, 73),
            Rp(1, 2, 3, 4, 0, 74),
            Rp(0, 1, 2, 3, 4, 75),
            Rp(4, 0, 1, 2, 3, 76),
            Rp(3, 4, 0, 1, 2, 77),
            Rp(2, 3, 4, 0, 1, 78),
            Rp(1, 2, 3, 4, 0, 79),
        };
        inline for (round3) |r| {
            const t = s[(r.i - 3) & 0xf] ^ s[(r.i - 8) & 0xf] ^ s[(r.i - 14) & 0xf] ^ s[(r.i - 16) & 0xf];
            s[r.i & 0xf] = math.rotl(u32, t, @as(u32, 1));

            v[r.e] = v[r.e] +% math.rotl(u32, v[r.a], @as(u32, 5)) +% 0xCA62C1D6 +% s[r.i & 0xf] +% (v[r.b] ^ v[r.c] ^ v[r.d]);
            v[r.b] = math.rotl(u32, v[r.b], @as(u32, 30));
        }

        d.s[0] +%= v[0];
        d.s[1] +%= v[1];
        d.s[2] +%= v[2];
        d.s[3] +%= v[3];
        d.s[4] +%= v[4];
    }
};

const htest = @import("test.zig");

test "sha1 single" {
    htest.assertEqualHash(Sha1, "da39a3ee5e6b4b0d3255bfef95601890afd80709", "");
    htest.assertEqualHash(Sha1, "a9993e364706816aba3e25717850c26c9cd0d89d", "abc");
    htest.assertEqualHash(Sha1, "a49b2446a02c645bf419f995b67091253a04a259", "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu");
}

test "sha1 streaming" {
    var h = Sha1.init();
    var out: [20]u8 = undefined;

    h.final(out[0..]);
    htest.assertEqual("da39a3ee5e6b4b0d3255bfef95601890afd80709", out[0..]);

    h.reset();
    h.update("abc");
    h.final(out[0..]);
    htest.assertEqual("a9993e364706816aba3e25717850c26c9cd0d89d", out[0..]);

    h.reset();
    h.update("a");
    h.update("b");
    h.update("c");
    h.final(out[0..]);
    htest.assertEqual("a9993e364706816aba3e25717850c26c9cd0d89d", out[0..]);
}

test "sha1 aligned final" {
    var block = [_]u8{0} ** Sha1.block_length;
    var out: [Sha1.digest_length]u8 = undefined;

    var h = Sha1.init();
    h.update(&block);
    h.final(out[0..]);
}

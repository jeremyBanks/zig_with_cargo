pub const Md5 = @import("crypto/md5.zig").Md5;
pub const Sha1 = @import("crypto/sha1.zig").Sha1;

const sha2 = @import("crypto/sha2.zig");
pub const Sha224 = sha2.Sha224;
pub const Sha256 = sha2.Sha256;
pub const Sha384 = sha2.Sha384;
pub const Sha512 = sha2.Sha512;

const sha3 = @import("crypto/sha3.zig");
pub const Sha3_224 = sha3.Sha3_224;
pub const Sha3_256 = sha3.Sha3_256;
pub const Sha3_384 = sha3.Sha3_384;
pub const Sha3_512 = sha3.Sha3_512;

pub const gimli = @import("crypto/gimli.zig");

const blake2 = @import("crypto/blake2.zig");
pub const Blake2s224 = blake2.Blake2s224;
pub const Blake2s256 = blake2.Blake2s256;
pub const Blake2b384 = blake2.Blake2b384;
pub const Blake2b512 = blake2.Blake2b512;

const hmac = @import("crypto/hmac.zig");
pub const HmacMd5 = hmac.HmacMd5;
pub const HmacSha1 = hmac.HmacSha1;
pub const HmacSha256 = hmac.HmacSha256;
pub const HmacBlake2s256 = hmac.HmacBlake2s256;

const import_chaCha20 = @import("crypto/chacha20.zig");
pub const chaCha20IETF = import_chaCha20.chaCha20IETF;
pub const chaCha20With64BitNonce = import_chaCha20.chaCha20With64BitNonce;

pub const Poly1305 = @import("crypto/poly1305.zig").Poly1305;
pub const X25519 = @import("crypto/x25519.zig").X25519;

const std = @import("std.zig");
pub const randomBytes = std.os.getrandom;

test "crypto" {
    _ = @import("crypto/blake2.zig");
    _ = @import("crypto/chacha20.zig");
    _ = @import("crypto/gimli.zig");
    _ = @import("crypto/hmac.zig");
    _ = @import("crypto/md5.zig");
    _ = @import("crypto/poly1305.zig");
    _ = @import("crypto/sha1.zig");
    _ = @import("crypto/sha2.zig");
    _ = @import("crypto/sha3.zig");
    _ = @import("crypto/x25519.zig");
}

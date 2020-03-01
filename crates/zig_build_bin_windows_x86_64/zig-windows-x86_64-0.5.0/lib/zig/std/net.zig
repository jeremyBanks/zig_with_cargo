const std = @import("std.zig");
const builtin = @import("builtin");
const assert = std.debug.assert;
const net = @This();
const mem = std.mem;
const os = std.os;

pub const TmpWinAddr = struct {
    family: u8,
    data: [14]u8,
};

pub const OsAddress = switch (builtin.os) {
    builtin.Os.windows => TmpWinAddr,
    else => os.sockaddr,
};

pub const Address = struct {
    os_addr: OsAddress,

    pub fn initIp4(ip4: u32, _port: u16) Address {
        return Address{
            .os_addr = os.sockaddr{
                .in = os.sockaddr_in{
                    .family = os.AF_INET,
                    .port = mem.nativeToBig(u16, _port),
                    .addr = ip4,
                    .zero = [_]u8{0} ** 8,
                },
            },
        };
    }

    pub fn initIp6(ip6: *const Ip6Addr, _port: u16) Address {
        return Address{
            .os_addr = os.sockaddr{
                .in6 = os.sockaddr_in6{
                    .family = os.AF_INET6,
                    .port = mem.nativeToBig(u16, _port),
                    .flowinfo = 0,
                    .addr = ip6.addr,
                    .scope_id = ip6.scope_id,
                },
            },
        };
    }

    pub fn port(self: Address) u16 {
        return mem.bigToNative(u16, self.os_addr.in.port);
    }

    pub fn initPosix(addr: os.sockaddr) Address {
        return Address{ .os_addr = addr };
    }

    pub fn format(self: *const Address, out_stream: var) !void {
        switch (self.os_addr.in.family) {
            os.AF_INET => {
                const native_endian_port = mem.bigToNative(u16, self.os_addr.in.port);
                const bytes = ([]const u8)((*self.os_addr.in.addr)[0..1]);
                try out_stream.print("{}.{}.{}.{}:{}", bytes[0], bytes[1], bytes[2], bytes[3], native_endian_port);
            },
            os.AF_INET6 => {
                const native_endian_port = mem.bigToNative(u16, self.os_addr.in6.port);
                try out_stream.print("[TODO render ip6 address]:{}", native_endian_port);
            },
            else => try out_stream.write("(unrecognized address family)"),
        }
    }
};

pub fn parseIp4(buf: []const u8) !u32 {
    var result: u32 = undefined;
    const out_ptr = @sliceToBytes((*[1]u32)(&result)[0..]);

    var x: u8 = 0;
    var index: u8 = 0;
    var saw_any_digits = false;
    for (buf) |c| {
        if (c == '.') {
            if (!saw_any_digits) {
                return error.InvalidCharacter;
            }
            if (index == 3) {
                return error.InvalidEnd;
            }
            out_ptr[index] = x;
            index += 1;
            x = 0;
            saw_any_digits = false;
        } else if (c >= '0' and c <= '9') {
            saw_any_digits = true;
            const digit = c - '0';
            if (@mulWithOverflow(u8, x, 10, &x)) {
                return error.Overflow;
            }
            if (@addWithOverflow(u8, x, digit, &x)) {
                return error.Overflow;
            }
        } else {
            return error.InvalidCharacter;
        }
    }
    if (index == 3 and saw_any_digits) {
        out_ptr[index] = x;
        return result;
    }

    return error.Incomplete;
}

pub const Ip6Addr = struct {
    scope_id: u32,
    addr: [16]u8,
};

pub fn parseIp6(buf: []const u8) !Ip6Addr {
    var result: Ip6Addr = undefined;
    result.scope_id = 0;
    const ip_slice = result.addr[0..];

    var x: u16 = 0;
    var saw_any_digits = false;
    var index: u8 = 0;
    var scope_id = false;
    for (buf) |c| {
        if (scope_id) {
            if (c >= '0' and c <= '9') {
                const digit = c - '0';
                if (@mulWithOverflow(u32, result.scope_id, 10, &result.scope_id)) {
                    return error.Overflow;
                }
                if (@addWithOverflow(u32, result.scope_id, digit, &result.scope_id)) {
                    return error.Overflow;
                }
            } else {
                return error.InvalidCharacter;
            }
        } else if (c == ':') {
            if (!saw_any_digits) {
                return error.InvalidCharacter;
            }
            if (index == 14) {
                return error.InvalidEnd;
            }
            ip_slice[index] = @truncate(u8, x >> 8);
            index += 1;
            ip_slice[index] = @truncate(u8, x);
            index += 1;

            x = 0;
            saw_any_digits = false;
        } else if (c == '%') {
            if (!saw_any_digits) {
                return error.InvalidCharacter;
            }
            if (index == 14) {
                ip_slice[index] = @truncate(u8, x >> 8);
                index += 1;
                ip_slice[index] = @truncate(u8, x);
                index += 1;
            }
            scope_id = true;
            saw_any_digits = false;
        } else {
            const digit = try std.fmt.charToDigit(c, 16);
            if (@mulWithOverflow(u16, x, 16, &x)) {
                return error.Overflow;
            }
            if (@addWithOverflow(u16, x, digit, &x)) {
                return error.Overflow;
            }
            saw_any_digits = true;
        }
    }

    if (!saw_any_digits) {
        return error.Incomplete;
    }

    if (scope_id) {
        return result;
    }

    if (index == 14) {
        ip_slice[14] = @truncate(u8, x >> 8);
        ip_slice[15] = @truncate(u8, x);
        return result;
    }

    return error.Incomplete;
}

test "std.net.parseIp4" {
    assert((try parseIp4("127.0.0.1")) == mem.bigToNative(u32, 0x7f000001));

    testParseIp4Fail("256.0.0.1", error.Overflow);
    testParseIp4Fail("x.0.0.1", error.InvalidCharacter);
    testParseIp4Fail("127.0.0.1.1", error.InvalidEnd);
    testParseIp4Fail("127.0.0.", error.Incomplete);
    testParseIp4Fail("100..0.1", error.InvalidCharacter);
}

fn testParseIp4Fail(buf: []const u8, expected_err: anyerror) void {
    if (parseIp4(buf)) |_| {
        @panic("expected error");
    } else |e| {
        assert(e == expected_err);
    }
}

test "std.net.parseIp6" {
    const addr = try parseIp6("FF01:0:0:0:0:0:0:FB");
    assert(addr.addr[0] == 0xff);
    assert(addr.addr[1] == 0x01);
    assert(addr.addr[2] == 0x00);
}

pub fn connectUnixSocket(path: []const u8) !std.fs.File {
    const opt_non_block = if (std.event.Loop.instance != null) os.SOCK_NONBLOCK else 0;
    const sockfd = try os.socket(
        os.AF_UNIX,
        os.SOCK_STREAM | os.SOCK_CLOEXEC | opt_non_block,
        0,
    );
    errdefer os.close(sockfd);

    var sock_addr = os.sockaddr{
        .un = os.sockaddr_un{
            .family = os.AF_UNIX,
            .path = undefined,
        },
    };

    if (path.len > @typeOf(sock_addr.un.path).len) return error.NameTooLong;
    mem.copy(u8, sock_addr.un.path[0..], path);
    const size = @intCast(u32, @sizeOf(os.sa_family_t) + path.len);
    if (std.event.Loop.instance) |loop| {
        try os.connect_async(sockfd, &sock_addr, size);
        try loop.linuxWaitFd(sockfd, os.EPOLLIN | os.EPOLLOUT | os.EPOLLET);
        try os.getsockoptError(sockfd);
    } else {
        try os.connect(sockfd, &sock_addr, size);
    }

    return std.fs.File.openHandle(sockfd);
}

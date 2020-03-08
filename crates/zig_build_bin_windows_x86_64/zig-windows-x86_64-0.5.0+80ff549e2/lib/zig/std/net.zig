const std = @import("std.zig");
const builtin = @import("builtin");
const assert = std.debug.assert;
const net = @This();
const mem = std.mem;
const os = std.os;
const fs = std.fs;

test "" {
    _ = @import("net/test.zig");
}

const has_unix_sockets = @hasDecl(os, "sockaddr_un");

pub const Address = extern union {
    any: os.sockaddr,
    in: os.sockaddr_in,
    in6: os.sockaddr_in6,
    un: if (has_unix_sockets) os.sockaddr_un else void,

    // TODO this crashed the compiler. https://github.com/ziglang/zig/issues/3512
    //pub const localhost = initIp4(parseIp4("127.0.0.1") catch unreachable, 0);

    pub fn parseIp(name: []const u8, port: u16) !Address {
        if (parseIp4(name, port)) |ip4| return ip4 else |err| switch (err) {
            error.Overflow,
            error.InvalidEnd,
            error.InvalidCharacter,
            error.Incomplete,
            => {},
        }

        if (parseIp6(name, port)) |ip6| return ip6 else |err| switch (err) {
            error.Overflow,
            error.InvalidEnd,
            error.InvalidCharacter,
            error.Incomplete,
            error.InvalidIpv4Mapping,
            => {},
        }

        return error.InvalidIPAddressFormat;
    }

    pub fn parseExpectingFamily(name: []const u8, family: os.sa_family_t, port: u16) !Address {
        switch (family) {
            os.AF_INET => return parseIp4(name, port),
            os.AF_INET6 => return parseIp6(name, port),
            os.AF_UNSPEC => return parseIp(name, port),
            else => unreachable,
        }
    }

    pub fn parseIp6(buf: []const u8, port: u16) !Address {
        var result = Address{
            .in6 = os.sockaddr_in6{
                .scope_id = 0,
                .port = mem.nativeToBig(u16, port),
                .flowinfo = 0,
                .addr = undefined,
            },
        };
        var ip_slice = result.in6.addr[0..];

        var tail: [16]u8 = undefined;

        var x: u16 = 0;
        var saw_any_digits = false;
        var index: u8 = 0;
        var scope_id = false;
        var abbrv = false;
        for (buf) |c, i| {
            if (scope_id) {
                if (c >= '0' and c <= '9') {
                    const digit = c - '0';
                    if (@mulWithOverflow(u32, result.in6.scope_id, 10, &result.in6.scope_id)) {
                        return error.Overflow;
                    }
                    if (@addWithOverflow(u32, result.in6.scope_id, digit, &result.in6.scope_id)) {
                        return error.Overflow;
                    }
                } else {
                    return error.InvalidCharacter;
                }
            } else if (c == ':') {
                if (!saw_any_digits) {
                    if (abbrv) return error.InvalidCharacter; // ':::'
                    if (i != 0) abbrv = true;
                    mem.set(u8, ip_slice[index..], 0);
                    ip_slice = tail[0..];
                    index = 0;
                    continue;
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
                scope_id = true;
                saw_any_digits = false;
            } else if (c == '.') {
                if (!abbrv or ip_slice[0] != 0xff or ip_slice[1] != 0xff) {
                    // must start with '::ffff:'
                    return error.InvalidIpv4Mapping;
                }
                const start_index = mem.lastIndexOfScalar(u8, buf[0..i], ':').? + 1;
                const addr = (parseIp4(buf[start_index..], 0) catch {
                    return error.InvalidIpv4Mapping;
                }).in.addr;
                ip_slice = result.in6.addr[0..];
                ip_slice[10] = 0xff;
                ip_slice[11] = 0xff;

                const ptr = mem.sliceAsBytes(@as(*const [1]u32, &addr)[0..]);

                ip_slice[12] = ptr[0];
                ip_slice[13] = ptr[1];
                ip_slice[14] = ptr[2];
                ip_slice[15] = ptr[3];
                return result;
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

        if (!saw_any_digits and !abbrv) {
            return error.Incomplete;
        }

        if (index == 14) {
            ip_slice[14] = @truncate(u8, x >> 8);
            ip_slice[15] = @truncate(u8, x);
            return result;
        } else {
            ip_slice[index] = @truncate(u8, x >> 8);
            index += 1;
            ip_slice[index] = @truncate(u8, x);
            index += 1;
            mem.copy(u8, result.in6.addr[16 - index ..], ip_slice[0..index]);
            return result;
        }
    }

    pub fn parseIp4(buf: []const u8, port: u16) !Address {
        var result = Address{
            .in = os.sockaddr_in{
                .port = mem.nativeToBig(u16, port),
                .addr = undefined,
            },
        };
        const out_ptr = mem.sliceAsBytes(@as(*[1]u32, &result.in.addr)[0..]);

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
                x = try std.math.mul(u8, x, 10);
                x = try std.math.add(u8, x, c - '0');
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

    pub fn initIp4(addr: [4]u8, port: u16) Address {
        return Address{
            .in = os.sockaddr_in{
                .port = mem.nativeToBig(u16, port),
                .addr = @ptrCast(*align(1) const u32, &addr).*,
            },
        };
    }

    pub fn initIp6(addr: [16]u8, port: u16, flowinfo: u32, scope_id: u32) Address {
        return Address{
            .in6 = os.sockaddr_in6{
                .addr = addr,
                .port = mem.nativeToBig(u16, port),
                .flowinfo = flowinfo,
                .scope_id = scope_id,
            },
        };
    }

    pub fn initUnix(path: []const u8) !Address {
        var sock_addr = os.sockaddr_un{
            .family = os.AF_UNIX,
            .path = undefined,
        };

        // this enables us to have the proper length of the socket in getOsSockLen
        mem.set(u8, &sock_addr.path, 0);

        if (path.len > sock_addr.path.len) return error.NameTooLong;
        mem.copy(u8, &sock_addr.path, path);

        return Address{ .un = sock_addr };
    }

    /// Returns the port in native endian.
    /// Asserts that the address is ip4 or ip6.
    pub fn getPort(self: Address) u16 {
        const big_endian_port = switch (self.any.family) {
            os.AF_INET => self.in.port,
            os.AF_INET6 => self.in6.port,
            else => unreachable,
        };
        return mem.bigToNative(u16, big_endian_port);
    }

    /// `port` is native-endian.
    /// Asserts that the address is ip4 or ip6.
    pub fn setPort(self: *Address, port: u16) void {
        const ptr = switch (self.any.family) {
            os.AF_INET => &self.in.port,
            os.AF_INET6 => &self.in6.port,
            else => unreachable,
        };
        ptr.* = mem.nativeToBig(u16, port);
    }

    /// Asserts that `addr` is an IP address.
    /// This function will read past the end of the pointer, with a size depending
    /// on the address family.
    pub fn initPosix(addr: *align(4) const os.sockaddr) Address {
        switch (addr.family) {
            os.AF_INET => return Address{ .in = @ptrCast(*const os.sockaddr_in, addr).* },
            os.AF_INET6 => return Address{ .in6 = @ptrCast(*const os.sockaddr_in6, addr).* },
            else => unreachable,
        }
    }

    pub fn format(
        self: Address,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        context: var,
        comptime Errors: type,
        comptime output: fn (@TypeOf(context), []const u8) Errors!void,
    ) !void {
        switch (self.any.family) {
            os.AF_INET => {
                const port = mem.bigToNative(u16, self.in.port);
                const bytes = @ptrCast(*const [4]u8, &self.in.addr);
                try std.fmt.format(context, Errors, output, "{}.{}.{}.{}:{}", .{
                    bytes[0],
                    bytes[1],
                    bytes[2],
                    bytes[3],
                    port,
                });
            },
            os.AF_INET6 => {
                const port = mem.bigToNative(u16, self.in6.port);
                if (mem.eql(u8, self.in6.addr[0..12], &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff })) {
                    try std.fmt.format(context, Errors, output, "[::ffff:{}.{}.{}.{}]:{}", .{
                        self.in6.addr[12],
                        self.in6.addr[13],
                        self.in6.addr[14],
                        self.in6.addr[15],
                        port,
                    });
                    return;
                }
                const big_endian_parts = @ptrCast(*align(1) const [8]u16, &self.in6.addr);
                const native_endian_parts = switch (builtin.endian) {
                    .Big => big_endian_parts.*,
                    .Little => blk: {
                        var buf: [8]u16 = undefined;
                        for (big_endian_parts) |part, i| {
                            buf[i] = mem.bigToNative(u16, part);
                        }
                        break :blk buf;
                    },
                };
                try output(context, "[");
                var i: usize = 0;
                var abbrv = false;
                while (i < native_endian_parts.len) : (i += 1) {
                    if (native_endian_parts[i] == 0) {
                        if (!abbrv) {
                            try output(context, if (i == 0) "::" else ":");
                            abbrv = true;
                        }
                        continue;
                    }
                    try std.fmt.format(context, Errors, output, "{x}", .{native_endian_parts[i]});
                    if (i != native_endian_parts.len - 1) {
                        try output(context, ":");
                    }
                }
                try std.fmt.format(context, Errors, output, "]:{}", .{port});
            },
            os.AF_UNIX => {
                if (!has_unix_sockets) {
                    unreachable;
                }

                try std.fmt.format(context, Errors, output, "{}", .{&self.un.path});
            },
            else => unreachable,
        }
    }

    pub fn eql(a: Address, b: Address) bool {
        const a_bytes = @ptrCast([*]const u8, &a.any)[0..a.getOsSockLen()];
        const b_bytes = @ptrCast([*]const u8, &b.any)[0..b.getOsSockLen()];
        return mem.eql(u8, a_bytes, b_bytes);
    }

    fn getOsSockLen(self: Address) os.socklen_t {
        switch (self.any.family) {
            os.AF_INET => return @sizeOf(os.sockaddr_in),
            os.AF_INET6 => return @sizeOf(os.sockaddr_in6),
            os.AF_UNIX => {
                if (!has_unix_sockets) {
                    unreachable;
                }

                const path_len = std.mem.len(@ptrCast([*:0]const u8, &self.un.path));
                return @intCast(os.socklen_t, @sizeOf(os.sockaddr_un) - self.un.path.len + path_len);
            },
            else => unreachable,
        }
    }
};

pub fn connectUnixSocket(path: []const u8) !fs.File {
    const opt_non_block = if (std.io.is_async) os.SOCK_NONBLOCK else 0;
    const sockfd = try os.socket(
        os.AF_UNIX,
        os.SOCK_STREAM | os.SOCK_CLOEXEC | opt_non_block,
        0,
    );
    errdefer os.close(sockfd);

    var addr = try std.net.Address.initUnix(path);

    try os.connect(
        sockfd,
        &addr.any,
        addr.getOsSockLen(),
    );

    return fs.File{
        .handle = sockfd,
        .io_mode = std.io.mode,
    };
}

pub const AddressList = struct {
    arena: std.heap.ArenaAllocator,
    addrs: []Address,
    canon_name: ?[]u8,

    fn deinit(self: *AddressList) void {
        // Here we copy the arena allocator into stack memory, because
        // otherwise it would destroy itself while it was still working.
        var arena = self.arena;
        arena.deinit();
        // self is destroyed
    }
};

/// All memory allocated with `allocator` will be freed before this function returns.
pub fn tcpConnectToHost(allocator: *mem.Allocator, name: []const u8, port: u16) !fs.File {
    const list = getAddressList(allocator, name, port);
    defer list.deinit();

    const addrs = list.addrs.toSliceConst();
    if (addrs.len == 0) return error.UnknownHostName;

    return tcpConnectToAddress(addrs[0], port);
}

pub fn tcpConnectToAddress(address: Address) !fs.File {
    const nonblock = if (std.io.is_async) os.SOCK_NONBLOCK else 0;
    const sock_flags = os.SOCK_STREAM | os.SOCK_CLOEXEC | nonblock;
    const sockfd = try os.socket(address.any.family, sock_flags, os.IPPROTO_TCP);
    errdefer os.close(sockfd);
    try os.connect(sockfd, &address.any, address.getOsSockLen());

    return fs.File{ .handle = sockfd, .io_mode = std.io.mode };
}

/// Call `AddressList.deinit` on the result.
pub fn getAddressList(allocator: *mem.Allocator, name: []const u8, port: u16) !*AddressList {
    const result = blk: {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const result = try arena.allocator.create(AddressList);
        result.* = AddressList{
            .arena = arena,
            .addrs = undefined,
            .canon_name = null,
        };
        break :blk result;
    };
    const arena = &result.arena.allocator;
    errdefer result.arena.deinit();

    if (builtin.link_libc) {
        const c = std.c;
        const name_c = try std.cstr.addNullByte(allocator, name);
        defer allocator.free(name_c);

        const port_c = try std.fmt.allocPrint(allocator, "{}\x00", .{port});
        defer allocator.free(port_c);

        const hints = os.addrinfo{
            .flags = c.AI_NUMERICSERV,
            .family = os.AF_UNSPEC,
            .socktype = os.SOCK_STREAM,
            .protocol = os.IPPROTO_TCP,
            .canonname = null,
            .addr = null,
            .addrlen = 0,
            .next = null,
        };
        var res: *os.addrinfo = undefined;
        switch (os.system.getaddrinfo(name_c.ptr, @ptrCast([*:0]const u8, port_c.ptr), &hints, &res)) {
            @intToEnum(os.system.EAI, 0) => {},
            .ADDRFAMILY => return error.HostLacksNetworkAddresses,
            .AGAIN => return error.TemporaryNameServerFailure,
            .BADFLAGS => unreachable, // Invalid hints
            .FAIL => return error.NameServerFailure,
            .FAMILY => return error.AddressFamilyNotSupported,
            .MEMORY => return error.OutOfMemory,
            .NODATA => return error.HostLacksNetworkAddresses,
            .NONAME => return error.UnknownHostName,
            .SERVICE => return error.ServiceUnavailable,
            .SOCKTYPE => unreachable, // Invalid socket type requested in hints
            .SYSTEM => switch (os.errno(-1)) {
                else => |e| return os.unexpectedErrno(e),
            },
            else => unreachable,
        }
        defer os.system.freeaddrinfo(res);

        const addr_count = blk: {
            var count: usize = 0;
            var it: ?*os.addrinfo = res;
            while (it) |info| : (it = info.next) {
                if (info.addr != null) {
                    count += 1;
                }
            }
            break :blk count;
        };
        result.addrs = try arena.alloc(Address, addr_count);

        var it: ?*os.addrinfo = res;
        var i: usize = 0;
        while (it) |info| : (it = info.next) {
            const addr = info.addr orelse continue;
            result.addrs[i] = Address.initPosix(@alignCast(4, addr));

            if (info.canonname) |n| {
                if (result.canon_name == null) {
                    result.canon_name = try mem.dupe(arena, u8, mem.toSliceConst(u8, n));
                }
            }
            i += 1;
        }

        return result;
    }
    if (builtin.os.tag == .linux) {
        const flags = std.c.AI_NUMERICSERV;
        const family = os.AF_UNSPEC;
        var lookup_addrs = std.ArrayList(LookupAddr).init(allocator);
        defer lookup_addrs.deinit();

        var canon = std.Buffer.initNull(arena);
        defer canon.deinit();

        try linuxLookupName(&lookup_addrs, &canon, name, family, flags, port);

        result.addrs = try arena.alloc(Address, lookup_addrs.len);
        if (!canon.isNull()) {
            result.canon_name = canon.toOwnedSlice();
        }

        for (lookup_addrs.toSliceConst()) |lookup_addr, i| {
            result.addrs[i] = lookup_addr.addr;
            assert(result.addrs[i].getPort() == port);
        }

        return result;
    }
    @compileError("std.net.getAddresses unimplemented for this OS");
}

const LookupAddr = struct {
    addr: Address,
    sortkey: i32 = 0,
};

const DAS_USABLE = 0x40000000;
const DAS_MATCHINGSCOPE = 0x20000000;
const DAS_MATCHINGLABEL = 0x10000000;
const DAS_PREC_SHIFT = 20;
const DAS_SCOPE_SHIFT = 16;
const DAS_PREFIX_SHIFT = 8;
const DAS_ORDER_SHIFT = 0;

fn linuxLookupName(
    addrs: *std.ArrayList(LookupAddr),
    canon: *std.Buffer,
    opt_name: ?[]const u8,
    family: os.sa_family_t,
    flags: u32,
    port: u16,
) !void {
    if (opt_name) |name| {
        // reject empty name and check len so it fits into temp bufs
        try canon.replaceContents(name);
        if (Address.parseExpectingFamily(name, family, port)) |addr| {
            try addrs.append(LookupAddr{ .addr = addr });
        } else |name_err| if ((flags & std.c.AI_NUMERICHOST) != 0) {
            return name_err;
        } else {
            try linuxLookupNameFromHosts(addrs, canon, name, family, port);
            if (addrs.len == 0) {
                try linuxLookupNameFromDnsSearch(addrs, canon, name, family, port);
            }
        }
    } else {
        try canon.resize(0);
        try linuxLookupNameFromNull(addrs, family, flags, port);
    }
    if (addrs.len == 0) return error.UnknownHostName;

    // No further processing is needed if there are fewer than 2
    // results or if there are only IPv4 results.
    if (addrs.len == 1 or family == os.AF_INET) return;
    const all_ip4 = for (addrs.toSliceConst()) |addr| {
        if (addr.addr.any.family != os.AF_INET) break false;
    } else true;
    if (all_ip4) return;

    // The following implements a subset of RFC 3484/6724 destination
    // address selection by generating a single 31-bit sort key for
    // each address. Rules 3, 4, and 7 are omitted for having
    // excessive runtime and code size cost and dubious benefit.
    // So far the label/precedence table cannot be customized.
    // This implementation is ported from musl libc.
    // A more idiomatic "ziggy" implementation would be welcome.
    for (addrs.toSlice()) |*addr, i| {
        var key: i32 = 0;
        var sa6: os.sockaddr_in6 = undefined;
        @memset(@ptrCast([*]u8, &sa6), 0, @sizeOf(os.sockaddr_in6));
        var da6 = os.sockaddr_in6{
            .family = os.AF_INET6,
            .scope_id = addr.addr.in6.scope_id,
            .port = 65535,
            .flowinfo = 0,
            .addr = [1]u8{0} ** 16,
        };
        var sa4: os.sockaddr_in = undefined;
        @memset(@ptrCast([*]u8, &sa4), 0, @sizeOf(os.sockaddr_in));
        var da4 = os.sockaddr_in{
            .family = os.AF_INET,
            .port = 65535,
            .addr = 0,
            .zero = [1]u8{0} ** 8,
        };
        var sa: *align(4) os.sockaddr = undefined;
        var da: *align(4) os.sockaddr = undefined;
        var salen: os.socklen_t = undefined;
        var dalen: os.socklen_t = undefined;
        if (addr.addr.any.family == os.AF_INET6) {
            mem.copy(u8, &da6.addr, &addr.addr.in6.addr);
            da = @ptrCast(*os.sockaddr, &da6);
            dalen = @sizeOf(os.sockaddr_in6);
            sa = @ptrCast(*os.sockaddr, &sa6);
            salen = @sizeOf(os.sockaddr_in6);
        } else {
            mem.copy(u8, &sa6.addr, "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff");
            mem.copy(u8, &da6.addr, "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff");
            // TODO https://github.com/ziglang/zig/issues/863
            mem.writeIntNative(u32, @ptrCast(*[4]u8, da6.addr[12..].ptr), addr.addr.in.addr);
            da4.addr = addr.addr.in.addr;
            da = @ptrCast(*os.sockaddr, &da4);
            dalen = @sizeOf(os.sockaddr_in);
            sa = @ptrCast(*os.sockaddr, &sa4);
            salen = @sizeOf(os.sockaddr_in);
        }
        const dpolicy = policyOf(da6.addr);
        const dscope: i32 = scopeOf(da6.addr);
        const dlabel = dpolicy.label;
        const dprec: i32 = dpolicy.prec;
        const MAXADDRS = 3;
        var prefixlen: i32 = 0;
        const sock_flags = os.SOCK_DGRAM | os.SOCK_CLOEXEC;
        if (os.socket(addr.addr.any.family, sock_flags, os.IPPROTO_UDP)) |fd| syscalls: {
            defer os.close(fd);
            os.connect(fd, da, dalen) catch break :syscalls;
            key |= DAS_USABLE;
            os.getsockname(fd, sa, &salen) catch break :syscalls;
            if (addr.addr.any.family == os.AF_INET) {
                // TODO sa6.addr[12..16] should return *[4]u8, making this cast unnecessary.
                mem.writeIntNative(u32, @ptrCast(*[4]u8, &sa6.addr[12]), sa4.addr);
            }
            if (dscope == @as(i32, scopeOf(sa6.addr))) key |= DAS_MATCHINGSCOPE;
            if (dlabel == labelOf(sa6.addr)) key |= DAS_MATCHINGLABEL;
            prefixlen = prefixMatch(sa6.addr, da6.addr);
        } else |_| {}
        key |= dprec << DAS_PREC_SHIFT;
        key |= (15 - dscope) << DAS_SCOPE_SHIFT;
        key |= prefixlen << DAS_PREFIX_SHIFT;
        key |= (MAXADDRS - @intCast(i32, i)) << DAS_ORDER_SHIFT;
        addr.sortkey = key;
    }
    std.sort.sort(LookupAddr, addrs.toSlice(), addrCmpLessThan);
}

const Policy = struct {
    addr: [16]u8,
    len: u8,
    mask: u8,
    prec: u8,
    label: u8,
};

const defined_policies = [_]Policy{
    Policy{
        .addr = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01".*,
        .len = 15,
        .mask = 0xff,
        .prec = 50,
        .label = 0,
    },
    Policy{
        .addr = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\x00\x00\x00\x00".*,
        .len = 11,
        .mask = 0xff,
        .prec = 35,
        .label = 4,
    },
    Policy{
        .addr = "\x20\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*,
        .len = 1,
        .mask = 0xff,
        .prec = 30,
        .label = 2,
    },
    Policy{
        .addr = "\x20\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*,
        .len = 3,
        .mask = 0xff,
        .prec = 5,
        .label = 5,
    },
    Policy{
        .addr = "\xfc\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*,
        .len = 0,
        .mask = 0xfe,
        .prec = 3,
        .label = 13,
    },
    //  These are deprecated and/or returned to the address
    //  pool, so despite the RFC, treating them as special
    //  is probably wrong.
    // { "", 11, 0xff, 1, 3 },
    // { "\xfe\xc0", 1, 0xc0, 1, 11 },
    // { "\x3f\xfe", 1, 0xff, 1, 12 },
    // Last rule must match all addresses to stop loop.
    Policy{
        .addr = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*,
        .len = 0,
        .mask = 0,
        .prec = 40,
        .label = 1,
    },
};

fn policyOf(a: [16]u8) *const Policy {
    for (defined_policies) |*policy| {
        if (!mem.eql(u8, a[0..policy.len], policy.addr[0..policy.len])) continue;
        if ((a[policy.len] & policy.mask) != policy.addr[policy.len]) continue;
        return policy;
    }
    unreachable;
}

fn scopeOf(a: [16]u8) u8 {
    if (IN6_IS_ADDR_MULTICAST(a)) return a[1] & 15;
    if (IN6_IS_ADDR_LINKLOCAL(a)) return 2;
    if (IN6_IS_ADDR_LOOPBACK(a)) return 2;
    if (IN6_IS_ADDR_SITELOCAL(a)) return 5;
    return 14;
}

fn prefixMatch(s: [16]u8, d: [16]u8) u8 {
    // TODO: This FIXME inherited from porting from musl libc.
    // I don't want this to go into zig std lib 1.0.0.

    // FIXME: The common prefix length should be limited to no greater
    // than the nominal length of the prefix portion of the source
    // address. However the definition of the source prefix length is
    // not clear and thus this limiting is not yet implemented.
    var i: u8 = 0;
    while (i < 128 and ((s[i / 8] ^ d[i / 8]) & (@as(u8, 128) >> @intCast(u3, i % 8))) == 0) : (i += 1) {}
    return i;
}

fn labelOf(a: [16]u8) u8 {
    return policyOf(a).label;
}

fn IN6_IS_ADDR_MULTICAST(a: [16]u8) bool {
    return a[0] == 0xff;
}

fn IN6_IS_ADDR_LINKLOCAL(a: [16]u8) bool {
    return a[0] == 0xfe and (a[1] & 0xc0) == 0x80;
}

fn IN6_IS_ADDR_LOOPBACK(a: [16]u8) bool {
    return a[0] == 0 and a[1] == 0 and
        a[2] == 0 and
        a[12] == 0 and a[13] == 0 and
        a[14] == 0 and a[15] == 1;
}

fn IN6_IS_ADDR_SITELOCAL(a: [16]u8) bool {
    return a[0] == 0xfe and (a[1] & 0xc0) == 0xc0;
}

// Parameters `b` and `a` swapped to make this descending.
fn addrCmpLessThan(b: LookupAddr, a: LookupAddr) bool {
    return a.sortkey < b.sortkey;
}

fn linuxLookupNameFromNull(
    addrs: *std.ArrayList(LookupAddr),
    family: os.sa_family_t,
    flags: u32,
    port: u16,
) !void {
    if ((flags & std.c.AI_PASSIVE) != 0) {
        if (family != os.AF_INET6) {
            (try addrs.addOne()).* = LookupAddr{
                .addr = Address.initIp4([1]u8{0} ** 4, port),
            };
        }
        if (family != os.AF_INET) {
            (try addrs.addOne()).* = LookupAddr{
                .addr = Address.initIp6([1]u8{0} ** 16, port, 0, 0),
            };
        }
    } else {
        if (family != os.AF_INET6) {
            (try addrs.addOne()).* = LookupAddr{
                .addr = Address.initIp4([4]u8{ 127, 0, 0, 1 }, port),
            };
        }
        if (family != os.AF_INET) {
            (try addrs.addOne()).* = LookupAddr{
                .addr = Address.initIp6(([1]u8{0} ** 15) ++ [1]u8{1}, port, 0, 0),
            };
        }
    }
}

fn linuxLookupNameFromHosts(
    addrs: *std.ArrayList(LookupAddr),
    canon: *std.Buffer,
    name: []const u8,
    family: os.sa_family_t,
    port: u16,
) !void {
    const file = fs.openFileAbsoluteC("/etc/hosts", .{}) catch |err| switch (err) {
        error.FileNotFound,
        error.NotDir,
        error.AccessDenied,
        => return,
        else => |e| return e,
    };
    defer file.close();

    const stream = &std.io.BufferedInStream(fs.File.ReadError).init(&file.inStream().stream).stream;
    var line_buf: [512]u8 = undefined;
    while (stream.readUntilDelimiterOrEof(&line_buf, '\n') catch |err| switch (err) {
        error.StreamTooLong => blk: {
            // Skip to the delimiter in the stream, to fix parsing
            try stream.skipUntilDelimiterOrEof('\n');
            // Use the truncated line. A truncated comment or hostname will be handled correctly.
            break :blk line_buf[0..];
        },
        else => |e| return e,
    }) |line| {
        const no_comment_line = mem.separate(line, "#").next().?;

        var line_it = mem.tokenize(no_comment_line, " \t");
        const ip_text = line_it.next() orelse continue;
        var first_name_text: ?[]const u8 = null;
        while (line_it.next()) |name_text| {
            if (first_name_text == null) first_name_text = name_text;
            if (mem.eql(u8, name_text, name)) {
                break;
            }
        } else continue;

        const addr = Address.parseExpectingFamily(ip_text, family, port) catch |err| switch (err) {
            error.Overflow,
            error.InvalidEnd,
            error.InvalidCharacter,
            error.Incomplete,
            error.InvalidIPAddressFormat,
            error.InvalidIpv4Mapping,
            => continue,
        };
        try addrs.append(LookupAddr{ .addr = addr });

        // first name is canonical name
        const name_text = first_name_text.?;
        if (isValidHostName(name_text)) {
            try canon.replaceContents(name_text);
        }
    }
}

pub fn isValidHostName(hostname: []const u8) bool {
    if (hostname.len >= 254) return false;
    if (!std.unicode.utf8ValidateSlice(hostname)) return false;
    for (hostname) |byte| {
        if (byte >= 0x80 or byte == '.' or byte == '-' or std.ascii.isAlNum(byte)) {
            continue;
        }
        return false;
    }
    return true;
}

fn linuxLookupNameFromDnsSearch(
    addrs: *std.ArrayList(LookupAddr),
    canon: *std.Buffer,
    name: []const u8,
    family: os.sa_family_t,
    port: u16,
) !void {
    var rc: ResolvConf = undefined;
    try getResolvConf(addrs.allocator, &rc);
    defer rc.deinit();

    // Count dots, suppress search when >=ndots or name ends in
    // a dot, which is an explicit request for global scope.
    var dots: usize = 0;
    for (name) |byte| {
        if (byte == '.') dots += 1;
    }

    const search = if (rc.search.isNull() or dots >= rc.ndots or mem.endsWith(u8, name, "."))
        &[_]u8{}
    else
        rc.search.toSliceConst();

    var canon_name = name;

    // Strip final dot for canon, fail if multiple trailing dots.
    if (mem.endsWith(u8, canon_name, ".")) canon_name.len -= 1;
    if (mem.endsWith(u8, canon_name, ".")) return error.UnknownHostName;

    // Name with search domain appended is setup in canon[]. This both
    // provides the desired default canonical name (if the requested
    // name is not a CNAME record) and serves as a buffer for passing
    // the full requested name to name_from_dns.
    try canon.resize(canon_name.len);
    mem.copy(u8, canon.toSlice(), canon_name);
    try canon.appendByte('.');

    var tok_it = mem.tokenize(search, " \t");
    while (tok_it.next()) |tok| {
        canon.shrink(canon_name.len + 1);
        try canon.append(tok);
        try linuxLookupNameFromDns(addrs, canon, canon.toSliceConst(), family, rc, port);
        if (addrs.len != 0) return;
    }

    canon.shrink(canon_name.len);
    return linuxLookupNameFromDns(addrs, canon, name, family, rc, port);
}

const dpc_ctx = struct {
    addrs: *std.ArrayList(LookupAddr),
    canon: *std.Buffer,
    port: u16,
};

fn linuxLookupNameFromDns(
    addrs: *std.ArrayList(LookupAddr),
    canon: *std.Buffer,
    name: []const u8,
    family: os.sa_family_t,
    rc: ResolvConf,
    port: u16,
) !void {
    var ctx = dpc_ctx{
        .addrs = addrs,
        .canon = canon,
        .port = port,
    };
    const AfRr = struct {
        af: os.sa_family_t,
        rr: u8,
    };
    const afrrs = [_]AfRr{
        AfRr{ .af = os.AF_INET6, .rr = os.RR_A },
        AfRr{ .af = os.AF_INET, .rr = os.RR_AAAA },
    };
    var qbuf: [2][280]u8 = undefined;
    var abuf: [2][512]u8 = undefined;
    var qp: [2][]const u8 = undefined;
    const apbuf = [2][]u8{ &abuf[0], &abuf[1] };
    var nq: usize = 0;

    for (afrrs) |afrr| {
        if (family != afrr.af) {
            const len = os.res_mkquery(0, name, 1, afrr.rr, &[_]u8{}, null, &qbuf[nq]);
            qp[nq] = qbuf[nq][0..len];
            nq += 1;
        }
    }

    var ap = [2][]u8{ apbuf[0][0..0], apbuf[1][0..0] };
    try resMSendRc(qp[0..nq], ap[0..nq], apbuf[0..nq], rc);

    var i: usize = 0;
    while (i < nq) : (i += 1) {
        dnsParse(ap[i], ctx, dnsParseCallback) catch {};
    }

    if (addrs.len != 0) return;
    if (ap[0].len < 4 or (ap[0][3] & 15) == 2) return error.TemporaryNameServerFailure;
    if ((ap[0][3] & 15) == 0) return error.UnknownHostName;
    if ((ap[0][3] & 15) == 3) return;
    return error.NameServerFailure;
}

const ResolvConf = struct {
    attempts: u32,
    ndots: u32,
    timeout: u32,
    search: std.Buffer,
    ns: std.ArrayList(LookupAddr),

    fn deinit(rc: *ResolvConf) void {
        rc.ns.deinit();
        rc.search.deinit();
        rc.* = undefined;
    }
};

/// Ignores lines longer than 512 bytes.
/// TODO: https://github.com/ziglang/zig/issues/2765 and https://github.com/ziglang/zig/issues/2761
fn getResolvConf(allocator: *mem.Allocator, rc: *ResolvConf) !void {
    rc.* = ResolvConf{
        .ns = std.ArrayList(LookupAddr).init(allocator),
        .search = std.Buffer.initNull(allocator),
        .ndots = 1,
        .timeout = 5,
        .attempts = 2,
    };
    errdefer rc.deinit();

    const file = fs.openFileAbsoluteC("/etc/resolv.conf", .{}) catch |err| switch (err) {
        error.FileNotFound,
        error.NotDir,
        error.AccessDenied,
        => return linuxLookupNameFromNumericUnspec(&rc.ns, "127.0.0.1", 53),
        else => |e| return e,
    };
    defer file.close();

    const stream = &std.io.BufferedInStream(fs.File.ReadError).init(&file.inStream().stream).stream;
    var line_buf: [512]u8 = undefined;
    while (stream.readUntilDelimiterOrEof(&line_buf, '\n') catch |err| switch (err) {
        error.StreamTooLong => blk: {
            // Skip to the delimiter in the stream, to fix parsing
            try stream.skipUntilDelimiterOrEof('\n');
            // Give an empty line to the while loop, which will be skipped.
            break :blk line_buf[0..0];
        },
        else => |e| return e,
    }) |line| {
        const no_comment_line = mem.separate(line, "#").next().?;
        var line_it = mem.tokenize(no_comment_line, " \t");

        const token = line_it.next() orelse continue;
        if (mem.eql(u8, token, "options")) {
            while (line_it.next()) |sub_tok| {
                var colon_it = mem.separate(sub_tok, ":");
                const name = colon_it.next().?;
                const value_txt = colon_it.next() orelse continue;
                const value = std.fmt.parseInt(u8, value_txt, 10) catch |err| switch (err) {
                    error.Overflow => 255,
                    error.InvalidCharacter => continue,
                };
                if (mem.eql(u8, name, "ndots")) {
                    rc.ndots = std.math.min(value, 15);
                } else if (mem.eql(u8, name, "attempts")) {
                    rc.attempts = std.math.min(value, 10);
                } else if (mem.eql(u8, name, "timeout")) {
                    rc.timeout = std.math.min(value, 60);
                }
            }
        } else if (mem.eql(u8, token, "nameserver")) {
            const ip_txt = line_it.next() orelse continue;
            try linuxLookupNameFromNumericUnspec(&rc.ns, ip_txt, 53);
        } else if (mem.eql(u8, token, "domain") or mem.eql(u8, token, "search")) {
            try rc.search.replaceContents(line_it.rest());
        }
    }

    if (rc.ns.len == 0) {
        return linuxLookupNameFromNumericUnspec(&rc.ns, "127.0.0.1", 53);
    }
}

fn linuxLookupNameFromNumericUnspec(
    addrs: *std.ArrayList(LookupAddr),
    name: []const u8,
    port: u16,
) !void {
    const addr = try Address.parseIp(name, port);
    (try addrs.addOne()).* = LookupAddr{ .addr = addr };
}

fn resMSendRc(
    queries: []const []const u8,
    answers: [][]u8,
    answer_bufs: []const []u8,
    rc: ResolvConf,
) !void {
    const timeout = 1000 * rc.timeout;
    const attempts = rc.attempts;

    var sl: os.socklen_t = @sizeOf(os.sockaddr_in);
    var family: os.sa_family_t = os.AF_INET;

    var ns_list = std.ArrayList(Address).init(rc.ns.allocator);
    defer ns_list.deinit();

    try ns_list.resize(rc.ns.len);
    const ns = ns_list.toSlice();

    for (rc.ns.toSliceConst()) |iplit, i| {
        ns[i] = iplit.addr;
        assert(ns[i].getPort() == 53);
        if (iplit.addr.any.family != os.AF_INET) {
            sl = @sizeOf(os.sockaddr_in6);
            family = os.AF_INET6;
        }
    }

    // Get local address and open/bind a socket
    var sa: Address = undefined;
    @memset(@ptrCast([*]u8, &sa), 0, @sizeOf(Address));
    sa.any.family = family;
    const flags = os.SOCK_DGRAM | os.SOCK_CLOEXEC | os.SOCK_NONBLOCK;
    const fd = os.socket(family, flags, 0) catch |err| switch (err) {
        error.AddressFamilyNotSupported => blk: {
            // Handle case where system lacks IPv6 support
            if (family == os.AF_INET6) {
                family = os.AF_INET;
                break :blk try os.socket(os.AF_INET, flags, 0);
            }
            return err;
        },
        else => |e| return e,
    };
    defer os.close(fd);
    try os.bind(fd, &sa.any, sl);

    // Past this point, there are no errors. Each individual query will
    // yield either no reply (indicated by zero length) or an answer
    // packet which is up to the caller to interpret.

    // Convert any IPv4 addresses in a mixed environment to v4-mapped
    // TODO
    //if (family == AF_INET6) {
    //    setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &(int){0}, sizeof 0);
    //    for (i=0; i<nns; i++) {
    //        if (ns[i].sin.sin_family != AF_INET) continue;
    //        memcpy(ns[i].sin6.sin6_addr.s6_addr+12,
    //            &ns[i].sin.sin_addr, 4);
    //        memcpy(ns[i].sin6.sin6_addr.s6_addr,
    //            "\0\0\0\0\0\0\0\0\0\0\xff\xff", 12);
    //        ns[i].sin6.sin6_family = AF_INET6;
    //        ns[i].sin6.sin6_flowinfo = 0;
    //        ns[i].sin6.sin6_scope_id = 0;
    //    }
    //}

    var pfd = [1]os.pollfd{os.pollfd{
        .fd = fd,
        .events = os.POLLIN,
        .revents = undefined,
    }};
    const retry_interval = timeout / attempts;
    var next: u32 = 0;
    var t2: u64 = std.time.milliTimestamp();
    var t0 = t2;
    var t1 = t2 - retry_interval;

    var servfail_retry: usize = undefined;

    outer: while (t2 - t0 < timeout) : (t2 = std.time.milliTimestamp()) {
        if (t2 - t1 >= retry_interval) {
            // Query all configured nameservers in parallel
            var i: usize = 0;
            while (i < queries.len) : (i += 1) {
                if (answers[i].len == 0) {
                    var j: usize = 0;
                    while (j < ns.len) : (j += 1) {
                        _ = os.sendto(fd, queries[i], os.MSG_NOSIGNAL, &ns[j].any, sl) catch undefined;
                    }
                }
            }
            t1 = t2;
            servfail_retry = 2 * queries.len;
        }

        // Wait for a response, or until time to retry
        const clamped_timeout = std.math.min(@as(u31, std.math.maxInt(u31)), t1 + retry_interval - t2);
        const nevents = os.poll(&pfd, clamped_timeout) catch 0;
        if (nevents == 0) continue;

        while (true) {
            var sl_copy = sl;
            const rlen = os.recvfrom(fd, answer_bufs[next], 0, &sa.any, &sl_copy) catch break;

            // Ignore non-identifiable packets
            if (rlen < 4) continue;

            // Ignore replies from addresses we didn't send to
            var j: usize = 0;
            while (j < ns.len and !ns[j].eql(sa)) : (j += 1) {}
            if (j == ns.len) continue;

            // Find which query this answer goes with, if any
            var i: usize = next;
            while (i < queries.len and (answer_bufs[next][0] != queries[i][0] or
                answer_bufs[next][1] != queries[i][1])) : (i += 1)
            {}

            if (i == queries.len) continue;
            if (answers[i].len != 0) continue;

            // Only accept positive or negative responses;
            // retry immediately on server failure, and ignore
            // all other codes such as refusal.
            switch (answer_bufs[next][3] & 15) {
                0, 3 => {},
                2 => if (servfail_retry != 0) {
                    servfail_retry -= 1;
                    _ = os.sendto(fd, queries[i], os.MSG_NOSIGNAL, &ns[j].any, sl) catch undefined;
                },
                else => continue,
            }

            // Store answer in the right slot, or update next
            // available temp slot if it's already in place.
            answers[i].len = rlen;
            if (i == next) {
                while (next < queries.len and answers[next].len != 0) : (next += 1) {}
            } else {
                mem.copy(u8, answer_bufs[i], answer_bufs[next][0..rlen]);
            }

            if (next == queries.len) break :outer;
        }
    }
}

fn dnsParse(
    r: []const u8,
    ctx: var,
    comptime callback: var,
) !void {
    // This implementation is ported from musl libc.
    // A more idiomatic "ziggy" implementation would be welcome.
    if (r.len < 12) return error.InvalidDnsPacket;
    if ((r[3] & 15) != 0) return;
    var p = r.ptr + 12;
    var qdcount = r[4] * @as(usize, 256) + r[5];
    var ancount = r[6] * @as(usize, 256) + r[7];
    if (qdcount + ancount > 64) return error.InvalidDnsPacket;
    while (qdcount != 0) {
        qdcount -= 1;
        while (@ptrToInt(p) - @ptrToInt(r.ptr) < r.len and p[0] -% 1 < 127) p += 1;
        if (p[0] > 193 or (p[0] == 193 and p[1] > 254) or @ptrToInt(p) > @ptrToInt(r.ptr) + r.len - 6)
            return error.InvalidDnsPacket;
        p += @as(usize, 5) + @boolToInt(p[0] != 0);
    }
    while (ancount != 0) {
        ancount -= 1;
        while (@ptrToInt(p) - @ptrToInt(r.ptr) < r.len and p[0] -% 1 < 127) p += 1;
        if (p[0] > 193 or (p[0] == 193 and p[1] > 254) or @ptrToInt(p) > @ptrToInt(r.ptr) + r.len - 6)
            return error.InvalidDnsPacket;
        p += @as(usize, 1) + @boolToInt(p[0] != 0);
        const len = p[8] * @as(usize, 256) + p[9];
        if (@ptrToInt(p) + len > @ptrToInt(r.ptr) + r.len) return error.InvalidDnsPacket;
        try callback(ctx, p[1], p[10 .. 10 + len], r);
        p += 10 + len;
    }
}

fn dnsParseCallback(ctx: dpc_ctx, rr: u8, data: []const u8, packet: []const u8) !void {
    switch (rr) {
        os.RR_A => {
            if (data.len != 4) return error.InvalidDnsARecord;
            const new_addr = try ctx.addrs.addOne();
            new_addr.* = LookupAddr{
                // TODO slice [0..4] to make this *[4]u8 without @ptrCast
                .addr = Address.initIp4(@ptrCast(*const [4]u8, data.ptr).*, ctx.port),
            };
        },
        os.RR_AAAA => {
            if (data.len != 16) return error.InvalidDnsAAAARecord;
            const new_addr = try ctx.addrs.addOne();
            new_addr.* = LookupAddr{
                // TODO slice [0..16] to make this *[16]u8 without @ptrCast
                .addr = Address.initIp6(@ptrCast(*const [16]u8, data.ptr).*, ctx.port, 0, 0),
            };
        },
        os.RR_CNAME => {
            var tmp: [256]u8 = undefined;
            // Returns len of compressed name. strlen to get canon name.
            _ = try os.dn_expand(packet, data, &tmp);
            const canon_name = mem.toSliceConst(u8, @ptrCast([*:0]const u8, &tmp));
            if (isValidHostName(canon_name)) {
                try ctx.canon.replaceContents(canon_name);
            }
        },
        else => return,
    }
}

pub const StreamServer = struct {
    /// Copied from `Options` on `init`.
    kernel_backlog: u32,
    reuse_address: bool,

    /// `undefined` until `listen` returns successfully.
    listen_address: Address,

    sockfd: ?os.fd_t,

    pub const Options = struct {
        /// How many connections the kernel will accept on the application's behalf.
        /// If more than this many connections pool in the kernel, clients will start
        /// seeing "Connection refused".
        kernel_backlog: u32 = 128,

        /// Enable SO_REUSEADDR on the socket.
        reuse_address: bool = false,
    };

    /// After this call succeeds, resources have been acquired and must
    /// be released with `deinit`.
    pub fn init(options: Options) StreamServer {
        return StreamServer{
            .sockfd = null,
            .kernel_backlog = options.kernel_backlog,
            .reuse_address = options.reuse_address,
            .listen_address = undefined,
        };
    }

    /// Release all resources. The `StreamServer` memory becomes `undefined`.
    pub fn deinit(self: *StreamServer) void {
        self.close();
        self.* = undefined;
    }

    pub fn listen(self: *StreamServer, address: Address) !void {
        const nonblock = if (std.io.is_async) os.SOCK_NONBLOCK else 0;
        const sock_flags = os.SOCK_STREAM | os.SOCK_CLOEXEC | nonblock;
        const proto = if (address.any.family == os.AF_UNIX) @as(u32, 0) else os.IPPROTO_TCP;

        const sockfd = try os.socket(address.any.family, sock_flags, proto);
        self.sockfd = sockfd;
        errdefer {
            os.close(sockfd);
            self.sockfd = null;
        }

        if (self.reuse_address) {
            try os.setsockopt(
                self.sockfd.?,
                os.SOL_SOCKET,
                os.SO_REUSEADDR,
                &mem.toBytes(@as(c_int, 1)),
            );
        }

        var socklen = address.getOsSockLen();
        try os.bind(sockfd, &address.any, socklen);
        try os.listen(sockfd, self.kernel_backlog);
        try os.getsockname(sockfd, &self.listen_address.any, &socklen);
    }

    /// Stop listening. It is still necessary to call `deinit` after stopping listening.
    /// Calling `deinit` will automatically call `close`. It is safe to call `close` when
    /// not listening.
    pub fn close(self: *StreamServer) void {
        if (self.sockfd) |fd| {
            os.close(fd);
            self.sockfd = null;
            self.listen_address = undefined;
        }
    }

    pub const AcceptError = error{
        ConnectionAborted,

        /// The per-process limit on the number of open file descriptors has been reached.
        ProcessFdQuotaExceeded,

        /// The system-wide limit on the total number of open files has been reached.
        SystemFdQuotaExceeded,

        /// Not enough free memory.  This often means that the memory allocation  is  limited
        /// by the socket buffer limits, not by the system memory.
        SystemResources,

        ProtocolFailure,

        /// Firewall rules forbid connection.
        BlockedByFirewall,
    } || os.UnexpectedError;

    pub const Connection = struct {
        file: fs.File,
        address: Address,
    };

    /// If this function succeeds, the returned `Connection` is a caller-managed resource.
    pub fn accept(self: *StreamServer) AcceptError!Connection {
        const nonblock = if (std.io.is_async) os.SOCK_NONBLOCK else 0;
        const accept_flags = nonblock | os.SOCK_CLOEXEC;
        var accepted_addr: Address = undefined;
        var adr_len: os.socklen_t = @sizeOf(Address);
        if (os.accept4(self.sockfd.?, &accepted_addr.any, &adr_len, accept_flags)) |fd| {
            return Connection{
                .file = fs.File{
                    .handle = fd,
                    .io_mode = std.io.mode,
                },
                .address = accepted_addr,
            };
        } else |err| switch (err) {
            // We only give SOCK_NONBLOCK when I/O mode is async, in which case this error
            // is handled by os.accept4.
            error.WouldBlock => unreachable,
            else => |e| return e,
        }
    }
};

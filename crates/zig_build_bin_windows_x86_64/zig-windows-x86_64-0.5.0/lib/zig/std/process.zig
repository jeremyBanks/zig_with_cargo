const builtin = @import("builtin");
const std = @import("std.zig");
const os = std.os;
const fs = std.fs;
const BufMap = std.BufMap;
const Buffer = std.Buffer;
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;

pub const abort = os.abort;
pub const exit = os.exit;
pub const changeCurDir = os.chdir;
pub const changeCurDirC = os.chdirC;

/// The result is a slice of `out_buffer`, from index `0`.
pub fn getCwd(out_buffer: *[fs.MAX_PATH_BYTES]u8) ![]u8 {
    return os.getcwd(out_buffer);
}

/// Caller must free the returned memory.
pub fn getCwdAlloc(allocator: *Allocator) ![]u8 {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    return mem.dupe(allocator, u8, try os.getcwd(&buf));
}

test "getCwdAlloc" {
    // at least call it so it gets compiled
    var buf: [1000]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buf).allocator;
    _ = getCwdAlloc(allocator) catch undefined;
}

/// Caller must free result when done.
/// TODO make this go through libc when we have it
pub fn getEnvMap(allocator: *Allocator) !BufMap {
    var result = BufMap.init(allocator);
    errdefer result.deinit();

    if (os.windows.is_the_target) {
        const ptr = try os.windows.GetEnvironmentStringsW();
        defer os.windows.FreeEnvironmentStringsW(ptr);

        var i: usize = 0;
        while (true) {
            if (ptr[i] == 0) return result;

            const key_start = i;

            while (ptr[i] != 0 and ptr[i] != '=') : (i += 1) {}
            const key_w = ptr[key_start..i];
            const key = try std.unicode.utf16leToUtf8Alloc(allocator, key_w);
            errdefer allocator.free(key);

            if (ptr[i] == '=') i += 1;

            const value_start = i;
            while (ptr[i] != 0) : (i += 1) {}
            const value_w = ptr[value_start..i];
            const value = try std.unicode.utf16leToUtf8Alloc(allocator, value_w);
            errdefer allocator.free(value);

            i += 1; // skip over null byte

            try result.setMove(key, value);
        }
    } else if (builtin.os == .wasi) {
        var environ_count: usize = undefined;
        var environ_buf_size: usize = undefined;

        const environ_sizes_get_ret = os.wasi.environ_sizes_get(&environ_count, &environ_buf_size);
        if (environ_sizes_get_ret != os.wasi.ESUCCESS) {
            return os.unexpectedErrno(environ_sizes_get_ret);
        }

        // TODO: Verify that the documentation is incorrect
        // https://github.com/WebAssembly/WASI/issues/27
        var environ = try allocator.alloc(?[*]u8, environ_count + 1);
        defer allocator.free(environ);
        var environ_buf = try std.heap.wasm_allocator.alloc(u8, environ_buf_size);
        defer allocator.free(environ_buf);

        const environ_get_ret = os.wasi.environ_get(environ.ptr, environ_buf.ptr);
        if (environ_get_ret != os.wasi.ESUCCESS) {
            return os.unexpectedErrno(environ_get_ret);
        }

        for (environ) |env| {
            if (env) |ptr| {
                const pair = mem.toSlice(u8, ptr);
                var parts = mem.separate(pair, "=");
                const key = parts.next().?;
                const value = parts.next().?;
                try result.set(key, value);
            }
        }
        return result;
    } else {
        for (os.environ) |ptr| {
            var line_i: usize = 0;
            while (ptr[line_i] != 0 and ptr[line_i] != '=') : (line_i += 1) {}
            const key = ptr[0..line_i];

            var end_i: usize = line_i;
            while (ptr[end_i] != 0) : (end_i += 1) {}
            const value = ptr[line_i + 1 .. end_i];

            try result.set(key, value);
        }
        return result;
    }
}

test "os.getEnvMap" {
    var env = try getEnvMap(std.debug.global_allocator);
    defer env.deinit();
}

pub const GetEnvVarOwnedError = error{
    OutOfMemory,
    EnvironmentVariableNotFound,

    /// See https://github.com/ziglang/zig/issues/1774
    InvalidUtf8,
};

/// Caller must free returned memory.
/// TODO make this go through libc when we have it
pub fn getEnvVarOwned(allocator: *mem.Allocator, key: []const u8) GetEnvVarOwnedError![]u8 {
    if (os.windows.is_the_target) {
        const key_with_null = try std.unicode.utf8ToUtf16LeWithNull(allocator, key);
        defer allocator.free(key_with_null);

        var buf = try allocator.alloc(u16, 256);
        defer allocator.free(buf);

        while (true) {
            const windows_buf_len = math.cast(os.windows.DWORD, buf.len) catch return error.OutOfMemory;
            const result = os.windows.GetEnvironmentVariableW(
                key_with_null.ptr,
                buf.ptr,
                windows_buf_len,
            ) catch |err| switch (err) {
                error.Unexpected => return error.EnvironmentVariableNotFound,
                else => |e| return e,
            };
            if (result > buf.len) {
                buf = try allocator.realloc(buf, result);
                continue;
            }

            return std.unicode.utf16leToUtf8Alloc(allocator, buf[0..result]) catch |err| switch (err) {
                error.DanglingSurrogateHalf => return error.InvalidUtf8,
                error.ExpectedSecondSurrogateHalf => return error.InvalidUtf8,
                error.UnexpectedSecondSurrogateHalf => return error.InvalidUtf8,
                else => |e| return e,
            };
        }
    } else {
        const result = os.getenv(key) orelse return error.EnvironmentVariableNotFound;
        return mem.dupe(allocator, u8, result);
    }
}

test "os.getEnvVarOwned" {
    var ga = std.debug.global_allocator;
    testing.expectError(error.EnvironmentVariableNotFound, getEnvVarOwned(ga, "BADENV"));
}

pub const ArgIteratorPosix = struct {
    index: usize,
    count: usize,

    pub fn init() ArgIteratorPosix {
        return ArgIteratorPosix{
            .index = 0,
            .count = os.argv.len,
        };
    }

    pub fn next(self: *ArgIteratorPosix) ?[]const u8 {
        if (self.index == self.count) return null;

        const s = os.argv[self.index];
        self.index += 1;
        return mem.toSlice(u8, s);
    }

    pub fn skip(self: *ArgIteratorPosix) bool {
        if (self.index == self.count) return false;

        self.index += 1;
        return true;
    }
};

pub const ArgIteratorWindows = struct {
    index: usize,
    cmd_line: [*]const u8,
    in_quote: bool,
    quote_count: usize,
    seen_quote_count: usize,

    pub const NextError = error{OutOfMemory};

    pub fn init() ArgIteratorWindows {
        return initWithCmdLine(os.windows.kernel32.GetCommandLineA());
    }

    pub fn initWithCmdLine(cmd_line: [*]const u8) ArgIteratorWindows {
        return ArgIteratorWindows{
            .index = 0,
            .cmd_line = cmd_line,
            .in_quote = false,
            .quote_count = countQuotes(cmd_line),
            .seen_quote_count = 0,
        };
    }

    /// You must free the returned memory when done.
    pub fn next(self: *ArgIteratorWindows, allocator: *Allocator) ?(NextError![]u8) {
        // march forward over whitespace
        while (true) : (self.index += 1) {
            const byte = self.cmd_line[self.index];
            switch (byte) {
                0 => return null,
                ' ', '\t' => continue,
                else => break,
            }
        }

        return self.internalNext(allocator);
    }

    pub fn skip(self: *ArgIteratorWindows) bool {
        // march forward over whitespace
        while (true) : (self.index += 1) {
            const byte = self.cmd_line[self.index];
            switch (byte) {
                0 => return false,
                ' ', '\t' => continue,
                else => break,
            }
        }

        var backslash_count: usize = 0;
        while (true) : (self.index += 1) {
            const byte = self.cmd_line[self.index];
            switch (byte) {
                0 => return true,
                '"' => {
                    const quote_is_real = backslash_count % 2 == 0;
                    if (quote_is_real) {
                        self.seen_quote_count += 1;
                    }
                },
                '\\' => {
                    backslash_count += 1;
                },
                ' ', '\t' => {
                    if (self.seen_quote_count % 2 == 0 or self.seen_quote_count == self.quote_count) {
                        return true;
                    }
                    backslash_count = 0;
                },
                else => {
                    backslash_count = 0;
                    continue;
                },
            }
        }
    }

    fn internalNext(self: *ArgIteratorWindows, allocator: *Allocator) NextError![]u8 {
        var buf = try Buffer.initSize(allocator, 0);
        defer buf.deinit();

        var backslash_count: usize = 0;
        while (true) : (self.index += 1) {
            const byte = self.cmd_line[self.index];
            switch (byte) {
                0 => return buf.toOwnedSlice(),
                '"' => {
                    const quote_is_real = backslash_count % 2 == 0;
                    try self.emitBackslashes(&buf, backslash_count / 2);
                    backslash_count = 0;

                    if (quote_is_real) {
                        self.seen_quote_count += 1;
                        if (self.seen_quote_count == self.quote_count and self.seen_quote_count % 2 == 1) {
                            try buf.appendByte('"');
                        }
                    } else {
                        try buf.appendByte('"');
                    }
                },
                '\\' => {
                    backslash_count += 1;
                },
                ' ', '\t' => {
                    try self.emitBackslashes(&buf, backslash_count);
                    backslash_count = 0;
                    if (self.seen_quote_count % 2 == 1 and self.seen_quote_count != self.quote_count) {
                        try buf.appendByte(byte);
                    } else {
                        return buf.toOwnedSlice();
                    }
                },
                else => {
                    try self.emitBackslashes(&buf, backslash_count);
                    backslash_count = 0;
                    try buf.appendByte(byte);
                },
            }
        }
    }

    fn emitBackslashes(self: *ArgIteratorWindows, buf: *Buffer, emit_count: usize) !void {
        var i: usize = 0;
        while (i < emit_count) : (i += 1) {
            try buf.appendByte('\\');
        }
    }

    fn countQuotes(cmd_line: [*]const u8) usize {
        var result: usize = 0;
        var backslash_count: usize = 0;
        var index: usize = 0;
        while (true) : (index += 1) {
            const byte = cmd_line[index];
            switch (byte) {
                0 => return result,
                '\\' => backslash_count += 1,
                '"' => {
                    result += 1 - (backslash_count % 2);
                    backslash_count = 0;
                },
                else => {
                    backslash_count = 0;
                },
            }
        }
    }
};

pub const ArgIterator = struct {
    const InnerType = if (builtin.os == .windows) ArgIteratorWindows else ArgIteratorPosix;

    inner: InnerType,

    pub fn init() ArgIterator {
        if (builtin.os == .wasi) {
            // TODO: Figure out a compatible interface accomodating WASI
            @compileError("ArgIterator is not yet supported in WASI. Use argsAlloc and argsFree instead.");
        }

        return ArgIterator{ .inner = InnerType.init() };
    }

    pub const NextError = ArgIteratorWindows.NextError;

    /// You must free the returned memory when done.
    pub fn next(self: *ArgIterator, allocator: *Allocator) ?(NextError![]u8) {
        if (builtin.os == .windows) {
            return self.inner.next(allocator);
        } else {
            return mem.dupe(allocator, u8, self.inner.next() orelse return null);
        }
    }

    /// If you only are targeting posix you can call this and not need an allocator.
    pub fn nextPosix(self: *ArgIterator) ?[]const u8 {
        return self.inner.next();
    }

    /// Parse past 1 argument without capturing it.
    /// Returns `true` if skipped an arg, `false` if we are at the end.
    pub fn skip(self: *ArgIterator) bool {
        return self.inner.skip();
    }
};

pub fn args() ArgIterator {
    return ArgIterator.init();
}

/// Caller must call argsFree on result.
pub fn argsAlloc(allocator: *mem.Allocator) ![][]u8 {
    if (builtin.os == .wasi) {
        var count: usize = undefined;
        var buf_size: usize = undefined;

        const args_sizes_get_ret = os.wasi.args_sizes_get(&count, &buf_size);
        if (args_sizes_get_ret != os.wasi.ESUCCESS) {
            return os.unexpectedErrno(args_sizes_get_ret);
        }

        var argv = try allocator.alloc([*]u8, count);
        defer allocator.free(argv);

        var argv_buf = try allocator.alloc(u8, buf_size);
        const args_get_ret = os.wasi.args_get(argv.ptr, argv_buf.ptr);
        if (args_get_ret != os.wasi.ESUCCESS) {
            return os.unexpectedErrno(args_get_ret);
        }

        var result_slice = try allocator.alloc([]u8, count);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            result_slice[i] = mem.toSlice(u8, argv[i]);
        }

        return result_slice;
    }

    // TODO refactor to only make 1 allocation.
    var it = args();
    var contents = try Buffer.initSize(allocator, 0);
    defer contents.deinit();

    var slice_list = std.ArrayList(usize).init(allocator);
    defer slice_list.deinit();

    while (it.next(allocator)) |arg_or_err| {
        const arg = try arg_or_err;
        defer allocator.free(arg);
        try contents.append(arg);
        try slice_list.append(arg.len);
    }

    const contents_slice = contents.toSliceConst();
    const slice_sizes = slice_list.toSliceConst();
    const slice_list_bytes = try math.mul(usize, @sizeOf([]u8), slice_sizes.len);
    const total_bytes = try math.add(usize, slice_list_bytes, contents_slice.len);
    const buf = try allocator.alignedAlloc(u8, @alignOf([]u8), total_bytes);
    errdefer allocator.free(buf);

    const result_slice_list = @bytesToSlice([]u8, buf[0..slice_list_bytes]);
    const result_contents = buf[slice_list_bytes..];
    mem.copy(u8, result_contents, contents_slice);

    var contents_index: usize = 0;
    for (slice_sizes) |len, i| {
        const new_index = contents_index + len;
        result_slice_list[i] = result_contents[contents_index..new_index];
        contents_index = new_index;
    }

    return result_slice_list;
}

pub fn argsFree(allocator: *mem.Allocator, args_alloc: []const []u8) void {
    if (builtin.os == .wasi) {
        const last_item = args_alloc[args_alloc.len - 1];
        const last_byte_addr = @ptrToInt(last_item.ptr) + last_item.len + 1; // null terminated
        const first_item_ptr = args_alloc[0].ptr;
        const len = last_byte_addr - @ptrToInt(first_item_ptr);
        allocator.free(first_item_ptr[0..len]);

        return allocator.free(args_alloc);
    }

    var total_bytes: usize = 0;
    for (args_alloc) |arg| {
        total_bytes += @sizeOf([]u8) + arg.len;
    }
    const unaligned_allocated_buf = @ptrCast([*]const u8, args_alloc.ptr)[0..total_bytes];
    const aligned_allocated_buf = @alignCast(@alignOf([]u8), unaligned_allocated_buf);
    return allocator.free(aligned_allocated_buf);
}

test "windows arg parsing" {
    testWindowsCmdLine(c"a   b\tc d", [_][]const u8{ "a", "b", "c", "d" });
    testWindowsCmdLine(c"\"abc\" d e", [_][]const u8{ "abc", "d", "e" });
    testWindowsCmdLine(c"a\\\\\\b d\"e f\"g h", [_][]const u8{ "a\\\\\\b", "de fg", "h" });
    testWindowsCmdLine(c"a\\\\\\\"b c d", [_][]const u8{ "a\\\"b", "c", "d" });
    testWindowsCmdLine(c"a\\\\\\\\\"b c\" d e", [_][]const u8{ "a\\\\b c", "d", "e" });
    testWindowsCmdLine(c"a   b\tc \"d f", [_][]const u8{ "a", "b", "c", "\"d", "f" });

    testWindowsCmdLine(c"\".\\..\\zig-cache\\build\" \"bin\\zig.exe\" \".\\..\" \".\\..\\zig-cache\" \"--help\"", [_][]const u8{
        ".\\..\\zig-cache\\build",
        "bin\\zig.exe",
        ".\\..",
        ".\\..\\zig-cache",
        "--help",
    });
}

fn testWindowsCmdLine(input_cmd_line: [*]const u8, expected_args: []const []const u8) void {
    var it = ArgIteratorWindows.initWithCmdLine(input_cmd_line);
    for (expected_args) |expected_arg| {
        const arg = it.next(std.debug.global_allocator).? catch unreachable;
        testing.expectEqualSlices(u8, expected_arg, arg);
    }
    testing.expect(it.next(std.debug.global_allocator) == null);
}

pub const UserInfo = struct {
    uid: u32,
    gid: u32,
};

/// POSIX function which gets a uid from username.
pub fn getUserInfo(name: []const u8) !UserInfo {
    return switch (builtin.os) {
        .linux, .macosx, .watchos, .tvos, .ios, .freebsd, .netbsd => posixGetUserInfo(name),
        else => @compileError("Unsupported OS"),
    };
}

/// TODO this reads /etc/passwd. But sometimes the user/id mapping is in something else
/// like NIS, AD, etc. See `man nss` or look at an strace for `id myuser`.
pub fn posixGetUserInfo(name: []const u8) !UserInfo {
    var in_stream = try io.InStream.open("/etc/passwd", null);
    defer in_stream.close();

    const State = enum {
        Start,
        WaitForNextLine,
        SkipPassword,
        ReadUserId,
        ReadGroupId,
    };

    var buf: [std.mem.page_size]u8 = undefined;
    var name_index: usize = 0;
    var state = State.Start;
    var uid: u32 = 0;
    var gid: u32 = 0;

    while (true) {
        const amt_read = try in_stream.read(buf[0..]);
        for (buf[0..amt_read]) |byte| {
            switch (state) {
                .Start => switch (byte) {
                    ':' => {
                        state = if (name_index == name.len) State.SkipPassword else State.WaitForNextLine;
                    },
                    '\n' => return error.CorruptPasswordFile,
                    else => {
                        if (name_index == name.len or name[name_index] != byte) {
                            state = .WaitForNextLine;
                        }
                        name_index += 1;
                    },
                },
                .WaitForNextLine => switch (byte) {
                    '\n' => {
                        name_index = 0;
                        state = .Start;
                    },
                    else => continue,
                },
                .SkipPassword => switch (byte) {
                    '\n' => return error.CorruptPasswordFile,
                    ':' => {
                        state = .ReadUserId;
                    },
                    else => continue,
                },
                .ReadUserId => switch (byte) {
                    ':' => {
                        state = .ReadGroupId;
                    },
                    '\n' => return error.CorruptPasswordFile,
                    else => {
                        const digit = switch (byte) {
                            '0'...'9' => byte - '0',
                            else => return error.CorruptPasswordFile,
                        };
                        if (@mulWithOverflow(u32, uid, 10, *uid)) return error.CorruptPasswordFile;
                        if (@addWithOverflow(u32, uid, digit, *uid)) return error.CorruptPasswordFile;
                    },
                },
                .ReadGroupId => switch (byte) {
                    '\n', ':' => {
                        return UserInfo{
                            .uid = uid,
                            .gid = gid,
                        };
                    },
                    else => {
                        const digit = switch (byte) {
                            '0'...'9' => byte - '0',
                            else => return error.CorruptPasswordFile,
                        };
                        if (@mulWithOverflow(u32, gid, 10, *gid)) return error.CorruptPasswordFile;
                        if (@addWithOverflow(u32, gid, digit, *gid)) return error.CorruptPasswordFile;
                    },
                },
            }
        }
        if (amt_read < buf.len) return error.UserNotFound;
    }
}

pub fn getBaseAddress() usize {
    switch (builtin.os) {
        .linux => {
            const base = os.system.getauxval(std.elf.AT_BASE);
            if (base != 0) {
                return base;
            }
            const phdr = os.system.getauxval(std.elf.AT_PHDR);
            return phdr - @sizeOf(std.elf.Ehdr);
        },
        .macosx, .freebsd, .netbsd => {
            return @ptrToInt(&std.c._mh_execute_header);
        },
        .windows => return @ptrToInt(os.windows.kernel32.GetModuleHandleW(null)),
        else => @compileError("Unsupported OS"),
    }
}

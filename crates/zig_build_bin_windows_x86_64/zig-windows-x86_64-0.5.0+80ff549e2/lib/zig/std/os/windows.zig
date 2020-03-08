// This file contains thin wrappers around Windows-specific APIs, with these
// specific goals in mind:
// * Convert "errno"-style error codes into Zig errors.
// * When null-terminated or UTF16LE byte buffers are required, provide APIs which accept
//   slices as well as APIs which accept null-terminated UTF16LE byte buffers.

const builtin = @import("builtin");
const std = @import("../std.zig");
const mem = std.mem;
const assert = std.debug.assert;
const math = std.math;
const maxInt = std.math.maxInt;

pub const advapi32 = @import("windows/advapi32.zig");
pub const kernel32 = @import("windows/kernel32.zig");
pub const ntdll = @import("windows/ntdll.zig");
pub const ole32 = @import("windows/ole32.zig");
pub const psapi = @import("windows/psapi.zig");
pub const shell32 = @import("windows/shell32.zig");
pub const ws2_32 = @import("windows/ws2_32.zig");

pub usingnamespace @import("windows/bits.zig");

pub const self_process_handle = @intToPtr(HANDLE, maxInt(usize));

pub const CreateFileError = error{
    SharingViolation,
    PathAlreadyExists,

    /// When any of the path components can not be found or the file component can not
    /// be found. Some operating systems distinguish between path components not found and
    /// file components not found, but they are collapsed into FileNotFound to gain
    /// consistency across operating systems.
    FileNotFound,

    AccessDenied,
    PipeBusy,
    NameTooLong,

    /// On Windows, file paths must be valid Unicode.
    InvalidUtf8,

    /// On Windows, file paths cannot contain these characters:
    /// '/', '*', '?', '"', '<', '>', '|'
    BadPathName,

    Unexpected,
};

pub fn CreateFile(
    file_path: []const u8,
    desired_access: DWORD,
    share_mode: DWORD,
    lpSecurityAttributes: ?LPSECURITY_ATTRIBUTES,
    creation_disposition: DWORD,
    flags_and_attrs: DWORD,
    hTemplateFile: ?HANDLE,
) CreateFileError!HANDLE {
    const file_path_w = try sliceToPrefixedFileW(file_path);
    return CreateFileW(&file_path_w, desired_access, share_mode, lpSecurityAttributes, creation_disposition, flags_and_attrs, hTemplateFile);
}

pub fn CreateFileW(
    file_path_w: [*:0]const u16,
    desired_access: DWORD,
    share_mode: DWORD,
    lpSecurityAttributes: ?LPSECURITY_ATTRIBUTES,
    creation_disposition: DWORD,
    flags_and_attrs: DWORD,
    hTemplateFile: ?HANDLE,
) CreateFileError!HANDLE {
    const result = kernel32.CreateFileW(file_path_w, desired_access, share_mode, lpSecurityAttributes, creation_disposition, flags_and_attrs, hTemplateFile);

    if (result == INVALID_HANDLE_VALUE) {
        switch (kernel32.GetLastError()) {
            .SHARING_VIOLATION => return error.SharingViolation,
            .ALREADY_EXISTS => return error.PathAlreadyExists,
            .FILE_EXISTS => return error.PathAlreadyExists,
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            .ACCESS_DENIED => return error.AccessDenied,
            .PIPE_BUSY => return error.PipeBusy,
            .FILENAME_EXCED_RANGE => return error.NameTooLong,
            else => |err| return unexpectedError(err),
        }
    }

    return result;
}

pub const CreatePipeError = error{Unexpected};

pub fn CreatePipe(rd: *HANDLE, wr: *HANDLE, sattr: *const SECURITY_ATTRIBUTES) CreatePipeError!void {
    if (kernel32.CreatePipe(rd, wr, sattr, 0) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub fn CreateEventEx(attributes: ?*SECURITY_ATTRIBUTES, name: []const u8, flags: DWORD, desired_access: DWORD) !HANDLE {
    const nameW = try sliceToPrefixedFileW(name);
    return CreateEventExW(attributes, &nameW, flags, desired_access);
}

pub fn CreateEventExW(attributes: ?*SECURITY_ATTRIBUTES, nameW: [*:0]const u16, flags: DWORD, desired_access: DWORD) !HANDLE {
    const handle = kernel32.CreateEventExW(attributes, nameW, flags, desired_access);
    if (handle) |h| {
        return h;
    } else {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub fn DeviceIoControl(
    h: HANDLE,
    ioControlCode: DWORD,
    in: ?[]const u8,
    out: ?[]u8,
    overlapped: ?*OVERLAPPED,
) !DWORD {
    var bytes: DWORD = undefined;
    if (kernel32.DeviceIoControl(
        h,
        ioControlCode,
        if (in) |i| i.ptr else null,
        if (in) |i| @intCast(u32, i.len) else 0,
        if (out) |o| o.ptr else null,
        if (out) |o| @intCast(u32, o.len) else 0,
        &bytes,
        overlapped,
    ) == 0) {
        switch (kernel32.GetLastError()) {
            .IO_PENDING => if (overlapped == null) unreachable,
            else => |err| return unexpectedError(err),
        }
    }
    return bytes;
}

pub fn GetOverlappedResult(h: HANDLE, overlapped: *OVERLAPPED, wait: bool) !DWORD {
    var bytes: DWORD = undefined;
    if (kernel32.GetOverlappedResult(h, overlapped, &bytes, @boolToInt(wait)) == 0) {
        switch (kernel32.GetLastError()) {
            .IO_INCOMPLETE => if (!wait) return error.WouldBlock else unreachable,
            else => |err| return unexpectedError(err),
        }
    }
    return bytes;
}

pub const SetHandleInformationError = error{Unexpected};

pub fn SetHandleInformation(h: HANDLE, mask: DWORD, flags: DWORD) SetHandleInformationError!void {
    if (kernel32.SetHandleInformation(h, mask, flags) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub const RtlGenRandomError = error{Unexpected};

/// Call RtlGenRandom() instead of CryptGetRandom() on Windows
/// https://github.com/rust-lang-nursery/rand/issues/111
/// https://bugzilla.mozilla.org/show_bug.cgi?id=504270
pub fn RtlGenRandom(output: []u8) RtlGenRandomError!void {
    var total_read: usize = 0;
    var buff: []u8 = output[0..];
    const max_read_size: ULONG = maxInt(ULONG);

    while (total_read < output.len) {
        const to_read: ULONG = math.min(buff.len, max_read_size);

        if (advapi32.RtlGenRandom(buff.ptr, to_read) == 0) {
            return unexpectedError(kernel32.GetLastError());
        }

        total_read += to_read;
        buff = buff[to_read..];
    }
}

pub const WaitForSingleObjectError = error{
    WaitAbandoned,
    WaitTimeOut,
    Unexpected,
};

pub fn WaitForSingleObject(handle: HANDLE, milliseconds: DWORD) WaitForSingleObjectError!void {
    return WaitForSingleObjectEx(handle, milliseconds, false);
}

pub fn WaitForSingleObjectEx(handle: HANDLE, milliseconds: DWORD, alertable: bool) WaitForSingleObjectError!void {
    switch (kernel32.WaitForSingleObjectEx(handle, milliseconds, @boolToInt(alertable))) {
        WAIT_ABANDONED => return error.WaitAbandoned,
        WAIT_OBJECT_0 => return,
        WAIT_TIMEOUT => return error.WaitTimeOut,
        WAIT_FAILED => switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        },
        else => return error.Unexpected,
    }
}

pub fn WaitForMultipleObjectsEx(handles: []const HANDLE, waitAll: bool, milliseconds: DWORD, alertable: bool) !u32 {
    assert(handles.len < MAXIMUM_WAIT_OBJECTS);
    const nCount: DWORD = @intCast(DWORD, handles.len);
    switch (kernel32.WaitForMultipleObjectsEx(
        nCount,
        handles.ptr,
        @boolToInt(waitAll),
        milliseconds,
        @boolToInt(alertable),
    )) {
        WAIT_OBJECT_0...WAIT_OBJECT_0 + MAXIMUM_WAIT_OBJECTS => |n| {
            const handle_index = n - WAIT_OBJECT_0;
            assert(handle_index < nCount);
            return handle_index;
        },
        WAIT_ABANDONED_0...WAIT_ABANDONED_0 + MAXIMUM_WAIT_OBJECTS => |n| {
            const handle_index = n - WAIT_ABANDONED_0;
            assert(handle_index < nCount);
            return error.WaitAbandoned;
        },
        WAIT_TIMEOUT => return error.WaitTimeOut,
        WAIT_FAILED => switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        },
        else => return error.Unexpected,
    }
}

pub const FindFirstFileError = error{
    FileNotFound,
    InvalidUtf8,
    BadPathName,
    NameTooLong,
    Unexpected,
};

pub fn FindFirstFile(dir_path: []const u8, find_file_data: *WIN32_FIND_DATAW) FindFirstFileError!HANDLE {
    const dir_path_w = try sliceToPrefixedSuffixedFileW(dir_path, [_]u16{ '\\', '*' });
    const handle = kernel32.FindFirstFileW(&dir_path_w, find_file_data);

    if (handle == INVALID_HANDLE_VALUE) {
        switch (kernel32.GetLastError()) {
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            else => |err| return unexpectedError(err),
        }
    }

    return handle;
}

pub const FindNextFileError = error{Unexpected};

/// Returns `true` if there was another file, `false` otherwise.
pub fn FindNextFile(handle: HANDLE, find_file_data: *WIN32_FIND_DATAW) FindNextFileError!bool {
    if (kernel32.FindNextFileW(handle, find_file_data) == 0) {
        switch (kernel32.GetLastError()) {
            .NO_MORE_FILES => return false,
            else => |err| return unexpectedError(err),
        }
    }
    return true;
}

pub const CreateIoCompletionPortError = error{Unexpected};

pub fn CreateIoCompletionPort(
    file_handle: HANDLE,
    existing_completion_port: ?HANDLE,
    completion_key: usize,
    concurrent_thread_count: DWORD,
) CreateIoCompletionPortError!HANDLE {
    const handle = kernel32.CreateIoCompletionPort(file_handle, existing_completion_port, completion_key, concurrent_thread_count) orelse {
        switch (kernel32.GetLastError()) {
            .INVALID_PARAMETER => unreachable,
            else => |err| return unexpectedError(err),
        }
    };
    return handle;
}

pub const PostQueuedCompletionStatusError = error{Unexpected};

pub fn PostQueuedCompletionStatus(
    completion_port: HANDLE,
    bytes_transferred_count: DWORD,
    completion_key: usize,
    lpOverlapped: ?*OVERLAPPED,
) PostQueuedCompletionStatusError!void {
    if (kernel32.PostQueuedCompletionStatus(completion_port, bytes_transferred_count, completion_key, lpOverlapped) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub const GetQueuedCompletionStatusResult = enum {
    Normal,
    Aborted,
    Cancelled,
    EOF,
};

pub fn GetQueuedCompletionStatus(
    completion_port: HANDLE,
    bytes_transferred_count: *DWORD,
    lpCompletionKey: *usize,
    lpOverlapped: *?*OVERLAPPED,
    dwMilliseconds: DWORD,
) GetQueuedCompletionStatusResult {
    if (kernel32.GetQueuedCompletionStatus(
        completion_port,
        bytes_transferred_count,
        lpCompletionKey,
        lpOverlapped,
        dwMilliseconds,
    ) == FALSE) {
        switch (kernel32.GetLastError()) {
            .ABANDONED_WAIT_0 => return GetQueuedCompletionStatusResult.Aborted,
            .OPERATION_ABORTED => return GetQueuedCompletionStatusResult.Cancelled,
            .HANDLE_EOF => return GetQueuedCompletionStatusResult.EOF,
            else => |err| {
                if (std.debug.runtime_safety) {
                    std.debug.panic("unexpected error: {}\n", .{err});
                }
            },
        }
    }
    return GetQueuedCompletionStatusResult.Normal;
}

pub fn CloseHandle(hObject: HANDLE) void {
    assert(ntdll.NtClose(hObject) == .SUCCESS);
}

pub fn FindClose(hFindFile: HANDLE) void {
    assert(kernel32.FindClose(hFindFile) != 0);
}

pub const ReadFileError = error{
    OperationAborted,
    BrokenPipe,
    Unexpected,
};

/// If buffer's length exceeds what a Windows DWORD integer can hold, it will be broken into
/// multiple non-atomic reads.
pub fn ReadFile(in_hFile: HANDLE, buffer: []u8, offset: ?u64) ReadFileError!usize {
    if (std.event.Loop.instance) |loop| {
        // TODO support async ReadFile with no offset
        const off = offset.?;
        var resume_node = std.event.Loop.ResumeNode.Basic{
            .base = .{
                .id = .Basic,
                .handle = @frame(),
                .overlapped = OVERLAPPED{
                    .Internal = 0,
                    .InternalHigh = 0,
                    .Offset = @truncate(u32, off),
                    .OffsetHigh = @truncate(u32, off >> 32),
                    .hEvent = null,
                },
            },
        };
        // TODO only call create io completion port once per fd
        _ = windows.CreateIoCompletionPort(fd, loop.os_data.io_port, undefined, undefined) catch undefined;
        loop.beginOneEvent();
        suspend {
            // TODO handle buffer bigger than DWORD can hold
            _ = windows.kernel32.ReadFile(fd, buffer.ptr, @intCast(windows.DWORD, buffer.len), null, &resume_node.base.overlapped);
        }
        var bytes_transferred: windows.DWORD = undefined;
        if (windows.kernel32.GetOverlappedResult(fd, &resume_node.base.overlapped, &bytes_transferred, windows.FALSE) == 0) {
            switch (windows.kernel32.GetLastError()) {
                .IO_PENDING => unreachable,
                .OPERATION_ABORTED => return error.OperationAborted,
                .BROKEN_PIPE => return error.BrokenPipe,
                .HANDLE_EOF => return @as(usize, bytes_transferred),
                else => |err| return windows.unexpectedError(err),
            }
        }
        return @as(usize, bytes_transferred);
    } else {
        var index: usize = 0;
        while (index < buffer.len) {
            const want_read_count = @intCast(DWORD, math.min(@as(DWORD, maxInt(DWORD)), buffer.len - index));
            var amt_read: DWORD = undefined;
            var overlapped_data: OVERLAPPED = undefined;
            const overlapped: ?*OVERLAPPED = if (offset) |off| blk: {
                overlapped_data = .{
                    .Internal = 0,
                    .InternalHigh = 0,
                    .Offset = @truncate(u32, off + index),
                    .OffsetHigh = @truncate(u32, (off + index) >> 32),
                    .hEvent = null,
                };
                break :blk &overlapped_data;
            } else null;
            if (kernel32.ReadFile(in_hFile, buffer.ptr + index, want_read_count, &amt_read, overlapped) == 0) {
                switch (kernel32.GetLastError()) {
                    .OPERATION_ABORTED => continue,
                    .BROKEN_PIPE => return index,
                    else => |err| return unexpectedError(err),
                }
            }
            if (amt_read == 0) return index;
            index += amt_read;
        }
        return index;
    }
}

pub const WriteFileError = error{
    SystemResources,
    OperationAborted,
    BrokenPipe,
    Unexpected,
};

pub fn WriteFile(handle: HANDLE, bytes: []const u8, offset: ?u64) WriteFileError!usize {
    if (std.event.Loop.instance) |loop| {
        // TODO support async WriteFile with no offset
        const off = offset.?;
        var resume_node = std.event.Loop.ResumeNode.Basic{
            .base = .{
                .id = .Basic,
                .handle = @frame(),
                .overlapped = OVERLAPPED{
                    .Internal = 0,
                    .InternalHigh = 0,
                    .Offset = @truncate(u32, off),
                    .OffsetHigh = @truncate(u32, off >> 32),
                    .hEvent = null,
                },
            },
        };
        // TODO only call create io completion port once per fd
        _ = CreateIoCompletionPort(fd, loop.os_data.io_port, undefined, undefined);
        loop.beginOneEvent();
        suspend {
            const adjusted_len = math.cast(windows.DWORD, bytes.len) catch maxInt(windows.DWORD);
            _ = kernel32.WriteFile(fd, bytes.ptr, adjusted_len, null, &resume_node.base.overlapped);
        }
        var bytes_transferred: windows.DWORD = undefined;
        if (kernel32.GetOverlappedResult(fd, &resume_node.base.overlapped, &bytes_transferred, FALSE) == 0) {
            switch (kernel32.GetLastError()) {
                .IO_PENDING => unreachable,
                .INVALID_USER_BUFFER => return error.SystemResources,
                .NOT_ENOUGH_MEMORY => return error.SystemResources,
                .OPERATION_ABORTED => return error.OperationAborted,
                .NOT_ENOUGH_QUOTA => return error.SystemResources,
                .BROKEN_PIPE => return error.BrokenPipe,
                else => |err| return windows.unexpectedError(err),
            }
        }
        return bytes_transferred;
    } else {
        var bytes_written: DWORD = undefined;
        var overlapped_data: OVERLAPPED = undefined;
        const overlapped: ?*OVERLAPPED = if (offset) |off| blk: {
            overlapped_data = .{
                .Internal = 0,
                .InternalHigh = 0,
                .Offset = @truncate(u32, off),
                .OffsetHigh = @truncate(u32, off >> 32),
                .hEvent = null,
            };
            break :blk &overlapped_data;
        } else null;
        const adjusted_len = math.cast(u32, bytes.len) catch maxInt(u32);
        if (kernel32.WriteFile(handle, bytes.ptr, adjusted_len, &bytes_written, overlapped) == 0) {
            switch (kernel32.GetLastError()) {
                .INVALID_USER_BUFFER => return error.SystemResources,
                .NOT_ENOUGH_MEMORY => return error.SystemResources,
                .OPERATION_ABORTED => return error.OperationAborted,
                .NOT_ENOUGH_QUOTA => return error.SystemResources,
                .IO_PENDING => unreachable,
                .BROKEN_PIPE => return error.BrokenPipe,
                else => |err| return unexpectedError(err),
            }
        }
        return bytes_written;
    }
}

pub const GetCurrentDirectoryError = error{
    NameTooLong,
    Unexpected,
};

/// The result is a slice of `buffer`, indexed from 0.
pub fn GetCurrentDirectory(buffer: []u8) GetCurrentDirectoryError![]u8 {
    var utf16le_buf: [PATH_MAX_WIDE]u16 = undefined;
    const result = kernel32.GetCurrentDirectoryW(utf16le_buf.len, &utf16le_buf);
    if (result == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
    assert(result <= utf16le_buf.len);
    const utf16le_slice = utf16le_buf[0..result];
    // Trust that Windows gives us valid UTF-16LE.
    var end_index: usize = 0;
    var it = std.unicode.Utf16LeIterator.init(utf16le_slice);
    while (it.nextCodepoint() catch unreachable) |codepoint| {
        const seq_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
        if (end_index + seq_len >= buffer.len)
            return error.NameTooLong;
        end_index += std.unicode.utf8Encode(codepoint, buffer[end_index..]) catch unreachable;
    }
    return buffer[0..end_index];
}

pub const CreateSymbolicLinkError = error{Unexpected};

pub fn CreateSymbolicLink(
    sym_link_path: []const u8,
    target_path: []const u8,
    flags: DWORD,
) CreateSymbolicLinkError!void {
    const sym_link_path_w = try sliceToPrefixedFileW(sym_link_path);
    const target_path_w = try sliceToPrefixedFileW(target_path);
    return CreateSymbolicLinkW(&sym_link_path_w, &target_path_w, flags);
}

pub fn CreateSymbolicLinkW(
    sym_link_path: [*:0]const u16,
    target_path: [*:0]const u16,
    flags: DWORD,
) CreateSymbolicLinkError!void {
    if (kernel32.CreateSymbolicLinkW(sym_link_path, target_path, flags) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub const DeleteFileError = error{
    FileNotFound,
    AccessDenied,
    NameTooLong,
    FileBusy,
    Unexpected,
};

pub fn DeleteFile(filename: []const u8) DeleteFileError!void {
    const filename_w = try sliceToPrefixedFileW(filename);
    return DeleteFileW(&filename_w);
}

pub fn DeleteFileW(filename: [*:0]const u16) DeleteFileError!void {
    if (kernel32.DeleteFileW(filename) == 0) {
        switch (kernel32.GetLastError()) {
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            .ACCESS_DENIED => return error.AccessDenied,
            .FILENAME_EXCED_RANGE => return error.NameTooLong,
            .INVALID_PARAMETER => return error.NameTooLong,
            .SHARING_VIOLATION => return error.FileBusy,
            else => |err| return unexpectedError(err),
        }
    }
}

pub const MoveFileError = error{Unexpected};

pub fn MoveFileEx(old_path: []const u8, new_path: []const u8, flags: DWORD) MoveFileError!void {
    const old_path_w = try sliceToPrefixedFileW(old_path);
    const new_path_w = try sliceToPrefixedFileW(new_path);
    return MoveFileExW(&old_path_w, &new_path_w, flags);
}

pub fn MoveFileExW(old_path: [*:0]const u16, new_path: [*:0]const u16, flags: DWORD) MoveFileError!void {
    if (kernel32.MoveFileExW(old_path, new_path, flags) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub const CreateDirectoryError = error{
    NameTooLong,
    PathAlreadyExists,
    FileNotFound,
    NoDevice,
    AccessDenied,
    Unexpected,
};

/// Returns an open directory handle which the caller is responsible for closing with `CloseHandle`.
pub fn CreateDirectory(dir: ?HANDLE, pathname: []const u8, sa: ?*SECURITY_ATTRIBUTES) CreateDirectoryError!HANDLE {
    const pathname_w = try sliceToPrefixedFileW(pathname);
    return CreateDirectoryW(dir, &pathname_w, sa);
}

/// Same as `CreateDirectory` except takes a WTF-16 encoded path.
pub fn CreateDirectoryW(
    dir: ?HANDLE,
    sub_path_w: [*:0]const u16,
    sa: ?*SECURITY_ATTRIBUTES,
) CreateDirectoryError!HANDLE {
    const path_len_bytes = math.cast(u16, mem.toSliceConst(u16, sub_path_w).len * 2) catch |err| switch (err) {
        error.Overflow => return error.NameTooLong,
    };
    var nt_name = UNICODE_STRING{
        .Length = path_len_bytes,
        .MaximumLength = path_len_bytes,
        .Buffer = @intToPtr([*]u16, @ptrToInt(sub_path_w)),
    };

    if (sub_path_w[0] == '.' and sub_path_w[1] == 0) {
        // Windows does not recognize this, but it does work with empty string.
        nt_name.Length = 0;
    }

    var attr = OBJECT_ATTRIBUTES{
        .Length = @sizeOf(OBJECT_ATTRIBUTES),
        .RootDirectory = if (std.fs.path.isAbsoluteWindowsW(sub_path_w)) null else dir,
        .Attributes = 0, // Note we do not use OBJ_CASE_INSENSITIVE here.
        .ObjectName = &nt_name,
        .SecurityDescriptor = if (sa) |ptr| ptr.lpSecurityDescriptor else null,
        .SecurityQualityOfService = null,
    };
    var io: IO_STATUS_BLOCK = undefined;
    var result_handle: HANDLE = undefined;
    const rc = ntdll.NtCreateFile(
        &result_handle,
        GENERIC_READ | SYNCHRONIZE,
        &attr,
        &io,
        null,
        FILE_ATTRIBUTE_NORMAL,
        FILE_SHARE_READ,
        FILE_CREATE,
        FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT,
        null,
        0,
    );
    switch (rc) {
        .SUCCESS => return result_handle,
        .OBJECT_NAME_INVALID => unreachable,
        .OBJECT_NAME_NOT_FOUND => return error.FileNotFound,
        .OBJECT_PATH_NOT_FOUND => return error.FileNotFound,
        .NO_MEDIA_IN_DEVICE => return error.NoDevice,
        .INVALID_PARAMETER => unreachable,
        .ACCESS_DENIED => return error.AccessDenied,
        .OBJECT_PATH_SYNTAX_BAD => unreachable,
        .OBJECT_NAME_COLLISION => return error.PathAlreadyExists,
        else => return unexpectedStatus(rc),
    }
}

pub const RemoveDirectoryError = error{
    FileNotFound,
    DirNotEmpty,
    Unexpected,
};

pub fn RemoveDirectory(dir_path: []const u8) RemoveDirectoryError!void {
    const dir_path_w = try sliceToPrefixedFileW(dir_path);
    return RemoveDirectoryW(&dir_path_w);
}

pub fn RemoveDirectoryW(dir_path_w: [*:0]const u16) RemoveDirectoryError!void {
    if (kernel32.RemoveDirectoryW(dir_path_w) == 0) {
        switch (kernel32.GetLastError()) {
            .PATH_NOT_FOUND => return error.FileNotFound,
            .DIR_NOT_EMPTY => return error.DirNotEmpty,
            else => |err| return unexpectedError(err),
        }
    }
}

pub const GetStdHandleError = error{
    NoStandardHandleAttached,
    Unexpected,
};

pub fn GetStdHandle(handle_id: DWORD) GetStdHandleError!HANDLE {
    const handle = kernel32.GetStdHandle(handle_id) orelse return error.NoStandardHandleAttached;
    if (handle == INVALID_HANDLE_VALUE) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
    return handle;
}

pub const SetFilePointerError = error{Unexpected};

/// The SetFilePointerEx function with the `dwMoveMethod` parameter set to `FILE_BEGIN`.
pub fn SetFilePointerEx_BEGIN(handle: HANDLE, offset: u64) SetFilePointerError!void {
    // "The starting point is zero or the beginning of the file. If [FILE_BEGIN]
    // is specified, then the liDistanceToMove parameter is interpreted as an unsigned value."
    // https://docs.microsoft.com/en-us/windows/desktop/api/fileapi/nf-fileapi-setfilepointerex
    const ipos = @bitCast(LARGE_INTEGER, offset);
    if (kernel32.SetFilePointerEx(handle, ipos, null, FILE_BEGIN) == 0) {
        switch (kernel32.GetLastError()) {
            .INVALID_PARAMETER => unreachable,
            .INVALID_HANDLE => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
}

/// The SetFilePointerEx function with the `dwMoveMethod` parameter set to `FILE_CURRENT`.
pub fn SetFilePointerEx_CURRENT(handle: HANDLE, offset: i64) SetFilePointerError!void {
    if (kernel32.SetFilePointerEx(handle, offset, null, FILE_CURRENT) == 0) {
        switch (kernel32.GetLastError()) {
            .INVALID_PARAMETER => unreachable,
            .INVALID_HANDLE => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
}

/// The SetFilePointerEx function with the `dwMoveMethod` parameter set to `FILE_END`.
pub fn SetFilePointerEx_END(handle: HANDLE, offset: i64) SetFilePointerError!void {
    if (kernel32.SetFilePointerEx(handle, offset, null, FILE_END) == 0) {
        switch (kernel32.GetLastError()) {
            .INVALID_PARAMETER => unreachable,
            .INVALID_HANDLE => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
}

/// The SetFilePointerEx function with parameters to get the current offset.
pub fn SetFilePointerEx_CURRENT_get(handle: HANDLE) SetFilePointerError!u64 {
    var result: LARGE_INTEGER = undefined;
    if (kernel32.SetFilePointerEx(handle, 0, &result, FILE_CURRENT) == 0) {
        switch (kernel32.GetLastError()) {
            .INVALID_PARAMETER => unreachable,
            .INVALID_HANDLE => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
    // Based on the docs for FILE_BEGIN, it seems that the returned signed integer
    // should be interpreted as an unsigned integer.
    return @bitCast(u64, result);
}

pub const GetFinalPathNameByHandleError = error{
    FileNotFound,
    SystemResources,
    NameTooLong,
    Unexpected,
};

pub fn GetFinalPathNameByHandleW(
    hFile: HANDLE,
    buf_ptr: [*]u16,
    buf_len: DWORD,
    flags: DWORD,
) GetFinalPathNameByHandleError![:0]u16 {
    const rc = kernel32.GetFinalPathNameByHandleW(hFile, buf_ptr, buf_len, flags);
    if (rc == 0) {
        switch (kernel32.GetLastError()) {
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            .NOT_ENOUGH_MEMORY => return error.SystemResources,
            .FILENAME_EXCED_RANGE => return error.NameTooLong,
            .INVALID_PARAMETER => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
    return buf_ptr[0..rc :0];
}

pub const GetFileSizeError = error{Unexpected};

pub fn GetFileSizeEx(hFile: HANDLE) GetFileSizeError!u64 {
    var file_size: LARGE_INTEGER = undefined;
    if (kernel32.GetFileSizeEx(hFile, &file_size) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
    return @bitCast(u64, file_size);
}

pub const GetFileAttributesError = error{
    FileNotFound,
    PermissionDenied,
    Unexpected,
};

pub fn GetFileAttributes(filename: []const u8) GetFileAttributesError!DWORD {
    const filename_w = try sliceToPrefixedFileW(filename);
    return GetFileAttributesW(&filename_w);
}

pub fn GetFileAttributesW(lpFileName: [*:0]const u16) GetFileAttributesError!DWORD {
    const rc = kernel32.GetFileAttributesW(lpFileName);
    if (rc == INVALID_FILE_ATTRIBUTES) {
        switch (kernel32.GetLastError()) {
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            .ACCESS_DENIED => return error.PermissionDenied,
            else => |err| return unexpectedError(err),
        }
    }
    return rc;
}

pub fn WSAStartup(majorVersion: u8, minorVersion: u8) !ws2_32.WSADATA {
    var wsadata: ws2_32.WSADATA = undefined;
    return switch (ws2_32.WSAStartup((@as(WORD, minorVersion) << 8) | majorVersion, &wsadata)) {
        0 => wsadata,
        else => |err| unexpectedWSAError(@intToEnum(WinsockError, err)),
    };
}

pub fn WSACleanup() !void {
    return switch (ws2_32.WSACleanup()) {
        0 => {},
        ws2_32.SOCKET_ERROR => switch (ws2_32.WSAGetLastError()) {
            else => |err| return unexpectedWSAError(err),
        },
        else => unreachable,
    };
}

pub fn WSASocketW(
    af: i32,
    socket_type: i32,
    protocol: i32,
    protocolInfo: ?*ws2_32.WSAPROTOCOL_INFOW,
    g: ws2_32.GROUP,
    dwFlags: DWORD,
) !ws2_32.SOCKET {
    const rc = ws2_32.WSASocketW(af, socket_type, protocol, protocolInfo, g, dwFlags);
    if (rc == ws2_32.INVALID_SOCKET) {
        switch (ws2_32.WSAGetLastError()) {
            .WSAEAFNOSUPPORT => return error.AddressFamilyNotSupported,
            .WSAEMFILE => return error.ProcessFdQuotaExceeded,
            .WSAENOBUFS => return error.SystemResources,
            .WSAEPROTONOSUPPORT => return error.ProtocolNotSupported,
            else => |err| return unexpectedWSAError(err),
        }
    }
    return rc;
}

pub fn closesocket(s: ws2_32.SOCKET) !void {
    switch (ws2_32.closesocket(s)) {
        0 => {},
        ws2_32.SOCKET_ERROR => switch (ws2_32.WSAGetLastError()) {
            else => |err| return unexpectedWSAError(err),
        },
        else => unreachable,
    }
}

pub fn WSAIoctl(
    s: ws2_32.SOCKET,
    dwIoControlCode: DWORD,
    inBuffer: ?[]const u8,
    outBuffer: []u8,
    overlapped: ?*ws2_32.WSAOVERLAPPED,
    completionRoutine: ?ws2_32.WSAOVERLAPPED_COMPLETION_ROUTINE,
) !DWORD {
    var bytes: DWORD = undefined;
    switch (ws2_32.WSAIoctl(
        s,
        dwIoControlCode,
        if (inBuffer) |i| i.ptr else null,
        if (inBuffer) |i| @intCast(DWORD, i.len) else 0,
        outBuffer.ptr,
        @intCast(DWORD, outBuffer.len),
        &bytes,
        overlapped,
        completionRoutine,
    )) {
        0 => {},
        ws2_32.SOCKET_ERROR => switch (ws2_32.WSAGetLastError()) {
            else => |err| return unexpectedWSAError(err),
        },
        else => unreachable,
    }
    return bytes;
}

const GetModuleFileNameError = error{Unexpected};

pub fn GetModuleFileNameW(hModule: ?HMODULE, buf_ptr: [*]u16, buf_len: DWORD) GetModuleFileNameError![:0]u16 {
    const rc = kernel32.GetModuleFileNameW(hModule, buf_ptr, buf_len);
    if (rc == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
    return buf_ptr[0..rc :0];
}

pub const TerminateProcessError = error{Unexpected};

pub fn TerminateProcess(hProcess: HANDLE, uExitCode: UINT) TerminateProcessError!void {
    if (kernel32.TerminateProcess(hProcess, uExitCode) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub const VirtualAllocError = error{Unexpected};

pub fn VirtualAlloc(addr: ?LPVOID, size: usize, alloc_type: DWORD, flProtect: DWORD) VirtualAllocError!LPVOID {
    return kernel32.VirtualAlloc(addr, size, alloc_type, flProtect) orelse {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    };
}

pub fn VirtualFree(lpAddress: ?LPVOID, dwSize: usize, dwFreeType: DWORD) void {
    assert(kernel32.VirtualFree(lpAddress, dwSize, dwFreeType) != 0);
}

pub const SetConsoleTextAttributeError = error{Unexpected};

pub fn SetConsoleTextAttribute(hConsoleOutput: HANDLE, wAttributes: WORD) SetConsoleTextAttributeError!void {
    if (kernel32.SetConsoleTextAttribute(hConsoleOutput, wAttributes) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub const GetEnvironmentStringsError = error{OutOfMemory};

pub fn GetEnvironmentStringsW() GetEnvironmentStringsError![*:0]u16 {
    return kernel32.GetEnvironmentStringsW() orelse return error.OutOfMemory;
}

pub fn FreeEnvironmentStringsW(penv: [*:0]u16) void {
    assert(kernel32.FreeEnvironmentStringsW(penv) != 0);
}

pub const GetEnvironmentVariableError = error{
    EnvironmentVariableNotFound,
    Unexpected,
};

pub fn GetEnvironmentVariableW(lpName: LPWSTR, lpBuffer: [*]u16, nSize: DWORD) GetEnvironmentVariableError!DWORD {
    const rc = kernel32.GetEnvironmentVariableW(lpName, lpBuffer, nSize);
    if (rc == 0) {
        switch (kernel32.GetLastError()) {
            .ENVVAR_NOT_FOUND => return error.EnvironmentVariableNotFound,
            else => |err| return unexpectedError(err),
        }
    }
    return rc;
}

pub const CreateProcessError = error{
    FileNotFound,
    AccessDenied,
    InvalidName,
    Unexpected,
};

pub fn CreateProcessW(
    lpApplicationName: ?LPWSTR,
    lpCommandLine: LPWSTR,
    lpProcessAttributes: ?*SECURITY_ATTRIBUTES,
    lpThreadAttributes: ?*SECURITY_ATTRIBUTES,
    bInheritHandles: BOOL,
    dwCreationFlags: DWORD,
    lpEnvironment: ?*c_void,
    lpCurrentDirectory: ?LPWSTR,
    lpStartupInfo: *STARTUPINFOW,
    lpProcessInformation: *PROCESS_INFORMATION,
) CreateProcessError!void {
    if (kernel32.CreateProcessW(
        lpApplicationName,
        lpCommandLine,
        lpProcessAttributes,
        lpThreadAttributes,
        bInheritHandles,
        dwCreationFlags,
        lpEnvironment,
        lpCurrentDirectory,
        lpStartupInfo,
        lpProcessInformation,
    ) == 0) {
        switch (kernel32.GetLastError()) {
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            .ACCESS_DENIED => return error.AccessDenied,
            .INVALID_PARAMETER => unreachable,
            .INVALID_NAME => return error.InvalidName,
            else => |err| return unexpectedError(err),
        }
    }
}

pub const LoadLibraryError = error{
    FileNotFound,
    Unexpected,
};

pub fn LoadLibraryW(lpLibFileName: [*:0]const u16) LoadLibraryError!HMODULE {
    return kernel32.LoadLibraryW(lpLibFileName) orelse {
        switch (kernel32.GetLastError()) {
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            .MOD_NOT_FOUND => return error.FileNotFound,
            else => |err| return unexpectedError(err),
        }
    };
}

pub fn FreeLibrary(hModule: HMODULE) void {
    assert(kernel32.FreeLibrary(hModule) != 0);
}

pub fn QueryPerformanceFrequency() u64 {
    // "On systems that run Windows XP or later, the function will always succeed"
    // https://docs.microsoft.com/en-us/windows/desktop/api/profileapi/nf-profileapi-queryperformancefrequency
    var result: LARGE_INTEGER = undefined;
    assert(kernel32.QueryPerformanceFrequency(&result) != 0);
    // The kernel treats this integer as unsigned.
    return @bitCast(u64, result);
}

pub fn QueryPerformanceCounter() u64 {
    // "On systems that run Windows XP or later, the function will always succeed"
    // https://docs.microsoft.com/en-us/windows/desktop/api/profileapi/nf-profileapi-queryperformancecounter
    var result: LARGE_INTEGER = undefined;
    assert(kernel32.QueryPerformanceCounter(&result) != 0);
    // The kernel treats this integer as unsigned.
    return @bitCast(u64, result);
}

pub fn InitOnceExecuteOnce(InitOnce: *INIT_ONCE, InitFn: INIT_ONCE_FN, Parameter: ?*c_void, Context: ?*c_void) void {
    assert(kernel32.InitOnceExecuteOnce(InitOnce, InitFn, Parameter, Context) != 0);
}

pub fn HeapFree(hHeap: HANDLE, dwFlags: DWORD, lpMem: *c_void) void {
    assert(kernel32.HeapFree(hHeap, dwFlags, lpMem) != 0);
}

pub fn HeapDestroy(hHeap: HANDLE) void {
    assert(kernel32.HeapDestroy(hHeap) != 0);
}

pub const GetFileInformationByHandleError = error{Unexpected};

pub fn GetFileInformationByHandle(
    hFile: HANDLE,
) GetFileInformationByHandleError!BY_HANDLE_FILE_INFORMATION {
    var info: BY_HANDLE_FILE_INFORMATION = undefined;
    const rc = ntdll.GetFileInformationByHandle(hFile, &info);
    if (rc == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
    return info;
}

pub const SetFileTimeError = error{Unexpected};

pub fn SetFileTime(
    hFile: HANDLE,
    lpCreationTime: ?*const FILETIME,
    lpLastAccessTime: ?*const FILETIME,
    lpLastWriteTime: ?*const FILETIME,
) SetFileTimeError!void {
    const rc = kernel32.SetFileTime(hFile, lpCreationTime, lpLastAccessTime, lpLastWriteTime);
    if (rc == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub fn teb() *TEB {
    return switch (builtin.arch) {
        .i386 => asm volatile (
            \\ movl %%fs:0x18, %[ptr]
            : [ptr] "=r" (-> *TEB)
        ),
        .x86_64 => asm volatile (
            \\ movq %%gs:0x30, %[ptr]
            : [ptr] "=r" (-> *TEB)
        ),
        .aarch64 => asm volatile (
            \\ mov %[ptr], x18
            : [ptr] "=r" (-> *TEB)
        ),
        else => @compileError("unsupported arch"),
    };
}

pub fn peb() *PEB {
    return teb().ProcessEnvironmentBlock;
}

/// A file time is a 64-bit value that represents the number of 100-nanosecond
/// intervals that have elapsed since 12:00 A.M. January 1, 1601 Coordinated
/// Universal Time (UTC).
/// This function returns the number of nanoseconds since the canonical epoch,
/// which is the POSIX one (Jan 01, 1970 AD).
pub fn fromSysTime(hns: i64) i64 {
    const adjusted_epoch = hns + std.time.epoch.windows * (std.time.ns_per_s / 100);
    return adjusted_epoch * 100;
}

pub fn toSysTime(ns: i64) i64 {
    const hns = @divFloor(ns, 100);
    return hns - std.time.epoch.windows * (std.time.ns_per_s / 100);
}

pub fn fileTimeToNanoSeconds(ft: FILETIME) i64 {
    const hns = @bitCast(i64, (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime);
    return fromSysTime(hns);
}

/// Converts a number of nanoseconds since the POSIX epoch to a Windows FILETIME.
pub fn nanoSecondsToFileTime(ns: i64) FILETIME {
    const adjusted = @bitCast(u64, toSysTime(ns));
    return FILETIME{
        .dwHighDateTime = @truncate(u32, adjusted >> 32),
        .dwLowDateTime = @truncate(u32, adjusted),
    };
}

pub fn cStrToPrefixedFileW(s: [*:0]const u8) ![PATH_MAX_WIDE:0]u16 {
    return sliceToPrefixedFileW(mem.toSliceConst(u8, s));
}

pub fn sliceToPrefixedFileW(s: []const u8) ![PATH_MAX_WIDE:0]u16 {
    return sliceToPrefixedSuffixedFileW(s, &[_]u16{});
}

/// Assumes an absolute path.
pub fn wToPrefixedFileW(s: []const u16) ![PATH_MAX_WIDE:0]u16 {
    // TODO https://github.com/ziglang/zig/issues/2765
    var result: [PATH_MAX_WIDE:0]u16 = undefined;

    const start_index = if (mem.startsWith(u16, s, &[_]u16{ '\\', '?' })) 0 else blk: {
        const prefix = [_]u16{ '\\', '?', '?', '\\' };
        mem.copy(u16, result[0..], &prefix);
        break :blk prefix.len;
    };
    const end_index = start_index + s.len;
    if (end_index + 1 > result.len) return error.NameTooLong;
    mem.copy(u16, result[start_index..], s);
    result[end_index] = 0;
    return result;
}

pub fn sliceToPrefixedSuffixedFileW(s: []const u8, comptime suffix: []const u16) ![PATH_MAX_WIDE + suffix.len:0]u16 {
    // TODO https://github.com/ziglang/zig/issues/2765
    var result: [PATH_MAX_WIDE + suffix.len:0]u16 = undefined;
    // > File I/O functions in the Windows API convert "/" to "\" as part of
    // > converting the name to an NT-style name, except when using the "\\?\"
    // > prefix as detailed in the following sections.
    // from https://docs.microsoft.com/en-us/windows/desktop/FileIO/naming-a-file#maximum-path-length-limitation
    // Because we want the larger maximum path length for absolute paths, we
    // disallow forward slashes in zig std lib file functions on Windows.
    for (s) |byte| {
        switch (byte) {
            '/', '*', '?', '"', '<', '>', '|' => return error.BadPathName,
            else => {},
        }
    }
    const start_index = if (mem.startsWith(u8, s, "\\?") or !std.fs.path.isAbsolute(s)) 0 else blk: {
        const prefix = [_]u16{ '\\', '?', '?', '\\' };
        mem.copy(u16, result[0..], &prefix);
        break :blk prefix.len;
    };
    const end_index = start_index + try std.unicode.utf8ToUtf16Le(result[start_index..], s);
    if (end_index + suffix.len > result.len) return error.NameTooLong;
    mem.copy(u16, result[end_index..], suffix);
    result[end_index + suffix.len] = 0;
    return result;
}

inline fn MAKELANGID(p: c_ushort, s: c_ushort) LANGID {
    return (s << 10) | p;
}

/// Call this when you made a windows DLL call or something that does SetLastError
/// and you get an unexpected error.
pub fn unexpectedError(err: Win32Error) std.os.UnexpectedError {
    if (std.os.unexpected_error_tracing) {
        // 614 is the length of the longest windows error desciption
        var buf_u16: [614]u16 = undefined;
        var buf_u8: [614]u8 = undefined;
        var len = kernel32.FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, err, MAKELANGID(LANG.NEUTRAL, SUBLANG.DEFAULT), buf_u16[0..].ptr, buf_u16.len / @sizeOf(TCHAR), null);
        _ = std.unicode.utf16leToUtf8(&buf_u8, buf_u16[0..len]) catch unreachable;
        std.debug.warn("error.Unexpected: GetLastError({}): {}\n", .{ @enumToInt(err), buf_u8[0..len] });
        std.debug.dumpCurrentStackTrace(null);
    }
    return error.Unexpected;
}

pub fn unexpectedWSAError(err: WinsockError) std.os.UnexpectedError {
    return unexpectedError(@intToEnum(Win32Error, @enumToInt(err)));
}

/// Call this when you made a windows NtDll call
/// and you get an unexpected status.
pub fn unexpectedStatus(status: NTSTATUS) std.os.UnexpectedError {
    if (std.os.unexpected_error_tracing) {
        std.debug.warn("error.Unexpected NTSTATUS=0x{x}\n", .{@enumToInt(status)});
        std.debug.dumpCurrentStackTrace(null);
    }
    return error.Unexpected;
}

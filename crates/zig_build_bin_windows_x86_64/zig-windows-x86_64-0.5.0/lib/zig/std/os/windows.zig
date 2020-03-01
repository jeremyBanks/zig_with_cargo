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

pub const is_the_target = builtin.os == .windows;
pub const advapi32 = @import("windows/advapi32.zig");
pub const kernel32 = @import("windows/kernel32.zig");
pub const ntdll = @import("windows/ntdll.zig");
pub const ole32 = @import("windows/ole32.zig");
pub const shell32 = @import("windows/shell32.zig");

pub usingnamespace @import("windows/bits.zig");

/// `builtin` is missing `subsystem` when the subsystem is automatically detected,
/// so Zig standard library has the subsystem detection logic here. This should generally be
/// used rather than `builtin.subsystem`.
/// On non-windows targets, this is `null`.
pub const subsystem: ?builtin.SubSystem = blk: {
    if (@hasDecl(builtin, "subsystem")) break :blk builtin.subsystem;
    switch (builtin.os) {
        .windows => {
            if (builtin.is_test) {
                break :blk builtin.SubSystem.Console;
            }
            const root = @import("root");
            if (@hasDecl(root, "WinMain") or
                @hasDecl(root, "wWinMain") or
                @hasDecl(root, "WinMainCRTStartup") or
                @hasDecl(root, "wWinMainCRTStartup"))
            {
                break :blk builtin.SubSystem.Windows;
            } else {
                break :blk builtin.SubSystem.Console;
            }
        },
        .uefi => break :blk builtin.SubSystem.EfiApplication,
        else => break :blk null,
    }
};

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
    file_path_w: [*]const u16,
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
            ERROR.SHARING_VIOLATION => return error.SharingViolation,
            ERROR.ALREADY_EXISTS => return error.PathAlreadyExists,
            ERROR.FILE_EXISTS => return error.PathAlreadyExists,
            ERROR.FILE_NOT_FOUND => return error.FileNotFound,
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
            ERROR.ACCESS_DENIED => return error.AccessDenied,
            ERROR.PIPE_BUSY => return error.PipeBusy,
            ERROR.FILENAME_EXCED_RANGE => return error.NameTooLong,
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
    switch (kernel32.WaitForSingleObject(handle, milliseconds)) {
        WAIT_ABANDONED => return error.WaitAbandoned,
        WAIT_OBJECT_0 => return,
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
    const dir_path_w = try sliceToPrefixedSuffixedFileW(dir_path, [_]u16{ '\\', '*', 0 });
    const handle = kernel32.FindFirstFileW(&dir_path_w, find_file_data);

    if (handle == INVALID_HANDLE_VALUE) {
        switch (kernel32.GetLastError()) {
            ERROR.FILE_NOT_FOUND => return error.FileNotFound,
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
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
            ERROR.NO_MORE_FILES => return false,
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
            ERROR.INVALID_PARAMETER => unreachable,
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
            ERROR.ABANDONED_WAIT_0 => return GetQueuedCompletionStatusResult.Aborted,
            ERROR.OPERATION_ABORTED => return GetQueuedCompletionStatusResult.Cancelled,
            ERROR.HANDLE_EOF => return GetQueuedCompletionStatusResult.EOF,
            else => |err| {
                if (std.debug.runtime_safety) {
                    std.debug.panic("unexpected error: {}\n", err);
                }
            },
        }
    }
    return GetQueuedCompletionStatusResult.Normal;
}

pub fn CloseHandle(hObject: HANDLE) void {
    assert(kernel32.CloseHandle(hObject) != 0);
}

pub fn FindClose(hFindFile: HANDLE) void {
    assert(kernel32.FindClose(hFindFile) != 0);
}

pub const ReadFileError = error{Unexpected};

pub fn ReadFile(in_hFile: HANDLE, buffer: []u8) ReadFileError!usize {
    var index: usize = 0;
    while (index < buffer.len) {
        const want_read_count = @intCast(DWORD, math.min(DWORD(maxInt(DWORD)), buffer.len - index));
        var amt_read: DWORD = undefined;
        if (kernel32.ReadFile(in_hFile, buffer.ptr + index, want_read_count, &amt_read, null) == 0) {
            switch (kernel32.GetLastError()) {
                ERROR.OPERATION_ABORTED => continue,
                ERROR.BROKEN_PIPE => return index,
                else => |err| return unexpectedError(err),
            }
        }
        if (amt_read == 0) return index;
        index += amt_read;
    }
    return index;
}

pub const WriteFileError = error{
    SystemResources,
    OperationAborted,
    BrokenPipe,
    Unexpected,
};

/// This function is for blocking file descriptors only. For non-blocking, see
/// `WriteFileAsync`.
pub fn WriteFile(handle: HANDLE, bytes: []const u8) WriteFileError!void {
    var bytes_written: DWORD = undefined;
    // TODO replace this @intCast with a loop that writes all the bytes
    if (kernel32.WriteFile(handle, bytes.ptr, @intCast(u32, bytes.len), &bytes_written, null) == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.INVALID_USER_BUFFER => return error.SystemResources,
            ERROR.NOT_ENOUGH_MEMORY => return error.SystemResources,
            ERROR.OPERATION_ABORTED => return error.OperationAborted,
            ERROR.NOT_ENOUGH_QUOTA => return error.SystemResources,
            ERROR.IO_PENDING => unreachable, // this function is for blocking files only
            ERROR.BROKEN_PIPE => return error.BrokenPipe,
            else => |err| return unexpectedError(err),
        }
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
    sym_link_path: [*]const u16,
    target_path: [*]const u16,
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

pub fn DeleteFileW(filename: [*]const u16) DeleteFileError!void {
    if (kernel32.DeleteFileW(filename) == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.FILE_NOT_FOUND => return error.FileNotFound,
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
            ERROR.ACCESS_DENIED => return error.AccessDenied,
            ERROR.FILENAME_EXCED_RANGE => return error.NameTooLong,
            ERROR.INVALID_PARAMETER => return error.NameTooLong,
            ERROR.SHARING_VIOLATION => return error.FileBusy,
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

pub fn MoveFileExW(old_path: [*]const u16, new_path: [*]const u16, flags: DWORD) MoveFileError!void {
    if (kernel32.MoveFileExW(old_path, new_path, flags) == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
}

pub const CreateDirectoryError = error{
    PathAlreadyExists,
    FileNotFound,
    Unexpected,
};

pub fn CreateDirectory(pathname: []const u8, attrs: ?*SECURITY_ATTRIBUTES) CreateDirectoryError!void {
    const pathname_w = try sliceToPrefixedFileW(pathname);
    return CreateDirectoryW(&pathname_w, attrs);
}

pub fn CreateDirectoryW(pathname: [*]const u16, attrs: ?*SECURITY_ATTRIBUTES) CreateDirectoryError!void {
    if (kernel32.CreateDirectoryW(pathname, attrs) == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.ALREADY_EXISTS => return error.PathAlreadyExists,
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
            else => |err| return unexpectedError(err),
        }
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

pub fn RemoveDirectoryW(dir_path_w: [*]const u16) RemoveDirectoryError!void {
    if (kernel32.RemoveDirectoryW(dir_path_w) == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
            ERROR.DIR_NOT_EMPTY => return error.DirNotEmpty,
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
            ERROR.INVALID_PARAMETER => unreachable,
            ERROR.INVALID_HANDLE => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
}

/// The SetFilePointerEx function with the `dwMoveMethod` parameter set to `FILE_CURRENT`.
pub fn SetFilePointerEx_CURRENT(handle: HANDLE, offset: i64) SetFilePointerError!void {
    if (kernel32.SetFilePointerEx(handle, offset, null, FILE_CURRENT) == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.INVALID_PARAMETER => unreachable,
            ERROR.INVALID_HANDLE => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
}

/// The SetFilePointerEx function with the `dwMoveMethod` parameter set to `FILE_END`.
pub fn SetFilePointerEx_END(handle: HANDLE, offset: i64) SetFilePointerError!void {
    if (kernel32.SetFilePointerEx(handle, offset, null, FILE_END) == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.INVALID_PARAMETER => unreachable,
            ERROR.INVALID_HANDLE => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
}

/// The SetFilePointerEx function with parameters to get the current offset.
pub fn SetFilePointerEx_CURRENT_get(handle: HANDLE) SetFilePointerError!u64 {
    var result: LARGE_INTEGER = undefined;
    if (kernel32.SetFilePointerEx(handle, 0, &result, FILE_CURRENT) == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.INVALID_PARAMETER => unreachable,
            ERROR.INVALID_HANDLE => unreachable,
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
) GetFinalPathNameByHandleError!DWORD {
    const rc = kernel32.GetFinalPathNameByHandleW(hFile, buf_ptr, buf_len, flags);
    if (rc == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.FILE_NOT_FOUND => return error.FileNotFound,
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
            ERROR.NOT_ENOUGH_MEMORY => return error.SystemResources,
            ERROR.FILENAME_EXCED_RANGE => return error.NameTooLong,
            ERROR.INVALID_PARAMETER => unreachable,
            else => |err| return unexpectedError(err),
        }
    }
    return rc;
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

pub fn GetFileAttributesW(lpFileName: [*]const u16) GetFileAttributesError!DWORD {
    const rc = kernel32.GetFileAttributesW(lpFileName);
    if (rc == INVALID_FILE_ATTRIBUTES) {
        switch (kernel32.GetLastError()) {
            ERROR.FILE_NOT_FOUND => return error.FileNotFound,
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
            ERROR.ACCESS_DENIED => return error.PermissionDenied,
            else => |err| return unexpectedError(err),
        }
    }
    return rc;
}

const GetModuleFileNameError = error{Unexpected};

pub fn GetModuleFileNameW(hModule: ?HMODULE, buf_ptr: [*]u16, buf_len: DWORD) GetModuleFileNameError![]u16 {
    const rc = kernel32.GetModuleFileNameW(hModule, buf_ptr, buf_len);
    if (rc == 0) {
        switch (kernel32.GetLastError()) {
            else => |err| return unexpectedError(err),
        }
    }
    return buf_ptr[0..rc];
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

pub fn GetEnvironmentStringsW() GetEnvironmentStringsError![*]u16 {
    return kernel32.GetEnvironmentStringsW() orelse return error.OutOfMemory;
}

pub fn FreeEnvironmentStringsW(penv: [*]u16) void {
    assert(kernel32.FreeEnvironmentStringsW(penv) != 0);
}

pub const GetEnvironmentVariableError = error{
    EnvironmentVariableNotFound,
    Unexpected,
};

pub fn GetEnvironmentVariableW(lpName: LPWSTR, lpBuffer: LPWSTR, nSize: DWORD) GetEnvironmentVariableError!DWORD {
    const rc = kernel32.GetEnvironmentVariableW(lpName, lpBuffer, nSize);
    if (rc == 0) {
        switch (kernel32.GetLastError()) {
            ERROR.ENVVAR_NOT_FOUND => return error.EnvironmentVariableNotFound,
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
            ERROR.FILE_NOT_FOUND => return error.FileNotFound,
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
            ERROR.ACCESS_DENIED => return error.AccessDenied,
            ERROR.INVALID_PARAMETER => unreachable,
            ERROR.INVALID_NAME => return error.InvalidName,
            else => |err| return unexpectedError(err),
        }
    }
}

pub const LoadLibraryError = error{
    FileNotFound,
    Unexpected,
};

pub fn LoadLibraryW(lpLibFileName: [*]const u16) LoadLibraryError!HMODULE {
    return kernel32.LoadLibraryW(lpLibFileName) orelse {
        switch (kernel32.GetLastError()) {
            ERROR.FILE_NOT_FOUND => return error.FileNotFound,
            ERROR.PATH_NOT_FOUND => return error.FileNotFound,
            ERROR.MOD_NOT_FOUND => return error.FileNotFound,
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
    const hns = @bitCast(i64, (u64(ft.dwHighDateTime) << 32) | ft.dwLowDateTime);
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

pub fn cStrToPrefixedFileW(s: [*]const u8) ![PATH_MAX_WIDE + 1]u16 {
    return sliceToPrefixedFileW(mem.toSliceConst(u8, s));
}

pub fn sliceToPrefixedFileW(s: []const u8) ![PATH_MAX_WIDE + 1]u16 {
    return sliceToPrefixedSuffixedFileW(s, [_]u16{0});
}

pub fn sliceToPrefixedSuffixedFileW(s: []const u8, comptime suffix: []const u16) ![PATH_MAX_WIDE + suffix.len]u16 {
    // TODO https://github.com/ziglang/zig/issues/2765
    var result: [PATH_MAX_WIDE + suffix.len]u16 = undefined;
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
    const start_index = if (mem.startsWith(u8, s, "\\\\") or !std.fs.path.isAbsolute(s)) 0 else blk: {
        const prefix = [_]u16{ '\\', '\\', '?', '\\' };
        mem.copy(u16, result[0..], prefix);
        break :blk prefix.len;
    };
    const end_index = start_index + try std.unicode.utf8ToUtf16Le(result[start_index..], s);
    assert(end_index <= result.len);
    if (end_index + suffix.len > result.len) return error.NameTooLong;
    mem.copy(u16, result[end_index..], suffix);
    return result;
}

inline fn MAKELANGID(p: c_ushort, s: c_ushort) LANGID {
    return (s << 10) | p;
}

/// Call this when you made a windows DLL call or something that does SetLastError
/// and you get an unexpected error.
pub fn unexpectedError(err: DWORD) std.os.UnexpectedError {
    if (std.os.unexpected_error_tracing) {
        // 614 is the length of the longest windows error desciption
        var buf_u16: [614]u16 = undefined;
        var buf_u8: [614]u8 = undefined;
        var len = kernel32.FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, err, MAKELANGID(LANG.NEUTRAL, SUBLANG.DEFAULT), buf_u16[0..].ptr, buf_u16.len / @sizeOf(TCHAR), null);
        _ = std.unicode.utf16leToUtf8(&buf_u8, buf_u16[0..len]) catch unreachable;
        std.debug.warn("error.Unexpected: GetLastError({}): {}\n", err, buf_u8[0..len]);
        std.debug.dumpCurrentStackTrace(null);
    }
    return error.Unexpected;
}

/// Call this when you made a windows NtDll call
/// and you get an unexpected status.
pub fn unexpectedStatus(status: NTSTATUS) std.os.UnexpectedError {
    if (std.os.unexpected_error_tracing) {
        std.debug.warn("error.Unexpected NTSTATUS={}\n", status);
        std.debug.dumpCurrentStackTrace(null);
    }
    return error.Unexpected;
}

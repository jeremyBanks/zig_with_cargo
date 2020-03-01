// Platform-dependent types and values that are used along with OS-specific APIs.

const builtin = @import("builtin");
const std = @import("../../std.zig");
const assert = std.debug.assert;
const maxInt = std.math.maxInt;

pub const ERROR = @import("error.zig");
pub const STATUS = @import("status.zig");
pub const LANG = @import("lang.zig");
pub const SUBLANG = @import("sublang.zig");

/// The standard input device. Initially, this is the console input buffer, CONIN$.
pub const STD_INPUT_HANDLE = maxInt(DWORD) - 10 + 1;

/// The standard output device. Initially, this is the active console screen buffer, CONOUT$.
pub const STD_OUTPUT_HANDLE = maxInt(DWORD) - 11 + 1;

/// The standard error device. Initially, this is the active console screen buffer, CONOUT$.
pub const STD_ERROR_HANDLE = maxInt(DWORD) - 12 + 1;

pub const SHORT = c_short;
pub const BOOL = c_int;
pub const BOOLEAN = BYTE;
pub const BYTE = u8;
pub const CHAR = u8;
pub const DWORD = u32;
pub const FLOAT = f32;
pub const HANDLE = *c_void;
pub const HCRYPTPROV = ULONG_PTR;
pub const HINSTANCE = *@OpaqueType();
pub const HMODULE = *@OpaqueType();
pub const FARPROC = *@OpaqueType();
pub const INT = c_int;
pub const LPBYTE = *BYTE;
pub const LPCH = *CHAR;
pub const LPCSTR = [*]const CHAR;
pub const LPCTSTR = [*]const TCHAR;
pub const LPCVOID = *const c_void;
pub const LPDWORD = *DWORD;
pub const LPSTR = [*]CHAR;
pub const LPTSTR = if (UNICODE) LPWSTR else LPSTR;
pub const LPVOID = *c_void;
pub const LPWSTR = [*]WCHAR;
pub const LPCWSTR = [*]const WCHAR;
pub const PVOID = *c_void;
pub const PWSTR = [*]WCHAR;
pub const SIZE_T = usize;
pub const TCHAR = if (UNICODE) WCHAR else u8;
pub const UINT = c_uint;
pub const ULONG_PTR = usize;
pub const DWORD_PTR = ULONG_PTR;
pub const UNICODE = false;
pub const WCHAR = u16;
pub const WORD = u16;
pub const LARGE_INTEGER = i64;
pub const ULONG = u32;
pub const LONG = i32;
pub const ULONGLONG = u64;
pub const LONGLONG = i64;
pub const HLOCAL = HANDLE;
pub const LANGID = c_ushort;
pub const NTSTATUS = ULONG;

pub const va_list = *@OpaqueType();

pub const TRUE = 1;
pub const FALSE = 0;

pub const INVALID_HANDLE_VALUE = @intToPtr(HANDLE, maxInt(usize));

pub const INVALID_FILE_ATTRIBUTES = DWORD(maxInt(DWORD));

pub const FILE_ALL_INFORMATION = extern struct {
    BasicInformation: FILE_BASIC_INFORMATION,
    StandardInformation: FILE_STANDARD_INFORMATION,
    InternalInformation: FILE_INTERNAL_INFORMATION,
    EaInformation: FILE_EA_INFORMATION,
    AccessInformation: FILE_ACCESS_INFORMATION,
    PositionInformation: FILE_POSITION_INFORMATION,
    ModeInformation: FILE_MODE_INFORMATION,
    AlignmentInformation: FILE_ALIGNMENT_INFORMATION,
    NameInformation: FILE_NAME_INFORMATION,
};

pub const FILE_BASIC_INFORMATION = extern struct {
    CreationTime: LARGE_INTEGER,
    LastAccessTime: LARGE_INTEGER,
    LastWriteTime: LARGE_INTEGER,
    ChangeTime: LARGE_INTEGER,
    FileAttributes: ULONG,
};

pub const FILE_STANDARD_INFORMATION = extern struct {
    AllocationSize: LARGE_INTEGER,
    EndOfFile: LARGE_INTEGER,
    NumberOfLinks: ULONG,
    DeletePending: BOOLEAN,
    Directory: BOOLEAN,
};

pub const FILE_INTERNAL_INFORMATION = extern struct {
    IndexNumber: LARGE_INTEGER,
};

pub const FILE_EA_INFORMATION = extern struct {
    EaSize: ULONG,
};

pub const FILE_ACCESS_INFORMATION = extern struct {
    AccessFlags: ACCESS_MASK,
};

pub const FILE_POSITION_INFORMATION = extern struct {
    CurrentByteOffset: LARGE_INTEGER,
};

pub const FILE_MODE_INFORMATION = extern struct {
    Mode: ULONG,
};

pub const FILE_ALIGNMENT_INFORMATION = extern struct {
    AlignmentRequirement: ULONG,
};

pub const FILE_NAME_INFORMATION = extern struct {
    FileNameLength: ULONG,
    FileName: [1]WCHAR,
};

pub const IO_STATUS_BLOCK = extern struct {
    Status: usize,
    Information: ULONG_PTR,
};

pub const FILE_INFORMATION_CLASS = extern enum {
    FileDirectoryInformation = 1,
    FileFullDirectoryInformation,
    FileBothDirectoryInformation,
    FileBasicInformation,
    FileStandardInformation,
    FileInternalInformation,
    FileEaInformation,
    FileAccessInformation,
    FileNameInformation,
    FileRenameInformation,
    FileLinkInformation,
    FileNamesInformation,
    FileDispositionInformation,
    FilePositionInformation,
    FileFullEaInformation,
    FileModeInformation,
    FileAlignmentInformation,
    FileAllInformation,
    FileAllocationInformation,
    FileEndOfFileInformation,
    FileAlternateNameInformation,
    FileStreamInformation,
    FilePipeInformation,
    FilePipeLocalInformation,
    FilePipeRemoteInformation,
    FileMailslotQueryInformation,
    FileMailslotSetInformation,
    FileCompressionInformation,
    FileObjectIdInformation,
    FileCompletionInformation,
    FileMoveClusterInformation,
    FileQuotaInformation,
    FileReparsePointInformation,
    FileNetworkOpenInformation,
    FileAttributeTagInformation,
    FileTrackingInformation,
    FileIdBothDirectoryInformation,
    FileIdFullDirectoryInformation,
    FileValidDataLengthInformation,
    FileShortNameInformation,
    FileIoCompletionNotificationInformation,
    FileIoStatusBlockRangeInformation,
    FileIoPriorityHintInformation,
    FileSfioReserveInformation,
    FileSfioVolumeInformation,
    FileHardLinkInformation,
    FileProcessIdsUsingFileInformation,
    FileNormalizedNameInformation,
    FileNetworkPhysicalNameInformation,
    FileIdGlobalTxDirectoryInformation,
    FileIsRemoteDeviceInformation,
    FileUnusedInformation,
    FileNumaNodeInformation,
    FileStandardLinkInformation,
    FileRemoteProtocolInformation,
    FileRenameInformationBypassAccessCheck,
    FileLinkInformationBypassAccessCheck,
    FileVolumeNameInformation,
    FileIdInformation,
    FileIdExtdDirectoryInformation,
    FileReplaceCompletionInformation,
    FileHardLinkFullIdInformation,
    FileIdExtdBothDirectoryInformation,
    FileDispositionInformationEx,
    FileRenameInformationEx,
    FileRenameInformationExBypassAccessCheck,
    FileDesiredStorageClassInformation,
    FileStatInformation,
    FileMemoryPartitionInformation,
    FileStatLxInformation,
    FileCaseSensitiveInformation,
    FileLinkInformationEx,
    FileLinkInformationExBypassAccessCheck,
    FileStorageReserveIdInformation,
    FileCaseSensitiveInformationForceAccessCheck,
    FileMaximumInformation,
};

pub const OVERLAPPED = extern struct {
    Internal: ULONG_PTR,
    InternalHigh: ULONG_PTR,
    Offset: DWORD,
    OffsetHigh: DWORD,
    hEvent: ?HANDLE,
};
pub const LPOVERLAPPED = *OVERLAPPED;

pub const MAX_PATH = 260;

// TODO issue #305
pub const FILE_INFO_BY_HANDLE_CLASS = u32;
pub const FileBasicInfo = 0;
pub const FileStandardInfo = 1;
pub const FileNameInfo = 2;
pub const FileRenameInfo = 3;
pub const FileDispositionInfo = 4;
pub const FileAllocationInfo = 5;
pub const FileEndOfFileInfo = 6;
pub const FileStreamInfo = 7;
pub const FileCompressionInfo = 8;
pub const FileAttributeTagInfo = 9;
pub const FileIdBothDirectoryInfo = 10;
pub const FileIdBothDirectoryRestartInfo = 11;
pub const FileIoPriorityHintInfo = 12;
pub const FileRemoteProtocolInfo = 13;
pub const FileFullDirectoryInfo = 14;
pub const FileFullDirectoryRestartInfo = 15;
pub const FileStorageInfo = 16;
pub const FileAlignmentInfo = 17;
pub const FileIdInfo = 18;
pub const FileIdExtdDirectoryInfo = 19;
pub const FileIdExtdDirectoryRestartInfo = 20;

pub const BY_HANDLE_FILE_INFORMATION = extern struct {
    dwFileAttributes: DWORD,
    ftCreationTime: FILETIME,
    ftLastAccessTime: FILETIME,
    ftLastWriteTime: FILETIME,
    dwVolumeSerialNumber: DWORD,
    nFileSizeHigh: DWORD,
    nFileSizeLow: DWORD,
    nNumberOfLinks: DWORD,
    nFileIndexHigh: DWORD,
    nFileIndexLow: DWORD,
};

pub const FILE_NAME_INFO = extern struct {
    FileNameLength: DWORD,
    FileName: [1]WCHAR,
};

/// Return the normalized drive name. This is the default.
pub const FILE_NAME_NORMALIZED = 0x0;

/// Return the opened file name (not normalized).
pub const FILE_NAME_OPENED = 0x8;

/// Return the path with the drive letter. This is the default.
pub const VOLUME_NAME_DOS = 0x0;

/// Return the path with a volume GUID path instead of the drive name.
pub const VOLUME_NAME_GUID = 0x1;

/// Return the path with no drive information.
pub const VOLUME_NAME_NONE = 0x4;

/// Return the path with the volume device path.
pub const VOLUME_NAME_NT = 0x2;

pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD,
    lpSecurityDescriptor: ?*c_void,
    bInheritHandle: BOOL,
};
pub const PSECURITY_ATTRIBUTES = *SECURITY_ATTRIBUTES;
pub const LPSECURITY_ATTRIBUTES = *SECURITY_ATTRIBUTES;

pub const GENERIC_READ = 0x80000000;
pub const GENERIC_WRITE = 0x40000000;
pub const GENERIC_EXECUTE = 0x20000000;
pub const GENERIC_ALL = 0x10000000;

pub const FILE_SHARE_DELETE = 0x00000004;
pub const FILE_SHARE_READ = 0x00000001;
pub const FILE_SHARE_WRITE = 0x00000002;

pub const CREATE_ALWAYS = 2;
pub const CREATE_NEW = 1;
pub const OPEN_ALWAYS = 4;
pub const OPEN_EXISTING = 3;
pub const TRUNCATE_EXISTING = 5;

pub const FILE_ATTRIBUTE_ARCHIVE = 0x20;
pub const FILE_ATTRIBUTE_COMPRESSED = 0x800;
pub const FILE_ATTRIBUTE_DEVICE = 0x40;
pub const FILE_ATTRIBUTE_DIRECTORY = 0x10;
pub const FILE_ATTRIBUTE_ENCRYPTED = 0x4000;
pub const FILE_ATTRIBUTE_HIDDEN = 0x2;
pub const FILE_ATTRIBUTE_INTEGRITY_STREAM = 0x8000;
pub const FILE_ATTRIBUTE_NORMAL = 0x80;
pub const FILE_ATTRIBUTE_NOT_CONTENT_INDEXED = 0x2000;
pub const FILE_ATTRIBUTE_NO_SCRUB_DATA = 0x20000;
pub const FILE_ATTRIBUTE_OFFLINE = 0x1000;
pub const FILE_ATTRIBUTE_READONLY = 0x1;
pub const FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = 0x400000;
pub const FILE_ATTRIBUTE_RECALL_ON_OPEN = 0x40000;
pub const FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
pub const FILE_ATTRIBUTE_SPARSE_FILE = 0x200;
pub const FILE_ATTRIBUTE_SYSTEM = 0x4;
pub const FILE_ATTRIBUTE_TEMPORARY = 0x100;
pub const FILE_ATTRIBUTE_VIRTUAL = 0x10000;

pub const PROCESS_INFORMATION = extern struct {
    hProcess: HANDLE,
    hThread: HANDLE,
    dwProcessId: DWORD,
    dwThreadId: DWORD,
};

pub const STARTUPINFOW = extern struct {
    cb: DWORD,
    lpReserved: ?LPWSTR,
    lpDesktop: ?LPWSTR,
    lpTitle: ?LPWSTR,
    dwX: DWORD,
    dwY: DWORD,
    dwXSize: DWORD,
    dwYSize: DWORD,
    dwXCountChars: DWORD,
    dwYCountChars: DWORD,
    dwFillAttribute: DWORD,
    dwFlags: DWORD,
    wShowWindow: WORD,
    cbReserved2: WORD,
    lpReserved2: ?LPBYTE,
    hStdInput: ?HANDLE,
    hStdOutput: ?HANDLE,
    hStdError: ?HANDLE,
};

pub const STARTF_FORCEONFEEDBACK = 0x00000040;
pub const STARTF_FORCEOFFFEEDBACK = 0x00000080;
pub const STARTF_PREVENTPINNING = 0x00002000;
pub const STARTF_RUNFULLSCREEN = 0x00000020;
pub const STARTF_TITLEISAPPID = 0x00001000;
pub const STARTF_TITLEISLINKNAME = 0x00000800;
pub const STARTF_UNTRUSTEDSOURCE = 0x00008000;
pub const STARTF_USECOUNTCHARS = 0x00000008;
pub const STARTF_USEFILLATTRIBUTE = 0x00000010;
pub const STARTF_USEHOTKEY = 0x00000200;
pub const STARTF_USEPOSITION = 0x00000004;
pub const STARTF_USESHOWWINDOW = 0x00000001;
pub const STARTF_USESIZE = 0x00000002;
pub const STARTF_USESTDHANDLES = 0x00000100;

pub const INFINITE = 4294967295;

pub const WAIT_ABANDONED = 0x00000080;
pub const WAIT_OBJECT_0 = 0x00000000;
pub const WAIT_TIMEOUT = 0x00000102;
pub const WAIT_FAILED = 0xFFFFFFFF;

pub const HANDLE_FLAG_INHERIT = 0x00000001;
pub const HANDLE_FLAG_PROTECT_FROM_CLOSE = 0x00000002;

pub const MOVEFILE_COPY_ALLOWED = 2;
pub const MOVEFILE_CREATE_HARDLINK = 16;
pub const MOVEFILE_DELAY_UNTIL_REBOOT = 4;
pub const MOVEFILE_FAIL_IF_NOT_TRACKABLE = 32;
pub const MOVEFILE_REPLACE_EXISTING = 1;
pub const MOVEFILE_WRITE_THROUGH = 8;

pub const FILE_BEGIN = 0;
pub const FILE_CURRENT = 1;
pub const FILE_END = 2;

pub const HEAP_CREATE_ENABLE_EXECUTE = 0x00040000;
pub const HEAP_GENERATE_EXCEPTIONS = 0x00000004;
pub const HEAP_NO_SERIALIZE = 0x00000001;

// AllocationType values
pub const MEM_COMMIT = 0x1000;
pub const MEM_RESERVE = 0x2000;
pub const MEM_RESET = 0x80000;
pub const MEM_RESET_UNDO = 0x1000000;
pub const MEM_LARGE_PAGES = 0x20000000;
pub const MEM_PHYSICAL = 0x400000;
pub const MEM_TOP_DOWN = 0x100000;
pub const MEM_WRITE_WATCH = 0x200000;

// Protect values
pub const PAGE_EXECUTE = 0x10;
pub const PAGE_EXECUTE_READ = 0x20;
pub const PAGE_EXECUTE_READWRITE = 0x40;
pub const PAGE_EXECUTE_WRITECOPY = 0x80;
pub const PAGE_NOACCESS = 0x01;
pub const PAGE_READONLY = 0x02;
pub const PAGE_READWRITE = 0x04;
pub const PAGE_WRITECOPY = 0x08;
pub const PAGE_TARGETS_INVALID = 0x40000000;
pub const PAGE_TARGETS_NO_UPDATE = 0x40000000; // Same as PAGE_TARGETS_INVALID
pub const PAGE_GUARD = 0x100;
pub const PAGE_NOCACHE = 0x200;
pub const PAGE_WRITECOMBINE = 0x400;

// FreeType values
pub const MEM_COALESCE_PLACEHOLDERS = 0x1;
pub const MEM_RESERVE_PLACEHOLDERS = 0x2;
pub const MEM_DECOMMIT = 0x4000;
pub const MEM_RELEASE = 0x8000;

pub const PTHREAD_START_ROUTINE = extern fn (LPVOID) DWORD;
pub const LPTHREAD_START_ROUTINE = PTHREAD_START_ROUTINE;

pub const WIN32_FIND_DATAW = extern struct {
    dwFileAttributes: DWORD,
    ftCreationTime: FILETIME,
    ftLastAccessTime: FILETIME,
    ftLastWriteTime: FILETIME,
    nFileSizeHigh: DWORD,
    nFileSizeLow: DWORD,
    dwReserved0: DWORD,
    dwReserved1: DWORD,
    cFileName: [260]u16,
    cAlternateFileName: [14]u16,
};

pub const FILETIME = extern struct {
    dwLowDateTime: DWORD,
    dwHighDateTime: DWORD,
};

pub const SYSTEM_INFO = extern struct {
    anon1: extern union {
        dwOemId: DWORD,
        anon2: extern struct {
            wProcessorArchitecture: WORD,
            wReserved: WORD,
        },
    },
    dwPageSize: DWORD,
    lpMinimumApplicationAddress: LPVOID,
    lpMaximumApplicationAddress: LPVOID,
    dwActiveProcessorMask: DWORD_PTR,
    dwNumberOfProcessors: DWORD,
    dwProcessorType: DWORD,
    dwAllocationGranularity: DWORD,
    wProcessorLevel: WORD,
    wProcessorRevision: WORD,
};

pub const HRESULT = c_long;

pub const KNOWNFOLDERID = GUID;
pub const GUID = extern struct {
    Data1: c_ulong,
    Data2: c_ushort,
    Data3: c_ushort,
    Data4: [8]u8,

    pub fn parse(str: []const u8) GUID {
        var guid: GUID = undefined;
        var index: usize = 0;
        assert(str[index] == '{');
        index += 1;

        guid.Data1 = std.fmt.parseUnsigned(c_ulong, str[index .. index + 8], 16) catch unreachable;
        index += 8;

        assert(str[index] == '-');
        index += 1;

        guid.Data2 = std.fmt.parseUnsigned(c_ushort, str[index .. index + 4], 16) catch unreachable;
        index += 4;

        assert(str[index] == '-');
        index += 1;

        guid.Data3 = std.fmt.parseUnsigned(c_ushort, str[index .. index + 4], 16) catch unreachable;
        index += 4;

        assert(str[index] == '-');
        index += 1;

        guid.Data4[0] = std.fmt.parseUnsigned(u8, str[index .. index + 2], 16) catch unreachable;
        index += 2;
        guid.Data4[1] = std.fmt.parseUnsigned(u8, str[index .. index + 2], 16) catch unreachable;
        index += 2;

        assert(str[index] == '-');
        index += 1;

        var i: usize = 2;
        while (i < guid.Data4.len) : (i += 1) {
            guid.Data4[i] = std.fmt.parseUnsigned(u8, str[index .. index + 2], 16) catch unreachable;
            index += 2;
        }

        assert(str[index] == '}');
        index += 1;
        return guid;
    }
};

pub const FOLDERID_LocalAppData = GUID.parse("{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}");

pub const KF_FLAG_DEFAULT = 0;
pub const KF_FLAG_NO_APPCONTAINER_REDIRECTION = 65536;
pub const KF_FLAG_CREATE = 32768;
pub const KF_FLAG_DONT_VERIFY = 16384;
pub const KF_FLAG_DONT_UNEXPAND = 8192;
pub const KF_FLAG_NO_ALIAS = 4096;
pub const KF_FLAG_INIT = 2048;
pub const KF_FLAG_DEFAULT_PATH = 1024;
pub const KF_FLAG_NOT_PARENT_RELATIVE = 512;
pub const KF_FLAG_SIMPLE_IDLIST = 256;
pub const KF_FLAG_ALIAS_ONLY = -2147483648;

pub const S_OK = 0;
pub const E_NOTIMPL = @bitCast(c_long, c_ulong(0x80004001));
pub const E_NOINTERFACE = @bitCast(c_long, c_ulong(0x80004002));
pub const E_POINTER = @bitCast(c_long, c_ulong(0x80004003));
pub const E_ABORT = @bitCast(c_long, c_ulong(0x80004004));
pub const E_FAIL = @bitCast(c_long, c_ulong(0x80004005));
pub const E_UNEXPECTED = @bitCast(c_long, c_ulong(0x8000FFFF));
pub const E_ACCESSDENIED = @bitCast(c_long, c_ulong(0x80070005));
pub const E_HANDLE = @bitCast(c_long, c_ulong(0x80070006));
pub const E_OUTOFMEMORY = @bitCast(c_long, c_ulong(0x8007000E));
pub const E_INVALIDARG = @bitCast(c_long, c_ulong(0x80070057));

pub const FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
pub const FILE_FLAG_DELETE_ON_CLOSE = 0x04000000;
pub const FILE_FLAG_NO_BUFFERING = 0x20000000;
pub const FILE_FLAG_OPEN_NO_RECALL = 0x00100000;
pub const FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
pub const FILE_FLAG_OVERLAPPED = 0x40000000;
pub const FILE_FLAG_POSIX_SEMANTICS = 0x0100000;
pub const FILE_FLAG_RANDOM_ACCESS = 0x10000000;
pub const FILE_FLAG_SESSION_AWARE = 0x00800000;
pub const FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000;
pub const FILE_FLAG_WRITE_THROUGH = 0x80000000;

pub const SMALL_RECT = extern struct {
    Left: SHORT,
    Top: SHORT,
    Right: SHORT,
    Bottom: SHORT,
};

pub const COORD = extern struct {
    X: SHORT,
    Y: SHORT,
};

pub const CREATE_UNICODE_ENVIRONMENT = 1024;

pub const TLS_OUT_OF_INDEXES = 4294967295;
pub const IMAGE_TLS_DIRECTORY = extern struct {
    StartAddressOfRawData: usize,
    EndAddressOfRawData: usize,
    AddressOfIndex: usize,
    AddressOfCallBacks: usize,
    SizeOfZeroFill: u32,
    Characteristics: u32,
};
pub const IMAGE_TLS_DIRECTORY64 = IMAGE_TLS_DIRECTORY;
pub const IMAGE_TLS_DIRECTORY32 = IMAGE_TLS_DIRECTORY;

pub const PIMAGE_TLS_CALLBACK = ?extern fn (PVOID, DWORD, PVOID) void;

pub const PROV_RSA_FULL = 1;

pub const REGSAM = ACCESS_MASK;
pub const ACCESS_MASK = DWORD;
pub const PHKEY = *HKEY;
pub const HKEY = *HKEY__;
pub const HKEY__ = extern struct {
    unused: c_int,
};
pub const LSTATUS = LONG;

pub const FILE_NOTIFY_INFORMATION = extern struct {
    NextEntryOffset: DWORD,
    Action: DWORD,
    FileNameLength: DWORD,
    FileName: [1]WCHAR,
};

pub const FILE_ACTION_ADDED = 0x00000001;
pub const FILE_ACTION_REMOVED = 0x00000002;
pub const FILE_ACTION_MODIFIED = 0x00000003;
pub const FILE_ACTION_RENAMED_OLD_NAME = 0x00000004;
pub const FILE_ACTION_RENAMED_NEW_NAME = 0x00000005;

pub const LPOVERLAPPED_COMPLETION_ROUTINE = ?extern fn (DWORD, DWORD, *OVERLAPPED) void;

pub const FILE_LIST_DIRECTORY = 1;

pub const FILE_NOTIFY_CHANGE_CREATION = 64;
pub const FILE_NOTIFY_CHANGE_SIZE = 8;
pub const FILE_NOTIFY_CHANGE_SECURITY = 256;
pub const FILE_NOTIFY_CHANGE_LAST_ACCESS = 32;
pub const FILE_NOTIFY_CHANGE_LAST_WRITE = 16;
pub const FILE_NOTIFY_CHANGE_DIR_NAME = 2;
pub const FILE_NOTIFY_CHANGE_FILE_NAME = 1;
pub const FILE_NOTIFY_CHANGE_ATTRIBUTES = 4;

pub const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: WORD,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

pub const FOREGROUND_BLUE = 1;
pub const FOREGROUND_GREEN = 2;
pub const FOREGROUND_RED = 4;
pub const FOREGROUND_INTENSITY = 8;

pub const LIST_ENTRY = extern struct {
    Flink: *LIST_ENTRY,
    Blink: *LIST_ENTRY,
};

pub const RTL_CRITICAL_SECTION_DEBUG = extern struct {
    Type: WORD,
    CreatorBackTraceIndex: WORD,
    CriticalSection: *RTL_CRITICAL_SECTION,
    ProcessLocksList: LIST_ENTRY,
    EntryCount: DWORD,
    ContentionCount: DWORD,
    Flags: DWORD,
    CreatorBackTraceIndexHigh: WORD,
    SpareWORD: WORD,
};

pub const RTL_CRITICAL_SECTION = extern struct {
    DebugInfo: *RTL_CRITICAL_SECTION_DEBUG,
    LockCount: LONG,
    RecursionCount: LONG,
    OwningThread: HANDLE,
    LockSemaphore: HANDLE,
    SpinCount: ULONG_PTR,
};

pub const CRITICAL_SECTION = RTL_CRITICAL_SECTION;
pub const INIT_ONCE = RTL_RUN_ONCE;
pub const INIT_ONCE_STATIC_INIT = RTL_RUN_ONCE_INIT;
pub const INIT_ONCE_FN = extern fn (InitOnce: *INIT_ONCE, Parameter: ?*c_void, Context: ?*c_void) BOOL;

pub const RTL_RUN_ONCE = extern struct {
    Ptr: ?*c_void,
};

pub const RTL_RUN_ONCE_INIT = RTL_RUN_ONCE{ .Ptr = null };

pub const COINIT_APARTMENTTHREADED = COINIT.COINIT_APARTMENTTHREADED;
pub const COINIT_MULTITHREADED = COINIT.COINIT_MULTITHREADED;
pub const COINIT_DISABLE_OLE1DDE = COINIT.COINIT_DISABLE_OLE1DDE;
pub const COINIT_SPEED_OVER_MEMORY = COINIT.COINIT_SPEED_OVER_MEMORY;
pub const COINIT = extern enum {
    COINIT_APARTMENTTHREADED = 2,
    COINIT_MULTITHREADED = 0,
    COINIT_DISABLE_OLE1DDE = 4,
    COINIT_SPEED_OVER_MEMORY = 8,
};

/// > The maximum path of 32,767 characters is approximate, because the "\\?\"
/// > prefix may be expanded to a longer string by the system at run time, and
/// > this expansion applies to the total length.
/// from https://docs.microsoft.com/en-us/windows/desktop/FileIO/naming-a-file#maximum-path-length-limitation
pub const PATH_MAX_WIDE = 32767;

pub const FORMAT_MESSAGE_ALLOCATE_BUFFER = 0x00000100;
pub const FORMAT_MESSAGE_ARGUMENT_ARRAY = 0x00002000;
pub const FORMAT_MESSAGE_FROM_HMODULE = 0x00000800;
pub const FORMAT_MESSAGE_FROM_STRING = 0x00000400;
pub const FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000;
pub const FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200;
pub const FORMAT_MESSAGE_MAX_WIDTH_MASK = 0x000000FF;

pub const EXCEPTION_DATATYPE_MISALIGNMENT = 0x80000002;
pub const EXCEPTION_ACCESS_VIOLATION = 0xc0000005;
pub const EXCEPTION_ILLEGAL_INSTRUCTION = 0xc000001d;
pub const EXCEPTION_STACK_OVERFLOW = 0xc00000fd;
pub const EXCEPTION_CONTINUE_SEARCH = 0;

pub const EXCEPTION_RECORD = extern struct {
    ExceptionCode: u32,
    ExceptionFlags: u32,
    ExceptionRecord: *EXCEPTION_RECORD,
    ExceptionAddress: *c_void,
    NumberParameters: u32,
    ExceptionInformation: [15]usize,
};

pub const EXCEPTION_POINTERS = extern struct {
    ExceptionRecord: *EXCEPTION_RECORD,
    ContextRecord: *c_void,
};

pub const VECTORED_EXCEPTION_HANDLER = stdcallcc fn (ExceptionInfo: *EXCEPTION_POINTERS) c_long;

pub const OBJECT_ATTRIBUTES = extern struct {
    Length: ULONG,
    RootDirectory: HANDLE,
    ObjectName: *UNICODE_STRING,
    Attributes: ULONG,
    SecurityDescriptor: ?*c_void,
    SecurityQualityOfService: ?*c_void,
};

pub const UNICODE_STRING = extern struct {
    Length: USHORT,
    MaximumLength: USHORT,
    Buffer: [*]WCHAR,
};

const std = @import("../../std.zig");
const maxInt = std.math.maxInt;

pub const fd_t = c_int;
pub const pid_t = c_int;
pub const mode_t = c_uint;

/// Renamed from `kevent` to `Kevent` to avoid conflict with function name.
pub const Kevent = extern struct {
    ident: usize,
    filter: i32,
    flags: u32,
    fflags: u32,
    data: i64,
    udata: usize,
};

pub const dl_phdr_info = extern struct {
    dlpi_addr: usize,
    dlpi_name: ?[*:0]const u8,
    dlpi_phdr: [*]std.elf.Phdr,
    dlpi_phnum: u16,
};

pub const msghdr = extern struct {
    /// optional address
    msg_name: ?*sockaddr,

    /// size of address
    msg_namelen: socklen_t,

    /// scatter/gather array
    msg_iov: [*]iovec,

    /// # elements in msg_iov
    msg_iovlen: i32,

    /// ancillary data
    msg_control: ?*c_void,

    /// ancillary data buffer len
    msg_controllen: socklen_t,

    /// flags on received message
    msg_flags: i32,
};

pub const msghdr_const = extern struct {
    /// optional address
    msg_name: ?*const sockaddr,

    /// size of address
    msg_namelen: socklen_t,

    /// scatter/gather array
    msg_iov: [*]iovec_const,

    /// # elements in msg_iov
    msg_iovlen: i32,

    /// ancillary data
    msg_control: ?*c_void,

    /// ancillary data buffer len
    msg_controllen: socklen_t,

    /// flags on received message
    msg_flags: i32,
};

pub const off_t = i64;

/// Renamed to Stat to not conflict with the stat function.
/// atime, mtime, and ctime have functions to return `timespec`,
/// because although this is a POSIX API, the layout and names of
/// the structs are inconsistent across operating systems, and
/// in C, macros are used to hide the differences. Here we use
/// methods to accomplish this.
pub const Stat = extern struct {
    dev: u64,
    mode: u32,
    ino: u64,
    nlink: usize,

    uid: u32,
    gid: u32,
    rdev: u64,

    atim: timespec,
    mtim: timespec,
    ctim: timespec,
    birthtim: timespec,

    size: off_t,
    blocks: i64,
    blksize: isize,
    flags: u32,
    gen: u32,
    __spare: [2]u32,

    pub fn atime(self: Stat) timespec {
        return self.atim;
    }

    pub fn mtime(self: Stat) timespec {
        return self.mtim;
    }

    pub fn ctime(self: Stat) timespec {
        return self.ctim;
    }
};

pub const timespec = extern struct {
    tv_sec: i64,
    tv_nsec: isize,
};

pub const dirent = extern struct {
    d_fileno: u64,
    d_reclen: u16,
    d_namlen: u16,
    d_type: u8,
    d_off: i64,
    d_name: [512]u8,

    pub fn reclen(self: dirent) u16 {
        return self.d_reclen;
    }
};

pub const in_port_t = u16;
pub const sa_family_t = u8;

pub const sockaddr = extern struct {
    /// total length
    len: u8,

    /// address family
    family: sa_family_t,

    /// actually longer; address value
    data: [14]u8,
};

pub const sockaddr_in = extern struct {
    len: u8 = @sizeOf(sockaddr_in),
    family: sa_family_t,
    port: in_port_t,
    addr: u32,
    zero: [8]u8 = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
};

pub const sockaddr_in6 = extern struct {
    len: u8 = @sizeOf(sockaddr_in6),
    family: sa_family_t,
    port: in_port_t,
    flowinfo: u32,
    addr: [16]u8,
    scope_id: u32,
};

/// Definitions for UNIX IPC domain.
pub const sockaddr_un = extern struct {
    /// total sockaddr length
    len: u8 = @sizeOf(sockaddr_un),

    /// AF_LOCAL
    family: sa_family_t,

    /// path name
    path: [104]u8,
};

pub const CTL_KERN = 1;
pub const CTL_DEBUG = 5;

pub const KERN_PROC_ARGS = 48; // struct: process argv/env
pub const KERN_PROC_PATHNAME = 5; // path to executable

pub const PATH_MAX = 1024;

pub const STDIN_FILENO = 0;
pub const STDOUT_FILENO = 1;
pub const STDERR_FILENO = 2;

pub const PROT_NONE = 0;
pub const PROT_READ = 1;
pub const PROT_WRITE = 2;
pub const PROT_EXEC = 4;

pub const CLOCK_REALTIME = 0;
pub const CLOCK_VIRTUAL = 1;
pub const CLOCK_PROF = 2;
pub const CLOCK_MONOTONIC = 3;
pub const CLOCK_THREAD_CPUTIME_ID = 0x20000000;
pub const CLOCK_PROCESS_CPUTIME_ID = 0x40000000;

pub const MAP_FAILED = @intToPtr(*c_void, maxInt(usize));
pub const MAP_SHARED = 0x0001;
pub const MAP_PRIVATE = 0x0002;
pub const MAP_REMAPDUP = 0x0004;
pub const MAP_FIXED = 0x0010;
pub const MAP_RENAME = 0x0020;
pub const MAP_NORESERVE = 0x0040;
pub const MAP_INHERIT = 0x0080;
pub const MAP_HASSEMAPHORE = 0x0200;
pub const MAP_TRYFIXED = 0x0400;
pub const MAP_WIRED = 0x0800;

pub const MAP_FILE = 0x0000;
pub const MAP_NOSYNC = 0x0800;
pub const MAP_ANON = 0x1000;
pub const MAP_ANONYMOUS = MAP_ANON;
pub const MAP_STACK = 0x2000;

pub const WNOHANG = 0x00000001;
pub const WUNTRACED = 0x00000002;
pub const WSTOPPED = WUNTRACED;
pub const WCONTINUED = 0x00000010;
pub const WNOWAIT = 0x00010000;
pub const WEXITED = 0x00000020;
pub const WTRAPPED = 0x00000040;

pub const SA_ONSTACK = 0x0001;
pub const SA_RESTART = 0x0002;
pub const SA_RESETHAND = 0x0004;
pub const SA_NOCLDSTOP = 0x0008;
pub const SA_NODEFER = 0x0010;
pub const SA_NOCLDWAIT = 0x0020;
pub const SA_SIGINFO = 0x0040;

pub const SIGHUP = 1;
pub const SIGINT = 2;
pub const SIGQUIT = 3;
pub const SIGILL = 4;
pub const SIGTRAP = 5;
pub const SIGABRT = 6;
pub const SIGIOT = SIGABRT;
pub const SIGEMT = 7;
pub const SIGFPE = 8;
pub const SIGKILL = 9;
pub const SIGBUS = 10;
pub const SIGSEGV = 11;
pub const SIGSYS = 12;
pub const SIGPIPE = 13;
pub const SIGALRM = 14;
pub const SIGTERM = 15;
pub const SIGURG = 16;
pub const SIGSTOP = 17;
pub const SIGTSTP = 18;
pub const SIGCONT = 19;
pub const SIGCHLD = 20;
pub const SIGTTIN = 21;
pub const SIGTTOU = 22;
pub const SIGIO = 23;
pub const SIGXCPU = 24;
pub const SIGXFSZ = 25;
pub const SIGVTALRM = 26;
pub const SIGPROF = 27;
pub const SIGWINCH = 28;
pub const SIGINFO = 29;
pub const SIGUSR1 = 30;
pub const SIGUSR2 = 31;
pub const SIGPWR = 32;

pub const SIGRTMIN = 33;
pub const SIGRTMAX = 63;

// access function
pub const F_OK = 0; // test for existence of file
pub const X_OK = 1; // test for execute or search permission
pub const W_OK = 2; // test for write permission
pub const R_OK = 4; // test for read permission

pub const O_RDONLY = 0x0000;
pub const O_WRONLY = 0x0001;
pub const O_RDWR = 0x0002;
pub const O_ACCMODE = 0x0003;

pub const O_CREAT = 0x0200;
pub const O_EXCL = 0x0800;
pub const O_NOCTTY = 0x8000;
pub const O_TRUNC = 0x0400;
pub const O_APPEND = 0x0008;
pub const O_NONBLOCK = 0x0004;
pub const O_DSYNC = 0x00010000;
pub const O_SYNC = 0x0080;
pub const O_RSYNC = 0x00020000;
pub const O_DIRECTORY = 0x00080000;
pub const O_NOFOLLOW = 0x00000100;
pub const O_CLOEXEC = 0x00400000;

pub const O_ASYNC = 0x0040;
pub const O_DIRECT = 0x00080000;
pub const O_NOATIME = 0;
pub const O_PATH = 0;
pub const O_TMPFILE = 0;
pub const O_NDELAY = O_NONBLOCK;

pub const F_DUPFD = 0;
pub const F_GETFD = 1;
pub const F_SETFD = 2;
pub const F_GETFL = 3;
pub const F_SETFL = 4;

pub const F_GETOWN = 5;
pub const F_SETOWN = 6;

pub const F_GETLK = 7;
pub const F_SETLK = 8;
pub const F_SETLKW = 9;

pub const SEEK_SET = 0;
pub const SEEK_CUR = 1;
pub const SEEK_END = 2;

pub const SIG_BLOCK = 1;
pub const SIG_UNBLOCK = 2;
pub const SIG_SETMASK = 3;

pub const SOCK_STREAM = 1;
pub const SOCK_DGRAM = 2;
pub const SOCK_RAW = 3;
pub const SOCK_RDM = 4;
pub const SOCK_SEQPACKET = 5;

pub const SOCK_CLOEXEC = 0x10000000;
pub const SOCK_NONBLOCK = 0x20000000;

pub const PF_UNSPEC = 0;
pub const PF_LOCAL = 1;
pub const PF_UNIX = PF_LOCAL;
pub const PF_FILE = PF_LOCAL;
pub const PF_INET = 2;
pub const PF_APPLETALK = 16;
pub const PF_INET6 = 24;
pub const PF_DECnet = 12;
pub const PF_KEY = 29;
pub const PF_ROUTE = 34;
pub const PF_SNA = 11;
pub const PF_MPLS = 33;
pub const PF_CAN = 35;
pub const PF_BLUETOOTH = 31;
pub const PF_ISDN = 26;
pub const PF_MAX = 37;

pub const AF_UNSPEC = PF_UNSPEC;
pub const AF_LOCAL = PF_LOCAL;
pub const AF_UNIX = AF_LOCAL;
pub const AF_FILE = AF_LOCAL;
pub const AF_INET = PF_INET;
pub const AF_APPLETALK = PF_APPLETALK;
pub const AF_INET6 = PF_INET6;
pub const AF_KEY = PF_KEY;
pub const AF_ROUTE = PF_ROUTE;
pub const AF_SNA = PF_SNA;
pub const AF_MPLS = PF_MPLS;
pub const AF_CAN = PF_CAN;
pub const AF_BLUETOOTH = PF_BLUETOOTH;
pub const AF_ISDN = PF_ISDN;
pub const AF_MAX = PF_MAX;

pub const DT_UNKNOWN = 0;
pub const DT_FIFO = 1;
pub const DT_CHR = 2;
pub const DT_DIR = 4;
pub const DT_BLK = 6;
pub const DT_REG = 8;
pub const DT_LNK = 10;
pub const DT_SOCK = 12;
pub const DT_WHT = 14;

/// add event to kq (implies enable)
pub const EV_ADD = 0x0001;

/// delete event from kq
pub const EV_DELETE = 0x0002;

/// enable event
pub const EV_ENABLE = 0x0004;

/// disable event (not reported)
pub const EV_DISABLE = 0x0008;

/// only report one occurrence
pub const EV_ONESHOT = 0x0010;

/// clear event state after reporting
pub const EV_CLEAR = 0x0020;

/// force immediate event output
/// ... with or without EV_ERROR
/// ... use KEVENT_FLAG_ERROR_EVENTS
///     on syscalls supporting flags
pub const EV_RECEIPT = 0x0040;

/// disable event after reporting
pub const EV_DISPATCH = 0x0080;

pub const EVFILT_READ = 0;
pub const EVFILT_WRITE = 1;

/// attached to aio requests
pub const EVFILT_AIO = 2;

/// attached to vnodes
pub const EVFILT_VNODE = 3;

/// attached to struct proc
pub const EVFILT_PROC = 4;

/// attached to struct proc
pub const EVFILT_SIGNAL = 5;

/// timers
pub const EVFILT_TIMER = 6;

/// Filesystem events
pub const EVFILT_FS = 7;

/// On input, NOTE_TRIGGER causes the event to be triggered for output.
pub const NOTE_TRIGGER = 0x08000000;

/// low water mark
pub const NOTE_LOWAT = 0x00000001;

/// vnode was removed
pub const NOTE_DELETE = 0x00000001;

/// data contents changed
pub const NOTE_WRITE = 0x00000002;

/// size increased
pub const NOTE_EXTEND = 0x00000004;

/// attributes changed
pub const NOTE_ATTRIB = 0x00000008;

/// link count changed
pub const NOTE_LINK = 0x00000010;

/// vnode was renamed
pub const NOTE_RENAME = 0x00000020;

/// vnode access was revoked
pub const NOTE_REVOKE = 0x00000040;

/// process exited
pub const NOTE_EXIT = 0x80000000;

/// process forked
pub const NOTE_FORK = 0x40000000;

/// process exec'd
pub const NOTE_EXEC = 0x20000000;

/// mask for signal & exit status
pub const NOTE_PDATAMASK = 0x000fffff;
pub const NOTE_PCTRLMASK = 0xf0000000;

pub const TIOCCBRK = 0x2000747a;
pub const TIOCCDTR = 0x20007478;
pub const TIOCCONS = 0x80047462;
pub const TIOCDCDTIMESTAMP = 0x40107458;
pub const TIOCDRAIN = 0x2000745e;
pub const TIOCEXCL = 0x2000740d;
pub const TIOCEXT = 0x80047460;
pub const TIOCFLAG_CDTRCTS = 0x10;
pub const TIOCFLAG_CLOCAL = 0x2;
pub const TIOCFLAG_CRTSCTS = 0x4;
pub const TIOCFLAG_MDMBUF = 0x8;
pub const TIOCFLAG_SOFTCAR = 0x1;
pub const TIOCFLUSH = 0x80047410;
pub const TIOCGETA = 0x402c7413;
pub const TIOCGETD = 0x4004741a;
pub const TIOCGFLAGS = 0x4004745d;
pub const TIOCGLINED = 0x40207442;
pub const TIOCGPGRP = 0x40047477;
pub const TIOCGQSIZE = 0x40047481;
pub const TIOCGRANTPT = 0x20007447;
pub const TIOCGSID = 0x40047463;
pub const TIOCGSIZE = 0x40087468;
pub const TIOCGWINSZ = 0x40087468;
pub const TIOCMBIC = 0x8004746b;
pub const TIOCMBIS = 0x8004746c;
pub const TIOCMGET = 0x4004746a;
pub const TIOCMSET = 0x8004746d;
pub const TIOCM_CAR = 0x40;
pub const TIOCM_CD = 0x40;
pub const TIOCM_CTS = 0x20;
pub const TIOCM_DSR = 0x100;
pub const TIOCM_DTR = 0x2;
pub const TIOCM_LE = 0x1;
pub const TIOCM_RI = 0x80;
pub const TIOCM_RNG = 0x80;
pub const TIOCM_RTS = 0x4;
pub const TIOCM_SR = 0x10;
pub const TIOCM_ST = 0x8;
pub const TIOCNOTTY = 0x20007471;
pub const TIOCNXCL = 0x2000740e;
pub const TIOCOUTQ = 0x40047473;
pub const TIOCPKT = 0x80047470;
pub const TIOCPKT_DATA = 0x0;
pub const TIOCPKT_DOSTOP = 0x20;
pub const TIOCPKT_FLUSHREAD = 0x1;
pub const TIOCPKT_FLUSHWRITE = 0x2;
pub const TIOCPKT_IOCTL = 0x40;
pub const TIOCPKT_NOSTOP = 0x10;
pub const TIOCPKT_START = 0x8;
pub const TIOCPKT_STOP = 0x4;
pub const TIOCPTMGET = 0x40287446;
pub const TIOCPTSNAME = 0x40287448;
pub const TIOCRCVFRAME = 0x80087445;
pub const TIOCREMOTE = 0x80047469;
pub const TIOCSBRK = 0x2000747b;
pub const TIOCSCTTY = 0x20007461;
pub const TIOCSDTR = 0x20007479;
pub const TIOCSETA = 0x802c7414;
pub const TIOCSETAF = 0x802c7416;
pub const TIOCSETAW = 0x802c7415;
pub const TIOCSETD = 0x8004741b;
pub const TIOCSFLAGS = 0x8004745c;
pub const TIOCSIG = 0x2000745f;
pub const TIOCSLINED = 0x80207443;
pub const TIOCSPGRP = 0x80047476;
pub const TIOCSQSIZE = 0x80047480;
pub const TIOCSSIZE = 0x80087467;
pub const TIOCSTART = 0x2000746e;
pub const TIOCSTAT = 0x80047465;
pub const TIOCSTI = 0x80017472;
pub const TIOCSTOP = 0x2000746f;
pub const TIOCSWINSZ = 0x80087467;
pub const TIOCUCNTL = 0x80047466;
pub const TIOCXMTFRAME = 0x80087444;

pub fn WEXITSTATUS(s: u32) u32 {
    return (s >> 8) & 0xff;
}
pub fn WTERMSIG(s: u32) u32 {
    return s & 0x7f;
}
pub fn WSTOPSIG(s: u32) u32 {
    return WEXITSTATUS(s);
}
pub fn WIFEXITED(s: u32) bool {
    return WTERMSIG(s) == 0;
}

pub fn WIFCONTINUED(s: u32) bool {
    return ((s & 0x7f) == 0xffff);
}

pub fn WIFSTOPPED(s: u32) bool {
    return ((s & 0x7f != 0x7f) and !WIFCONTINUED(s));
}

pub fn WIFSIGNALED(s: u32) bool {
    return !WIFSTOPPED(s) and !WIFCONTINUED(s) and !WIFEXITED(s);
}

pub const winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

const NSIG = 32;

pub const SIG_ERR = @intToPtr(extern fn (i32) void, maxInt(usize));
pub const SIG_DFL = @intToPtr(extern fn (i32) void, 0);
pub const SIG_IGN = @intToPtr(extern fn (i32) void, 1);

/// Renamed from `sigaction` to `Sigaction` to avoid conflict with the syscall.
pub const Sigaction = extern struct {
    /// signal handler
    __sigaction_u: extern union {
        __sa_handler: extern fn (i32) void,
        __sa_sigaction: extern fn (i32, *__siginfo, usize) void,
    },

    /// see signal options
    sa_flags: u32,

    /// signal mask to apply
    sa_mask: sigset_t,
};

pub const _SIG_WORDS = 4;
pub const _SIG_MAXSIG = 128;

pub inline fn _SIG_IDX(sig: usize) usize {
    return sig - 1;
}
pub inline fn _SIG_WORD(sig: usize) usize {
    return_SIG_IDX(sig) >> 5;
}
pub inline fn _SIG_BIT(sig: usize) usize {
    return 1 << (_SIG_IDX(sig) & 31);
}
pub inline fn _SIG_VALID(sig: usize) usize {
    return sig <= _SIG_MAXSIG and sig > 0;
}

pub const sigset_t = extern struct {
    __bits: [_SIG_WORDS]u32,
};

pub const EPERM = 1; // Operation not permitted
pub const ENOENT = 2; // No such file or directory
pub const ESRCH = 3; // No such process
pub const EINTR = 4; // Interrupted system call
pub const EIO = 5; // Input/output error
pub const ENXIO = 6; // Device not configured
pub const E2BIG = 7; // Argument list too long
pub const ENOEXEC = 8; // Exec format error
pub const EBADF = 9; // Bad file descriptor
pub const ECHILD = 10; // No child processes
pub const EDEADLK = 11; // Resource deadlock avoided
// 11 was EAGAIN
pub const ENOMEM = 12; // Cannot allocate memory
pub const EACCES = 13; // Permission denied
pub const EFAULT = 14; // Bad address
pub const ENOTBLK = 15; // Block device required
pub const EBUSY = 16; // Device busy
pub const EEXIST = 17; // File exists
pub const EXDEV = 18; // Cross-device link
pub const ENODEV = 19; // Operation not supported by device
pub const ENOTDIR = 20; // Not a directory
pub const EISDIR = 21; // Is a directory
pub const EINVAL = 22; // Invalid argument
pub const ENFILE = 23; // Too many open files in system
pub const EMFILE = 24; // Too many open files
pub const ENOTTY = 25; // Inappropriate ioctl for device
pub const ETXTBSY = 26; // Text file busy
pub const EFBIG = 27; // File too large
pub const ENOSPC = 28; // No space left on device
pub const ESPIPE = 29; // Illegal seek
pub const EROFS = 30; // Read-only file system
pub const EMLINK = 31; // Too many links
pub const EPIPE = 32; // Broken pipe

// math software
pub const EDOM = 33; // Numerical argument out of domain
pub const ERANGE = 34; // Result too large or too small

// non-blocking and interrupt i/o
pub const EAGAIN = 35; // Resource temporarily unavailable
pub const EWOULDBLOCK = EAGAIN; // Operation would block
pub const EINPROGRESS = 36; // Operation now in progress
pub const EALREADY = 37; // Operation already in progress

// ipc/network software -- argument errors
pub const ENOTSOCK = 38; // Socket operation on non-socket
pub const EDESTADDRREQ = 39; // Destination address required
pub const EMSGSIZE = 40; // Message too long
pub const EPROTOTYPE = 41; // Protocol wrong type for socket
pub const ENOPROTOOPT = 42; // Protocol option not available
pub const EPROTONOSUPPORT = 43; // Protocol not supported
pub const ESOCKTNOSUPPORT = 44; // Socket type not supported
pub const EOPNOTSUPP = 45; // Operation not supported
pub const EPFNOSUPPORT = 46; // Protocol family not supported
pub const EAFNOSUPPORT = 47; // Address family not supported by protocol family
pub const EADDRINUSE = 48; // Address already in use
pub const EADDRNOTAVAIL = 49; // Can't assign requested address

// ipc/network software -- operational errors
pub const ENETDOWN = 50; // Network is down
pub const ENETUNREACH = 51; // Network is unreachable
pub const ENETRESET = 52; // Network dropped connection on reset
pub const ECONNABORTED = 53; // Software caused connection abort
pub const ECONNRESET = 54; // Connection reset by peer
pub const ENOBUFS = 55; // No buffer space available
pub const EISCONN = 56; // Socket is already connected
pub const ENOTCONN = 57; // Socket is not connected
pub const ESHUTDOWN = 58; // Can't send after socket shutdown
pub const ETOOMANYREFS = 59; // Too many references: can't splice
pub const ETIMEDOUT = 60; // Operation timed out
pub const ECONNREFUSED = 61; // Connection refused

pub const ELOOP = 62; // Too many levels of symbolic links
pub const ENAMETOOLONG = 63; // File name too long

// should be rearranged
pub const EHOSTDOWN = 64; // Host is down
pub const EHOSTUNREACH = 65; // No route to host
pub const ENOTEMPTY = 66; // Directory not empty

// quotas & mush
pub const EPROCLIM = 67; // Too many processes
pub const EUSERS = 68; // Too many users
pub const EDQUOT = 69; // Disc quota exceeded

// Network File System
pub const ESTALE = 70; // Stale NFS file handle
pub const EREMOTE = 71; // Too many levels of remote in path
pub const EBADRPC = 72; // RPC struct is bad
pub const ERPCMISMATCH = 73; // RPC version wrong
pub const EPROGUNAVAIL = 74; // RPC prog. not avail
pub const EPROGMISMATCH = 75; // Program version wrong
pub const EPROCUNAVAIL = 76; // Bad procedure for program

pub const ENOLCK = 77; // No locks available
pub const ENOSYS = 78; // Function not implemented

pub const EFTYPE = 79; // Inappropriate file type or format
pub const EAUTH = 80; // Authentication error
pub const ENEEDAUTH = 81; // Need authenticator

// SystemV IPC
pub const EIDRM = 82; // Identifier removed
pub const ENOMSG = 83; // No message of desired type
pub const EOVERFLOW = 84; // Value too large to be stored in data type

// Wide/multibyte-character handling, ISO/IEC 9899/AMD1:1995
pub const EILSEQ = 85; // Illegal byte sequence

// From IEEE Std 1003.1-2001
// Base, Realtime, Threads or Thread Priority Scheduling option errors
pub const ENOTSUP = 86; // Not supported

// Realtime option errors
pub const ECANCELED = 87; // Operation canceled

// Realtime, XSI STREAMS option errors
pub const EBADMSG = 88; // Bad or Corrupt message

// XSI STREAMS option errors
pub const ENODATA = 89; // No message available
pub const ENOSR = 90; // No STREAM resources
pub const ENOSTR = 91; // Not a STREAM
pub const ETIME = 92; // STREAM ioctl timeout

// File system extended attribute errors
pub const ENOATTR = 93; // Attribute not found

// Realtime, XSI STREAMS option errors
pub const EMULTIHOP = 94; // Multihop attempted
pub const ENOLINK = 95; // Link has been severed
pub const EPROTO = 96; // Protocol error

pub const ELAST = 96; // Must equal largest errno

pub const MINSIGSTKSZ = 8192;
pub const SIGSTKSZ = MINSIGSTKSZ + 32768;

pub const SS_ONSTACK = 1;
pub const SS_DISABLE = 4;

pub const stack_t = extern struct {
    ss_sp: [*]u8,
    ss_size: isize,
    ss_flags: i32,
};

pub const S_IFMT = 0o170000;

pub const S_IFIFO = 0o010000;
pub const S_IFCHR = 0o020000;
pub const S_IFDIR = 0o040000;
pub const S_IFBLK = 0o060000;
pub const S_IFREG = 0o100000;
pub const S_IFLNK = 0o120000;
pub const S_IFSOCK = 0o140000;
pub const S_IFWHT = 0o160000;

pub const S_ISUID = 0o4000;
pub const S_ISGID = 0o2000;
pub const S_ISVTX = 0o1000;
pub const S_IRWXU = 0o700;
pub const S_IRUSR = 0o400;
pub const S_IWUSR = 0o200;
pub const S_IXUSR = 0o100;
pub const S_IRWXG = 0o070;
pub const S_IRGRP = 0o040;
pub const S_IWGRP = 0o020;
pub const S_IXGRP = 0o010;
pub const S_IRWXO = 0o007;
pub const S_IROTH = 0o004;
pub const S_IWOTH = 0o002;
pub const S_IXOTH = 0o001;

pub fn S_ISFIFO(m: u32) bool {
    return m & S_IFMT == S_IFIFO;
}

pub fn S_ISCHR(m: u32) bool {
    return m & S_IFMT == S_IFCHR;
}

pub fn S_ISDIR(m: u32) bool {
    return m & S_IFMT == S_IFDIR;
}

pub fn S_ISBLK(m: u32) bool {
    return m & S_IFMT == S_IFBLK;
}

pub fn S_ISREG(m: u32) bool {
    return m & S_IFMT == S_IFREG;
}

pub fn S_ISLNK(m: u32) bool {
    return m & S_IFMT == S_IFLNK;
}

pub fn S_ISSOCK(m: u32) bool {
    return m & S_IFMT == S_IFSOCK;
}

pub fn S_IWHT(m: u32) bool {
    return m & S_IFMT == S_IFWHT;
}

pub const HOST_NAME_MAX = 255;

/// dummy for IP
pub const IPPROTO_IP = 0;

/// IP6 hop-by-hop options
pub const IPPROTO_HOPOPTS = 0;

/// control message protocol
pub const IPPROTO_ICMP = 1;

/// group mgmt protocol
pub const IPPROTO_IGMP = 2;

/// gateway^2 (deprecated)
pub const IPPROTO_GGP = 3;

/// IP header
pub const IPPROTO_IPV4 = 4;

/// IP inside IP
pub const IPPROTO_IPIP = 4;

/// tcp
pub const IPPROTO_TCP = 6;

/// exterior gateway protocol
pub const IPPROTO_EGP = 8;

/// pup
pub const IPPROTO_PUP = 12;

/// user datagram protocol
pub const IPPROTO_UDP = 17;

/// xns idp
pub const IPPROTO_IDP = 22;

/// tp-4 w/ class negotiation
pub const IPPROTO_TP = 29;

/// DCCP
pub const IPPROTO_DCCP = 33;

/// IP6 header
pub const IPPROTO_IPV6 = 41;

/// IP6 routing header
pub const IPPROTO_ROUTING = 43;

/// IP6 fragmentation header
pub const IPPROTO_FRAGMENT = 44;

/// resource reservation
pub const IPPROTO_RSVP = 46;

/// GRE encaps RFC 1701
pub const IPPROTO_GRE = 47;

/// encap. security payload
pub const IPPROTO_ESP = 50;

/// authentication header
pub const IPPROTO_AH = 51;

/// IP Mobility RFC 2004
pub const IPPROTO_MOBILE = 55;

/// IPv6 ICMP
pub const IPPROTO_IPV6_ICMP = 58;

/// ICMP6
pub const IPPROTO_ICMPV6 = 58;

/// IP6 no next header
pub const IPPROTO_NONE = 59;

/// IP6 destination option
pub const IPPROTO_DSTOPTS = 60;

/// ISO cnlp
pub const IPPROTO_EON = 80;

/// Ethernet-in-IP
pub const IPPROTO_ETHERIP = 97;

/// encapsulation header
pub const IPPROTO_ENCAP = 98;

/// Protocol indep. multicast
pub const IPPROTO_PIM = 103;

/// IP Payload Comp. Protocol
pub const IPPROTO_IPCOMP = 108;

/// VRRP RFC 2338
pub const IPPROTO_VRRP = 112;

/// Common Address Resolution Protocol
pub const IPPROTO_CARP = 112;

/// L2TPv3
pub const IPPROTO_L2TP = 115;

/// SCTP
pub const IPPROTO_SCTP = 132;

/// PFSYNC
pub const IPPROTO_PFSYNC = 240;

/// raw IP packet
pub const IPPROTO_RAW = 255;

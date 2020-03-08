const std = @import("std");
const builtin = std.builtin;
const page_size = std.mem.page_size;

pub const tokenizer = @import("c/tokenizer.zig");
pub const Token = tokenizer.Token;
pub const Tokenizer = tokenizer.Tokenizer;
pub const parse = @import("c/parse.zig").parse;
pub const ast = @import("c/ast.zig");

pub usingnamespace @import("os/bits.zig");

pub usingnamespace switch (std.Target.current.os.tag) {
    .linux => @import("c/linux.zig"),
    .windows => @import("c/windows.zig"),
    .macosx, .ios, .tvos, .watchos => @import("c/darwin.zig"),
    .freebsd, .kfreebsd => @import("c/freebsd.zig"),
    .netbsd => @import("c/netbsd.zig"),
    .dragonfly => @import("c/dragonfly.zig"),
    .openbsd => @import("c/openbsd.zig"),
    .haiku => @import("c/haiku.zig"),
    .hermit => @import("c/hermit.zig"),
    .solaris => @import("c/solaris.zig"),
    .fuchsia => @import("c/fuchsia.zig"),
    .minix => @import("c/minix.zig"),
    .emscripten => @import("c/emscripten.zig"),
    else => struct {},
};

pub fn getErrno(rc: var) u16 {
    if (rc == -1) {
        return @intCast(u16, _errno().*);
    } else {
        return 0;
    }
}

/// The return type is `type` to force comptime function call execution.
/// TODO: https://github.com/ziglang/zig/issues/425
/// If not linking libc, returns struct{pub const ok = false;}
/// If linking musl libc, returns struct{pub const ok = true;}
/// If linking gnu libc (glibc), the `ok` value will be true if the target
/// version is greater than or equal to `glibc_version`.
/// If linking a libc other than these, returns `false`.
pub fn versionCheck(glibc_version: builtin.Version) type {
    return struct {
        pub const ok = blk: {
            if (!builtin.link_libc) break :blk false;
            if (std.Target.current.abi.isMusl()) break :blk true;
            if (std.Target.current.isGnuLibC()) {
                const ver = std.Target.current.os.version_range.linux.glibc;
                const order = ver.order(glibc_version);
                break :blk switch (order) {
                    .gt, .eq => true,
                    .lt => false,
                };
            } else {
                break :blk false;
            }
        };
    };
}

pub extern "c" var environ: [*:null]?[*:0]u8;

pub extern "c" fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*FILE;
pub extern "c" fn fclose(stream: *FILE) c_int;
pub extern "c" fn fwrite(ptr: [*]const u8, size_of_type: usize, item_count: usize, stream: *FILE) usize;
pub extern "c" fn fread(ptr: [*]u8, size_of_type: usize, item_count: usize, stream: *FILE) usize;

pub extern "c" fn printf(format: [*:0]const u8, ...) c_int;
pub extern "c" fn abort() noreturn;
pub extern "c" fn exit(code: c_int) noreturn;
pub extern "c" fn isatty(fd: fd_t) c_int;
pub extern "c" fn close(fd: fd_t) c_int;
pub extern "c" fn fstat(fd: fd_t, buf: *Stat) c_int;
pub extern "c" fn @"fstat$INODE64"(fd: fd_t, buf: *Stat) c_int;
pub extern "c" fn fstatat(dirfd: fd_t, path: [*:0]const u8, stat_buf: *Stat, flags: u32) c_int;
pub extern "c" fn lseek(fd: fd_t, offset: off_t, whence: c_int) off_t;
pub extern "c" fn open(path: [*:0]const u8, oflag: c_uint, ...) c_int;
pub extern "c" fn openat(fd: c_int, path: [*:0]const u8, oflag: c_uint, ...) c_int;
pub extern "c" fn raise(sig: c_int) c_int;
pub extern "c" fn read(fd: fd_t, buf: [*]u8, nbyte: usize) isize;
pub extern "c" fn readv(fd: c_int, iov: [*]const iovec, iovcnt: c_uint) isize;
pub extern "c" fn pread(fd: fd_t, buf: [*]u8, nbyte: usize, offset: u64) isize;
pub extern "c" fn preadv(fd: c_int, iov: [*]const iovec, iovcnt: c_uint, offset: u64) isize;
pub extern "c" fn writev(fd: c_int, iov: [*]const iovec_const, iovcnt: c_uint) isize;
pub extern "c" fn pwritev(fd: c_int, iov: [*]const iovec_const, iovcnt: c_uint, offset: u64) isize;
pub extern "c" fn stat(noalias path: [*:0]const u8, noalias buf: *Stat) c_int;
pub extern "c" fn write(fd: fd_t, buf: [*]const u8, nbyte: usize) isize;
pub extern "c" fn pwrite(fd: fd_t, buf: [*]const u8, nbyte: usize, offset: u64) isize;
pub extern "c" fn mmap(addr: ?*align(page_size) c_void, len: usize, prot: c_uint, flags: c_uint, fd: fd_t, offset: u64) *c_void;
pub extern "c" fn munmap(addr: *align(page_size) c_void, len: usize) c_int;
pub extern "c" fn mprotect(addr: *align(page_size) c_void, len: usize, prot: c_uint) c_int;
pub extern "c" fn unlink(path: [*:0]const u8) c_int;
pub extern "c" fn unlinkat(dirfd: fd_t, path: [*:0]const u8, flags: c_uint) c_int;
pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*]u8;
pub extern "c" fn waitpid(pid: c_int, stat_loc: *c_uint, options: c_uint) c_int;
pub extern "c" fn fork() c_int;
pub extern "c" fn access(path: [*:0]const u8, mode: c_uint) c_int;
pub extern "c" fn faccessat(dirfd: fd_t, path: [*:0]const u8, mode: c_uint, flags: c_uint) c_int;
pub extern "c" fn pipe(fds: *[2]fd_t) c_int;
pub extern "c" fn pipe2(fds: *[2]fd_t, flags: u32) c_int;
pub extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
pub extern "c" fn mkdirat(dirfd: fd_t, path: [*:0]const u8, mode: u32) c_int;
pub extern "c" fn symlink(existing: [*:0]const u8, new: [*:0]const u8) c_int;
pub extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
pub extern "c" fn chdir(path: [*:0]const u8) c_int;
pub extern "c" fn fchdir(fd: fd_t) c_int;
pub extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
pub extern "c" fn dup(fd: fd_t) c_int;
pub extern "c" fn dup2(old_fd: fd_t, new_fd: fd_t) c_int;
pub extern "c" fn readlink(noalias path: [*:0]const u8, noalias buf: [*]u8, bufsize: usize) isize;
pub extern "c" fn readlinkat(dirfd: fd_t, noalias path: [*:0]const u8, noalias buf: [*]u8, bufsize: usize) isize;
pub extern "c" fn realpath(noalias file_name: [*:0]const u8, noalias resolved_name: [*]u8) ?[*:0]u8;
pub extern "c" fn sigprocmask(how: c_int, noalias set: ?*const sigset_t, noalias oset: ?*sigset_t) c_int;
pub extern "c" fn gettimeofday(noalias tv: ?*timeval, noalias tz: ?*timezone) c_int;
pub extern "c" fn sigaction(sig: c_int, noalias act: *const Sigaction, noalias oact: ?*Sigaction) c_int;
pub extern "c" fn nanosleep(rqtp: *const timespec, rmtp: ?*timespec) c_int;
pub extern "c" fn setreuid(ruid: c_uint, euid: c_uint) c_int;
pub extern "c" fn setregid(rgid: c_uint, egid: c_uint) c_int;
pub extern "c" fn rmdir(path: [*:0]const u8) c_int;
pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
pub extern "c" fn getrusage(who: c_int, usage: *rusage) c_int;
pub extern "c" fn sysctl(name: [*]const c_int, namelen: c_uint, oldp: ?*c_void, oldlenp: ?*usize, newp: ?*c_void, newlen: usize) c_int;
pub extern "c" fn sysctlbyname(name: [*:0]const u8, oldp: ?*c_void, oldlenp: ?*usize, newp: ?*c_void, newlen: usize) c_int;
pub extern "c" fn sysctlnametomib(name: [*:0]const u8, mibp: ?*c_int, sizep: ?*usize) c_int;
pub extern "c" fn tcgetattr(fd: fd_t, termios_p: *termios) c_int;
pub extern "c" fn tcsetattr(fd: fd_t, optional_action: TCSA, termios_p: *const termios) c_int;
pub extern "c" fn fcntl(fd: fd_t, cmd: c_int, ...) c_int;
pub extern "c" fn uname(buf: *utsname) c_int;

pub extern "c" fn gethostname(name: [*]u8, len: usize) c_int;
pub extern "c" fn bind(socket: fd_t, address: ?*const sockaddr, address_len: socklen_t) c_int;
pub extern "c" fn socket(domain: c_uint, sock_type: c_uint, protocol: c_uint) c_int;
pub extern "c" fn listen(sockfd: fd_t, backlog: c_uint) c_int;
pub extern "c" fn getsockname(sockfd: fd_t, noalias addr: *sockaddr, noalias addrlen: *socklen_t) c_int;
pub extern "c" fn connect(sockfd: fd_t, sock_addr: *const sockaddr, addrlen: socklen_t) c_int;
pub extern "c" fn accept4(sockfd: fd_t, addr: *sockaddr, addrlen: *socklen_t, flags: c_uint) c_int;
pub extern "c" fn getsockopt(sockfd: fd_t, level: u32, optname: u32, optval: *c_void, optlen: *socklen_t) c_int;
pub extern "c" fn setsockopt(sockfd: fd_t, level: u32, optname: u32, optval: *c_void, optlen: socklen_t) c_int;
pub extern "c" fn send(sockfd: fd_t, buf: *const c_void, len: usize, flags: u32) isize;
pub extern "c" fn sendto(
    sockfd: fd_t,
    buf: *const c_void,
    len: usize,
    flags: u32,
    dest_addr: ?*const sockaddr,
    addrlen: socklen_t,
) isize;

pub extern fn recv(sockfd: fd_t, arg1: ?*c_void, arg2: usize, arg3: c_int) isize;
pub extern fn recvfrom(
    sockfd: fd_t,
    noalias buf: *c_void,
    len: usize,
    flags: u32,
    noalias src_addr: ?*sockaddr,
    noalias addrlen: ?*socklen_t,
) isize;

pub extern "c" fn kill(pid: pid_t, sig: c_int) c_int;
pub extern "c" fn getdirentries(fd: fd_t, buf_ptr: [*]u8, nbytes: usize, basep: *i64) isize;
pub extern "c" fn setgid(ruid: c_uint, euid: c_uint) c_int;
pub extern "c" fn setuid(uid: c_uint) c_int;
pub extern "c" fn clock_gettime(clk_id: c_int, tp: *timespec) c_int;
pub extern "c" fn clock_getres(clk_id: c_int, tp: *timespec) c_int;

pub extern "c" fn aligned_alloc(alignment: usize, size: usize) ?*c_void;
pub extern "c" fn malloc(usize) ?*c_void;
pub extern "c" fn realloc(?*c_void, usize) ?*c_void;
pub extern "c" fn free(*c_void) void;
pub extern "c" fn posix_memalign(memptr: **c_void, alignment: usize, size: usize) c_int;

// Deprecated
pub extern "c" fn futimes(fd: fd_t, times: *[2]timeval) c_int;
pub extern "c" fn utimes(path: [*:0]const u8, times: *[2]timeval) c_int;

pub extern "c" fn utimensat(dirfd: fd_t, pathname: [*:0]const u8, times: *[2]timespec, flags: u32) c_int;
pub extern "c" fn futimens(fd: fd_t, times: *const [2]timespec) c_int;

pub extern "c" fn pthread_create(noalias newthread: *pthread_t, noalias attr: ?*const pthread_attr_t, start_routine: extern fn (?*c_void) ?*c_void, noalias arg: ?*c_void) c_int;
pub extern "c" fn pthread_attr_init(attr: *pthread_attr_t) c_int;
pub extern "c" fn pthread_attr_setstack(attr: *pthread_attr_t, stackaddr: *c_void, stacksize: usize) c_int;
pub extern "c" fn pthread_attr_destroy(attr: *pthread_attr_t) c_int;
pub extern "c" fn pthread_self() pthread_t;
pub extern "c" fn pthread_join(thread: pthread_t, arg_return: ?*?*c_void) c_int;

pub extern "c" fn kqueue() c_int;
pub extern "c" fn kevent(
    kq: c_int,
    changelist: [*]const Kevent,
    nchanges: c_int,
    eventlist: [*]Kevent,
    nevents: c_int,
    timeout: ?*const timespec,
) c_int;

pub extern "c" fn getaddrinfo(
    noalias node: [*:0]const u8,
    noalias service: [*:0]const u8,
    noalias hints: *const addrinfo,
    noalias res: **addrinfo,
) EAI;

pub extern "c" fn freeaddrinfo(res: *addrinfo) void;

pub extern "c" fn getnameinfo(
    noalias addr: *const sockaddr,
    addrlen: socklen_t,
    noalias host: [*]u8,
    hostlen: socklen_t,
    noalias serv: [*]u8,
    servlen: socklen_t,
    flags: u32,
) EAI;

pub extern "c" fn gai_strerror(errcode: EAI) [*:0]const u8;

pub extern "c" fn poll(fds: [*]pollfd, nfds: nfds_t, timeout: c_int) c_int;

pub extern "c" fn dn_expand(
    msg: [*:0]const u8,
    eomorig: [*:0]const u8,
    comp_dn: [*:0]const u8,
    exp_dn: [*:0]u8,
    length: c_int,
) c_int;

pub extern "c" fn sched_yield() c_int;

pub const PTHREAD_MUTEX_INITIALIZER = pthread_mutex_t{};
pub extern "c" fn pthread_mutex_lock(mutex: *pthread_mutex_t) c_int;
pub extern "c" fn pthread_mutex_unlock(mutex: *pthread_mutex_t) c_int;
pub extern "c" fn pthread_mutex_destroy(mutex: *pthread_mutex_t) c_int;

pub const PTHREAD_COND_INITIALIZER = pthread_cond_t{};
pub extern "c" fn pthread_cond_wait(noalias cond: *pthread_cond_t, noalias mutex: *pthread_mutex_t) c_int;
pub extern "c" fn pthread_cond_timedwait(noalias cond: *pthread_cond_t, noalias mutex: *pthread_mutex_t, noalias abstime: *const timespec) c_int;
pub extern "c" fn pthread_cond_signal(cond: *pthread_cond_t) c_int;
pub extern "c" fn pthread_cond_broadcast(cond: *pthread_cond_t) c_int;
pub extern "c" fn pthread_cond_destroy(cond: *pthread_cond_t) c_int;

pub const pthread_t = *@OpaqueType();
pub const FILE = @OpaqueType();

pub extern "c" fn dlopen(path: [*:0]const u8, mode: c_int) ?*c_void;
pub extern "c" fn dlclose(handle: *c_void) c_int;
pub extern "c" fn dlsym(handle: ?*c_void, symbol: [*:0]const u8) ?*c_void;

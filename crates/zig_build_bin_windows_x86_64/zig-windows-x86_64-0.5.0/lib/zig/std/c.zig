const builtin = @import("builtin");
const std = @import("std");
const page_size = std.mem.page_size;

pub usingnamespace @import("os/bits.zig");

pub usingnamespace switch (builtin.os) {
    .linux => @import("c/linux.zig"),
    .windows => @import("c/windows.zig"),
    .macosx, .ios, .tvos, .watchos => @import("c/darwin.zig"),
    .freebsd => @import("c/freebsd.zig"),
    .netbsd => @import("c/netbsd.zig"),
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
            switch (builtin.abi) {
                .musl, .musleabi, .musleabihf => break :blk true,
                .gnu, .gnuabin32, .gnuabi64, .gnueabi, .gnueabihf, .gnux32 => {
                    const ver = builtin.glibc_version orelse break :blk false;
                    if (ver.major < glibc_version.major) break :blk false;
                    if (ver.major > glibc_version.major) break :blk true;
                    if (ver.minor < glibc_version.minor) break :blk false;
                    if (ver.minor > glibc_version.minor) break :blk true;
                    break :blk ver.patch >= glibc_version.patch;
                },
                else => break :blk false,
            }
        };
    };
}

// TODO https://github.com/ziglang/zig/issues/265 on this whole file

pub extern "c" fn fopen(filename: [*]const u8, modes: [*]const u8) ?*FILE;
pub extern "c" fn fclose(stream: *FILE) c_int;
pub extern "c" fn fwrite(ptr: [*]const u8, size_of_type: usize, item_count: usize, stream: *FILE) usize;
pub extern "c" fn fread(ptr: [*]u8, size_of_type: usize, item_count: usize, stream: *FILE) usize;

pub extern "c" fn printf(format: [*]const u8, ...) c_int;
pub extern "c" fn abort() noreturn;
pub extern "c" fn exit(code: c_int) noreturn;
pub extern "c" fn isatty(fd: fd_t) c_int;
pub extern "c" fn close(fd: fd_t) c_int;
pub extern "c" fn @"close$NOCANCEL"(fd: fd_t) c_int;
pub extern "c" fn fstat(fd: fd_t, buf: *Stat) c_int;
pub extern "c" fn @"fstat$INODE64"(fd: fd_t, buf: *Stat) c_int;
pub extern "c" fn lseek(fd: fd_t, offset: off_t, whence: c_int) off_t;
pub extern "c" fn open(path: [*]const u8, oflag: c_uint, ...) c_int;
pub extern "c" fn openat(fd: c_int, path: [*]const u8, oflag: c_uint, ...) c_int;
pub extern "c" fn raise(sig: c_int) c_int;
pub extern "c" fn read(fd: fd_t, buf: [*]u8, nbyte: usize) isize;
pub extern "c" fn readv(fd: c_int, iov: [*]const iovec, iovcnt: c_uint) isize;
pub extern "c" fn pread(fd: fd_t, buf: [*]u8, nbyte: usize, offset: u64) isize;
pub extern "c" fn preadv(fd: c_int, iov: [*]const iovec, iovcnt: c_uint, offset: u64) isize;
pub extern "c" fn writev(fd: c_int, iov: [*]const iovec_const, iovcnt: c_uint) isize;
pub extern "c" fn pwritev(fd: c_int, iov: [*]const iovec_const, iovcnt: c_uint, offset: u64) isize;
pub extern "c" fn stat(noalias path: [*]const u8, noalias buf: *Stat) c_int;
pub extern "c" fn write(fd: fd_t, buf: [*]const u8, nbyte: usize) isize;
pub extern "c" fn pwrite(fd: fd_t, buf: [*]const u8, nbyte: usize, offset: u64) isize;
pub extern "c" fn mmap(addr: ?*align(page_size) c_void, len: usize, prot: c_uint, flags: c_uint, fd: fd_t, offset: u64) *c_void;
pub extern "c" fn munmap(addr: *align(page_size) c_void, len: usize) c_int;
pub extern "c" fn mprotect(addr: *align(page_size) c_void, len: usize, prot: c_uint) c_int;
pub extern "c" fn unlink(path: [*]const u8) c_int;
pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*]u8;
pub extern "c" fn waitpid(pid: c_int, stat_loc: *c_uint, options: c_uint) c_int;
pub extern "c" fn fork() c_int;
pub extern "c" fn access(path: [*]const u8, mode: c_uint) c_int;
pub extern "c" fn pipe(fds: *[2]fd_t) c_int;
pub extern "c" fn pipe2(fds: *[2]fd_t, flags: u32) c_int;
pub extern "c" fn mkdir(path: [*]const u8, mode: c_uint) c_int;
pub extern "c" fn symlink(existing: [*]const u8, new: [*]const u8) c_int;
pub extern "c" fn rename(old: [*]const u8, new: [*]const u8) c_int;
pub extern "c" fn chdir(path: [*]const u8) c_int;
pub extern "c" fn execve(path: [*]const u8, argv: [*]const ?[*]const u8, envp: [*]const ?[*]const u8) c_int;
pub extern "c" fn dup(fd: fd_t) c_int;
pub extern "c" fn dup2(old_fd: fd_t, new_fd: fd_t) c_int;
pub extern "c" fn readlink(noalias path: [*]const u8, noalias buf: [*]u8, bufsize: usize) isize;
pub extern "c" fn realpath(noalias file_name: [*]const u8, noalias resolved_name: [*]u8) ?[*]u8;
pub extern "c" fn sigprocmask(how: c_int, noalias set: *const sigset_t, noalias oset: ?*sigset_t) c_int;
pub extern "c" fn gettimeofday(noalias tv: ?*timeval, noalias tz: ?*timezone) c_int;
pub extern "c" fn sigaction(sig: c_int, noalias act: *const Sigaction, noalias oact: ?*Sigaction) c_int;
pub extern "c" fn nanosleep(rqtp: *const timespec, rmtp: ?*timespec) c_int;
pub extern "c" fn setreuid(ruid: c_uint, euid: c_uint) c_int;
pub extern "c" fn setregid(rgid: c_uint, egid: c_uint) c_int;
pub extern "c" fn rmdir(path: [*]const u8) c_int;
pub extern "c" fn getenv(name: [*]const u8) ?[*]u8;
pub extern "c" fn sysctl(name: [*]const c_int, namelen: c_uint, oldp: ?*c_void, oldlenp: ?*usize, newp: ?*c_void, newlen: usize) c_int;
pub extern "c" fn sysctlbyname(name: [*]const u8, oldp: ?*c_void, oldlenp: ?*usize, newp: ?*c_void, newlen: usize) c_int;
pub extern "c" fn sysctlnametomib(name: [*]const u8, mibp: ?*c_int, sizep: ?*usize) c_int;

pub extern "c" fn gethostname(name: [*]u8, len: usize) c_int;
pub extern "c" fn bind(socket: fd_t, address: ?*const sockaddr, address_len: socklen_t) c_int;
pub extern "c" fn socket(domain: c_uint, sock_type: c_uint, protocol: c_uint) c_int;
pub extern "c" fn listen(sockfd: fd_t, backlog: c_uint) c_int;
pub extern "c" fn getsockname(sockfd: fd_t, noalias addr: *sockaddr, noalias addrlen: *socklen_t) c_int;
pub extern "c" fn connect(sockfd: fd_t, sock_addr: *const sockaddr, addrlen: socklen_t) c_int;
pub extern "c" fn accept4(sockfd: fd_t, addr: *sockaddr, addrlen: *socklen_t, flags: c_uint) c_int;
pub extern "c" fn getsockopt(sockfd: fd_t, level: c_int, optname: c_int, optval: *c_void, optlen: *socklen_t) c_int;
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

pub extern "c" fn utimensat(dirfd: fd_t, pathname: [*]const u8, times: *[2]timespec, flags: u32) c_int;
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

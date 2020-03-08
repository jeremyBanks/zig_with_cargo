const std = @import("../std.zig");
usingnamespace std.c;
extern "c" threadlocal var errno: c_int;
pub fn _errno() *c_int {
    return &errno;
}

pub extern "c" fn getdents(fd: c_int, buf_ptr: [*]u8, nbytes: usize) usize;
pub extern "c" fn sigaltstack(ss: ?*stack_t, old_ss: ?*stack_t) c_int;
pub extern "c" fn getrandom(buf_ptr: [*]u8, buf_len: usize, flags: c_uint) isize;

pub const dl_iterate_phdr_callback = extern fn (info: *dl_phdr_info, size: usize, data: ?*c_void) c_int;
pub extern "c" fn dl_iterate_phdr(callback: dl_iterate_phdr_callback, data: ?*c_void) c_int;

pub const pthread_mutex_t = extern struct {
    inner: ?*c_void = null,
};
pub const pthread_cond_t = extern struct {
    inner: ?*c_void = null,
};

pub const pthread_attr_t = extern struct { // copied from freebsd
    __size: [56]u8,
    __align: c_long,
};

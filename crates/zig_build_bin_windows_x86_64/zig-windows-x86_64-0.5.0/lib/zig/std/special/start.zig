// This file is included in the compilation unit when exporting an executable.

const root = @import("root");
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const uefi = std.os.uefi;

var starting_stack_ptr: [*]usize = undefined;

const is_wasm = switch (builtin.arch) {
    .wasm32, .wasm64 => true,
    else => false,
};

const is_mips = switch (builtin.arch) {
    .mips, .mipsel, .mips64, .mips64el => true,
    else => false,
};

comptime {
    if (builtin.link_libc) {
        @export("main", main, .Strong);
    } else if (builtin.os == .windows) {
        @export("WinMainCRTStartup", WinMainCRTStartup, .Strong);
    } else if (is_wasm and builtin.os == .freestanding) {
        @export("_start", wasm_freestanding_start, .Strong);
    } else if (builtin.os == .uefi) {
        @export("EfiMain", EfiMain, .Strong);
    } else if (is_mips) {
        if (!@hasDecl(root, "__start")) @export("__start", _start, .Strong);
    } else {
        if (!@hasDecl(root, "_start")) @export("_start", _start, .Strong);
    }
}

extern fn wasm_freestanding_start() void {
    _ = callMain();
}

extern fn EfiMain(handle: uefi.Handle, system_table: *uefi.tables.SystemTable) usize {
    const bad_efi_main_ret = "expected return type of main to be 'void', 'noreturn', or 'usize'";
    uefi.handle = handle;
    uefi.system_table = system_table;

    switch (@typeInfo(@typeOf(root.main).ReturnType)) {
        .NoReturn => {
            root.main();
        },
        .Void => {
            root.main();
            return 0;
        },
        .Int => |info| {
            if (info.bits != @typeInfo(usize).Int.bits) {
                @compileError(bad_efi_main_ret);
            }
            return root.main();
        },
        else => @compileError(bad_efi_main_ret),
    }
}

nakedcc fn _start() noreturn {
    if (builtin.os == builtin.Os.wasi) {
        std.os.wasi.proc_exit(callMain());
    }

    switch (builtin.arch) {
        .x86_64 => {
            starting_stack_ptr = asm (""
                : [argc] "={rsp}" (-> [*]usize)
            );
        },
        .i386 => {
            starting_stack_ptr = asm (""
                : [argc] "={esp}" (-> [*]usize)
            );
        },
        .aarch64, .aarch64_be, .arm => {
            starting_stack_ptr = asm ("mov %[argc], sp"
                : [argc] "=r" (-> [*]usize)
            );
        },
        .riscv64 => {
            starting_stack_ptr = asm ("mv %[argc], sp"
                : [argc] "=r" (-> [*]usize)
            );
        },
        .mipsel => {
            // Need noat here because LLVM is free to pick any register
            starting_stack_ptr = asm (
                \\ .set noat
                \\ move %[argc], $sp
                : [argc] "=r" (-> [*]usize)
            );
        },
        else => @compileError("unsupported arch"),
    }
    // If LLVM inlines stack variables into _start, they will overwrite
    // the command line argument data.
    @noInlineCall(posixCallMainAndExit);
}

extern fn WinMainCRTStartup() noreturn {
    @setAlignStack(16);
    if (!builtin.single_threaded) {
        _ = @import("start_windows_tls.zig");
    }

    std.debug.maybeEnableSegfaultHandler();

    std.os.windows.kernel32.ExitProcess(callMain());
}

// TODO https://github.com/ziglang/zig/issues/265
fn posixCallMainAndExit() noreturn {
    if (builtin.os == builtin.Os.freebsd) {
        @setAlignStack(16);
    }
    const argc = starting_stack_ptr[0];
    const argv = @ptrCast([*][*]u8, starting_stack_ptr + 1);

    const envp_optional = @ptrCast([*]?[*]u8, argv + argc + 1);
    var envp_count: usize = 0;
    while (envp_optional[envp_count]) |_| : (envp_count += 1) {}
    const envp = @ptrCast([*][*]u8, envp_optional)[0..envp_count];

    if (builtin.os == .linux) {
        // Find the beginning of the auxiliary vector
        const auxv = @ptrCast([*]std.elf.Auxv, envp.ptr + envp_count + 1);
        std.os.linux.elf_aux_maybe = auxv;
        // Initialize the TLS area
        const gnu_stack_phdr = std.os.linux.tls.initTLS() orelse @panic("ELF missing stack size");

        if (std.os.linux.tls.tls_image) |tls_img| {
            const tls_addr = std.os.linux.tls.allocateTLS(tls_img.alloc_size);
            const tp = std.os.linux.tls.copyTLS(tls_addr);
            std.os.linux.tls.setThreadPointer(tp);
        }

        // TODO This is disabled because what should we do when linking libc and this code
        // does not execute? And also it's causing a test failure in stack traces in release modes.

        //// Linux ignores the stack size from the ELF file, and instead always does 8 MiB. A further
        //// problem is that it uses PROT_GROWSDOWN which prevents stores to addresses too far down
        //// the stack and requires "probing". So here we allocate our own stack.
        //const wanted_stack_size = gnu_stack_phdr.p_memsz;
        //assert(wanted_stack_size % std.mem.page_size == 0);
        //// Allocate an extra page as the guard page.
        //const total_size = wanted_stack_size + std.mem.page_size;
        //const new_stack = std.os.mmap(
        //    null,
        //    total_size,
        //    std.os.PROT_READ | std.os.PROT_WRITE,
        //    std.os.MAP_PRIVATE | std.os.MAP_ANONYMOUS,
        //    -1,
        //    0,
        //) catch @panic("out of memory");
        //std.os.mprotect(new_stack[0..std.mem.page_size], std.os.PROT_NONE) catch {};
        //std.os.exit(@newStackCall(new_stack, callMainWithArgs, argc, argv, envp));
    }

    std.os.exit(@inlineCall(callMainWithArgs, argc, argv, envp));
}

fn callMainWithArgs(argc: usize, argv: [*][*]u8, envp: [][*]u8) u8 {
    std.os.argv = argv[0..argc];
    std.os.environ = envp;

    std.debug.maybeEnableSegfaultHandler();

    return callMain();
}

extern fn main(c_argc: i32, c_argv: [*][*]u8, c_envp: [*]?[*]u8) i32 {
    var env_count: usize = 0;
    while (c_envp[env_count] != null) : (env_count += 1) {}
    const envp = @ptrCast([*][*]u8, c_envp)[0..env_count];
    return @inlineCall(callMainWithArgs, @intCast(usize, c_argc), c_argv, envp);
}

// General error message for a malformed return type
const bad_main_ret = "expected return type of main to be 'void', '!void', 'noreturn', 'u8', or '!u8'";

// This is marked inline because for some reason LLVM in release mode fails to inline it,
// and we want fewer call frames in stack traces.
inline fn callMain() u8 {
    switch (@typeInfo(@typeOf(root.main).ReturnType)) {
        .NoReturn => {
            root.main();
        },
        .Void => {
            root.main();
            return 0;
        },
        .Int => |info| {
            if (info.bits != 8) {
                @compileError(bad_main_ret);
            }
            return root.main();
        },
        .ErrorUnion => {
            const result = root.main() catch |err| {
                std.debug.warn("error: {}\n", @errorName(err));
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                return 1;
            };
            switch (@typeInfo(@typeOf(result))) {
                .Void => return 0,
                .Int => |info| {
                    if (info.bits != 8) {
                        @compileError(bad_main_ret);
                    }
                    return result;
                },
                else => @compileError(bad_main_ret),
            }
        },
        else => @compileError(bad_main_ret),
    }
}

const main_thread_tls_align = 32;
var main_thread_tls_bytes: [64]u8 align(main_thread_tls_align) = [1]u8{0} ** 64;

const std = @import("std.zig");
const cstr = std.cstr;
const unicode = std.unicode;
const io = std.io;
const fs = std.fs;
const os = std.os;
const process = std.process;
const File = std.fs.File;
const windows = os.windows;
const mem = std.mem;
const debug = std.debug;
const BufMap = std.BufMap;
const Buffer = std.Buffer;
const builtin = @import("builtin");
const Os = builtin.Os;
const TailQueue = std.TailQueue;
const maxInt = std.math.maxInt;

pub const ChildProcess = struct {
    pub pid: if (os.windows.is_the_target) void else i32,
    pub handle: if (os.windows.is_the_target) windows.HANDLE else void,
    pub thread_handle: if (os.windows.is_the_target) windows.HANDLE else void,

    pub allocator: *mem.Allocator,

    pub stdin: ?File,
    pub stdout: ?File,
    pub stderr: ?File,

    pub term: ?(SpawnError!Term),

    pub argv: []const []const u8,

    /// Leave as null to use the current env map using the supplied allocator.
    pub env_map: ?*const BufMap,

    pub stdin_behavior: StdIo,
    pub stdout_behavior: StdIo,
    pub stderr_behavior: StdIo,

    /// Set to change the user id when spawning the child process.
    pub uid: if (os.windows.is_the_target) void else ?u32,

    /// Set to change the group id when spawning the child process.
    pub gid: if (os.windows.is_the_target) void else ?u32,

    /// Set to change the current working directory when spawning the child process.
    pub cwd: ?[]const u8,

    err_pipe: if (os.windows.is_the_target) void else [2]os.fd_t,
    llnode: if (os.windows.is_the_target) void else TailQueue(*ChildProcess).Node,

    pub const SpawnError = error{OutOfMemory} || os.ExecveError || os.SetIdError ||
        os.ChangeCurDirError || windows.CreateProcessError;

    pub const Term = union(enum) {
        Exited: u32,
        Signal: u32,
        Stopped: u32,
        Unknown: u32,
    };

    pub const StdIo = enum {
        Inherit,
        Ignore,
        Pipe,
        Close,
    };

    /// First argument in argv is the executable.
    /// On success must call deinit.
    pub fn init(argv: []const []const u8, allocator: *mem.Allocator) !*ChildProcess {
        const child = try allocator.create(ChildProcess);
        child.* = ChildProcess{
            .allocator = allocator,
            .argv = argv,
            .pid = undefined,
            .handle = undefined,
            .thread_handle = undefined,
            .err_pipe = undefined,
            .llnode = undefined,
            .term = null,
            .env_map = null,
            .cwd = null,
            .uid = if (os.windows.is_the_target) {} else null,
            .gid = if (os.windows.is_the_target) {} else null,
            .stdin = null,
            .stdout = null,
            .stderr = null,
            .stdin_behavior = StdIo.Inherit,
            .stdout_behavior = StdIo.Inherit,
            .stderr_behavior = StdIo.Inherit,
        };
        errdefer allocator.destroy(child);
        return child;
    }

    pub fn setUserName(self: *ChildProcess, name: []const u8) !void {
        const user_info = try os.getUserInfo(name);
        self.uid = user_info.uid;
        self.gid = user_info.gid;
    }

    /// On success must call `kill` or `wait`.
    pub fn spawn(self: *ChildProcess) !void {
        if (os.windows.is_the_target) {
            return self.spawnWindows();
        } else {
            return self.spawnPosix();
        }
    }

    pub fn spawnAndWait(self: *ChildProcess) !Term {
        try self.spawn();
        return self.wait();
    }

    /// Forcibly terminates child process and then cleans up all resources.
    pub fn kill(self: *ChildProcess) !Term {
        if (os.windows.is_the_target) {
            return self.killWindows(1);
        } else {
            return self.killPosix();
        }
    }

    pub fn killWindows(self: *ChildProcess, exit_code: windows.UINT) !Term {
        if (self.term) |term| {
            self.cleanupStreams();
            return term;
        }

        try windows.TerminateProcess(self.handle, exit_code);
        try self.waitUnwrappedWindows();
        return self.term.?;
    }

    pub fn killPosix(self: *ChildProcess) !Term {
        if (self.term) |term| {
            self.cleanupStreams();
            return term;
        }
        try os.kill(self.pid, os.SIGTERM);
        self.waitUnwrapped();
        return self.term.?;
    }

    /// Blocks until child process terminates and then cleans up all resources.
    pub fn wait(self: *ChildProcess) !Term {
        if (os.windows.is_the_target) {
            return self.waitWindows();
        } else {
            return self.waitPosix();
        }
    }

    pub const ExecResult = struct {
        term: Term,
        stdout: []u8,
        stderr: []u8,
    };

    /// Spawns a child process, waits for it, collecting stdout and stderr, and then returns.
    /// If it succeeds, the caller owns result.stdout and result.stderr memory.
    pub fn exec(allocator: *mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, env_map: ?*const BufMap, max_output_size: usize) !ExecResult {
        const child = try ChildProcess.init(argv, allocator);
        defer child.deinit();

        child.stdin_behavior = ChildProcess.StdIo.Ignore;
        child.stdout_behavior = ChildProcess.StdIo.Pipe;
        child.stderr_behavior = ChildProcess.StdIo.Pipe;
        child.cwd = cwd;
        child.env_map = env_map;

        try child.spawn();

        var stdout = Buffer.initNull(allocator);
        var stderr = Buffer.initNull(allocator);
        defer Buffer.deinit(&stdout);
        defer Buffer.deinit(&stderr);

        var stdout_file_in_stream = child.stdout.?.inStream();
        var stderr_file_in_stream = child.stderr.?.inStream();

        try stdout_file_in_stream.stream.readAllBuffer(&stdout, max_output_size);
        try stderr_file_in_stream.stream.readAllBuffer(&stderr, max_output_size);

        return ExecResult{
            .term = try child.wait(),
            .stdout = stdout.toOwnedSlice(),
            .stderr = stderr.toOwnedSlice(),
        };
    }

    fn waitWindows(self: *ChildProcess) !Term {
        if (self.term) |term| {
            self.cleanupStreams();
            return term;
        }

        try self.waitUnwrappedWindows();
        return self.term.?;
    }

    fn waitPosix(self: *ChildProcess) !Term {
        if (self.term) |term| {
            self.cleanupStreams();
            return term;
        }

        self.waitUnwrapped();
        return self.term.?;
    }

    pub fn deinit(self: *ChildProcess) void {
        self.allocator.destroy(self);
    }

    fn waitUnwrappedWindows(self: *ChildProcess) !void {
        const result = windows.WaitForSingleObject(self.handle, windows.INFINITE);

        self.term = (SpawnError!Term)(x: {
            var exit_code: windows.DWORD = undefined;
            if (windows.kernel32.GetExitCodeProcess(self.handle, &exit_code) == 0) {
                break :x Term{ .Unknown = 0 };
            } else {
                break :x Term{ .Exited = exit_code };
            }
        });

        os.close(self.handle);
        os.close(self.thread_handle);
        self.cleanupStreams();
        return result;
    }

    fn waitUnwrapped(self: *ChildProcess) void {
        const status = os.waitpid(self.pid, 0);
        self.cleanupStreams();
        self.handleWaitResult(status);
    }

    fn handleWaitResult(self: *ChildProcess, status: u32) void {
        self.term = self.cleanupAfterWait(status);
    }

    fn cleanupStreams(self: *ChildProcess) void {
        if (self.stdin) |*stdin| {
            stdin.close();
            self.stdin = null;
        }
        if (self.stdout) |*stdout| {
            stdout.close();
            self.stdout = null;
        }
        if (self.stderr) |*stderr| {
            stderr.close();
            self.stderr = null;
        }
    }

    fn cleanupAfterWait(self: *ChildProcess, status: u32) !Term {
        defer {
            os.close(self.err_pipe[0]);
            os.close(self.err_pipe[1]);
        }

        // Write maxInt(ErrInt) to the write end of the err_pipe. This is after
        // waitpid, so this write is guaranteed to be after the child
        // pid potentially wrote an error. This way we can do a blocking
        // read on the error pipe and either get maxInt(ErrInt) (no error) or
        // an error code.
        try writeIntFd(self.err_pipe[1], maxInt(ErrInt));
        const err_int = try readIntFd(self.err_pipe[0]);
        // Here we potentially return the fork child's error
        // from the parent pid.
        if (err_int != maxInt(ErrInt)) {
            return @errSetCast(SpawnError, @intToError(err_int));
        }

        return statusToTerm(status);
    }

    fn statusToTerm(status: u32) Term {
        return if (os.WIFEXITED(status))
            Term{ .Exited = os.WEXITSTATUS(status) }
        else if (os.WIFSIGNALED(status))
            Term{ .Signal = os.WTERMSIG(status) }
        else if (os.WIFSTOPPED(status))
            Term{ .Stopped = os.WSTOPSIG(status) }
        else
            Term{ .Unknown = status };
    }

    fn spawnPosix(self: *ChildProcess) !void {
        const stdin_pipe = if (self.stdin_behavior == StdIo.Pipe) try os.pipe() else undefined;
        errdefer if (self.stdin_behavior == StdIo.Pipe) {
            destroyPipe(stdin_pipe);
        };

        const stdout_pipe = if (self.stdout_behavior == StdIo.Pipe) try os.pipe() else undefined;
        errdefer if (self.stdout_behavior == StdIo.Pipe) {
            destroyPipe(stdout_pipe);
        };

        const stderr_pipe = if (self.stderr_behavior == StdIo.Pipe) try os.pipe() else undefined;
        errdefer if (self.stderr_behavior == StdIo.Pipe) {
            destroyPipe(stderr_pipe);
        };

        const any_ignore = (self.stdin_behavior == StdIo.Ignore or self.stdout_behavior == StdIo.Ignore or self.stderr_behavior == StdIo.Ignore);
        const dev_null_fd = if (any_ignore) try os.openC(c"/dev/null", os.O_RDWR, 0) else undefined;
        defer {
            if (any_ignore) os.close(dev_null_fd);
        }

        var env_map_owned: BufMap = undefined;
        var we_own_env_map: bool = undefined;
        const env_map = if (self.env_map) |env_map| x: {
            we_own_env_map = false;
            break :x env_map;
        } else x: {
            we_own_env_map = true;
            env_map_owned = try process.getEnvMap(self.allocator);
            break :x &env_map_owned;
        };
        defer {
            if (we_own_env_map) env_map_owned.deinit();
        }

        // This pipe is used to communicate errors between the time of fork
        // and execve from the child process to the parent process.
        const err_pipe = try os.pipe();
        errdefer destroyPipe(err_pipe);

        const pid_result = try os.fork();
        if (pid_result == 0) {
            // we are the child
            setUpChildIo(self.stdin_behavior, stdin_pipe[0], os.STDIN_FILENO, dev_null_fd) catch |err| forkChildErrReport(err_pipe[1], err);
            setUpChildIo(self.stdout_behavior, stdout_pipe[1], os.STDOUT_FILENO, dev_null_fd) catch |err| forkChildErrReport(err_pipe[1], err);
            setUpChildIo(self.stderr_behavior, stderr_pipe[1], os.STDERR_FILENO, dev_null_fd) catch |err| forkChildErrReport(err_pipe[1], err);

            if (self.stdin_behavior == .Pipe) {
                os.close(stdin_pipe[0]);
                os.close(stdin_pipe[1]);
            }
            if (self.stdout_behavior == .Pipe) {
                os.close(stdout_pipe[0]);
                os.close(stdout_pipe[1]);
            }
            if (self.stderr_behavior == .Pipe) {
                os.close(stderr_pipe[0]);
                os.close(stderr_pipe[1]);
            }

            if (self.cwd) |cwd| {
                os.chdir(cwd) catch |err| forkChildErrReport(err_pipe[1], err);
            }

            if (self.gid) |gid| {
                os.setregid(gid, gid) catch |err| forkChildErrReport(err_pipe[1], err);
            }

            if (self.uid) |uid| {
                os.setreuid(uid, uid) catch |err| forkChildErrReport(err_pipe[1], err);
            }

            os.execve(self.allocator, self.argv, env_map) catch |err| forkChildErrReport(err_pipe[1], err);
        }

        // we are the parent
        const pid = @intCast(i32, pid_result);
        if (self.stdin_behavior == StdIo.Pipe) {
            self.stdin = File.openHandle(stdin_pipe[1]);
        } else {
            self.stdin = null;
        }
        if (self.stdout_behavior == StdIo.Pipe) {
            self.stdout = File.openHandle(stdout_pipe[0]);
        } else {
            self.stdout = null;
        }
        if (self.stderr_behavior == StdIo.Pipe) {
            self.stderr = File.openHandle(stderr_pipe[0]);
        } else {
            self.stderr = null;
        }

        self.pid = pid;
        self.err_pipe = err_pipe;
        self.llnode = TailQueue(*ChildProcess).Node.init(self);
        self.term = null;

        if (self.stdin_behavior == StdIo.Pipe) {
            os.close(stdin_pipe[0]);
        }
        if (self.stdout_behavior == StdIo.Pipe) {
            os.close(stdout_pipe[1]);
        }
        if (self.stderr_behavior == StdIo.Pipe) {
            os.close(stderr_pipe[1]);
        }
    }

    fn spawnWindows(self: *ChildProcess) !void {
        const saAttr = windows.SECURITY_ATTRIBUTES{
            .nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
            .bInheritHandle = windows.TRUE,
            .lpSecurityDescriptor = null,
        };

        const any_ignore = (self.stdin_behavior == StdIo.Ignore or self.stdout_behavior == StdIo.Ignore or self.stderr_behavior == StdIo.Ignore);

        const nul_handle = if (any_ignore) blk: {
            break :blk try windows.CreateFile("NUL", windows.GENERIC_READ, windows.FILE_SHARE_READ, null, windows.OPEN_EXISTING, windows.FILE_ATTRIBUTE_NORMAL, null);
        } else blk: {
            break :blk undefined;
        };
        defer {
            if (any_ignore) os.close(nul_handle);
        }
        if (any_ignore) {
            try windows.SetHandleInformation(nul_handle, windows.HANDLE_FLAG_INHERIT, 0);
        }

        var g_hChildStd_IN_Rd: ?windows.HANDLE = null;
        var g_hChildStd_IN_Wr: ?windows.HANDLE = null;
        switch (self.stdin_behavior) {
            StdIo.Pipe => {
                try windowsMakePipeIn(&g_hChildStd_IN_Rd, &g_hChildStd_IN_Wr, &saAttr);
            },
            StdIo.Ignore => {
                g_hChildStd_IN_Rd = nul_handle;
            },
            StdIo.Inherit => {
                g_hChildStd_IN_Rd = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch null;
            },
            StdIo.Close => {
                g_hChildStd_IN_Rd = null;
            },
        }
        errdefer if (self.stdin_behavior == StdIo.Pipe) {
            windowsDestroyPipe(g_hChildStd_IN_Rd, g_hChildStd_IN_Wr);
        };

        var g_hChildStd_OUT_Rd: ?windows.HANDLE = null;
        var g_hChildStd_OUT_Wr: ?windows.HANDLE = null;
        switch (self.stdout_behavior) {
            StdIo.Pipe => {
                try windowsMakePipeOut(&g_hChildStd_OUT_Rd, &g_hChildStd_OUT_Wr, &saAttr);
            },
            StdIo.Ignore => {
                g_hChildStd_OUT_Wr = nul_handle;
            },
            StdIo.Inherit => {
                g_hChildStd_OUT_Wr = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch null;
            },
            StdIo.Close => {
                g_hChildStd_OUT_Wr = null;
            },
        }
        errdefer if (self.stdin_behavior == StdIo.Pipe) {
            windowsDestroyPipe(g_hChildStd_OUT_Rd, g_hChildStd_OUT_Wr);
        };

        var g_hChildStd_ERR_Rd: ?windows.HANDLE = null;
        var g_hChildStd_ERR_Wr: ?windows.HANDLE = null;
        switch (self.stderr_behavior) {
            StdIo.Pipe => {
                try windowsMakePipeOut(&g_hChildStd_ERR_Rd, &g_hChildStd_ERR_Wr, &saAttr);
            },
            StdIo.Ignore => {
                g_hChildStd_ERR_Wr = nul_handle;
            },
            StdIo.Inherit => {
                g_hChildStd_ERR_Wr = windows.GetStdHandle(windows.STD_ERROR_HANDLE) catch null;
            },
            StdIo.Close => {
                g_hChildStd_ERR_Wr = null;
            },
        }
        errdefer if (self.stdin_behavior == StdIo.Pipe) {
            windowsDestroyPipe(g_hChildStd_ERR_Rd, g_hChildStd_ERR_Wr);
        };

        const cmd_line = try windowsCreateCommandLine(self.allocator, self.argv);
        defer self.allocator.free(cmd_line);

        var siStartInfo = windows.STARTUPINFOW{
            .cb = @sizeOf(windows.STARTUPINFOW),
            .hStdError = g_hChildStd_ERR_Wr,
            .hStdOutput = g_hChildStd_OUT_Wr,
            .hStdInput = g_hChildStd_IN_Rd,
            .dwFlags = windows.STARTF_USESTDHANDLES,

            .lpReserved = null,
            .lpDesktop = null,
            .lpTitle = null,
            .dwX = 0,
            .dwY = 0,
            .dwXSize = 0,
            .dwYSize = 0,
            .dwXCountChars = 0,
            .dwYCountChars = 0,
            .dwFillAttribute = 0,
            .wShowWindow = 0,
            .cbReserved2 = 0,
            .lpReserved2 = null,
        };
        var piProcInfo: windows.PROCESS_INFORMATION = undefined;

        const cwd_slice = if (self.cwd) |cwd| try cstr.addNullByte(self.allocator, cwd) else null;
        defer if (cwd_slice) |cwd| self.allocator.free(cwd);
        const cwd_w = if (cwd_slice) |cwd| try unicode.utf8ToUtf16LeWithNull(self.allocator, cwd) else null;
        defer if (cwd_w) |cwd| self.allocator.free(cwd);
        const cwd_w_ptr = if (cwd_w) |cwd| cwd.ptr else null;

        const maybe_envp_buf = if (self.env_map) |env_map| try createWindowsEnvBlock(self.allocator, env_map) else null;
        defer if (maybe_envp_buf) |envp_buf| self.allocator.free(envp_buf);
        const envp_ptr = if (maybe_envp_buf) |envp_buf| envp_buf.ptr else null;

        // the cwd set in ChildProcess is in effect when choosing the executable path
        // to match posix semantics
        const app_name = x: {
            if (self.cwd) |cwd| {
                const resolved = try fs.path.resolve(self.allocator, [_][]const u8{ cwd, self.argv[0] });
                defer self.allocator.free(resolved);
                break :x try cstr.addNullByte(self.allocator, resolved);
            } else {
                break :x try cstr.addNullByte(self.allocator, self.argv[0]);
            }
        };
        defer self.allocator.free(app_name);

        const app_name_w = try unicode.utf8ToUtf16LeWithNull(self.allocator, app_name);
        defer self.allocator.free(app_name_w);

        const cmd_line_w = try unicode.utf8ToUtf16LeWithNull(self.allocator, cmd_line);
        defer self.allocator.free(cmd_line_w);

        windowsCreateProcess(app_name_w.ptr, cmd_line_w.ptr, envp_ptr, cwd_w_ptr, &siStartInfo, &piProcInfo) catch |no_path_err| {
            if (no_path_err != error.FileNotFound) return no_path_err;

            const PATH = try process.getEnvVarOwned(self.allocator, "PATH");
            defer self.allocator.free(PATH);
            const PATHEXT = try process.getEnvVarOwned(self.allocator, "PATHEXT");
            defer self.allocator.free(PATHEXT);

            var it = mem.tokenize(PATH, ";");
            retry: while (it.next()) |search_path| {
                var ext_it = mem.tokenize(PATHEXT, ";");
                while (ext_it.next()) |app_ext| {
                    const app_basename = try mem.concat(self.allocator, u8, [_][]const u8{ app_name[0 .. app_name.len - 1], app_ext });
                    defer self.allocator.free(app_basename);

                    const joined_path = try fs.path.join(self.allocator, [_][]const u8{ search_path, app_basename });
                    defer self.allocator.free(joined_path);

                    const joined_path_w = try unicode.utf8ToUtf16LeWithNull(self.allocator, joined_path);
                    defer self.allocator.free(joined_path_w);

                    if (windowsCreateProcess(joined_path_w.ptr, cmd_line_w.ptr, envp_ptr, cwd_w_ptr, &siStartInfo, &piProcInfo)) |_| {
                        break :retry;
                    } else |err| switch (err) {
                        error.FileNotFound => continue,
                        error.AccessDenied => continue,
                        else => return err,
                    }
                }
            } else {
                return no_path_err; // return the original error
            }
        };

        if (g_hChildStd_IN_Wr) |h| {
            self.stdin = File.openHandle(h);
        } else {
            self.stdin = null;
        }
        if (g_hChildStd_OUT_Rd) |h| {
            self.stdout = File.openHandle(h);
        } else {
            self.stdout = null;
        }
        if (g_hChildStd_ERR_Rd) |h| {
            self.stderr = File.openHandle(h);
        } else {
            self.stderr = null;
        }

        self.handle = piProcInfo.hProcess;
        self.thread_handle = piProcInfo.hThread;
        self.term = null;

        if (self.stdin_behavior == StdIo.Pipe) {
            os.close(g_hChildStd_IN_Rd.?);
        }
        if (self.stderr_behavior == StdIo.Pipe) {
            os.close(g_hChildStd_ERR_Wr.?);
        }
        if (self.stdout_behavior == StdIo.Pipe) {
            os.close(g_hChildStd_OUT_Wr.?);
        }
    }

    fn setUpChildIo(stdio: StdIo, pipe_fd: i32, std_fileno: i32, dev_null_fd: i32) !void {
        switch (stdio) {
            StdIo.Pipe => try os.dup2(pipe_fd, std_fileno),
            StdIo.Close => os.close(std_fileno),
            StdIo.Inherit => {},
            StdIo.Ignore => try os.dup2(dev_null_fd, std_fileno),
        }
    }
};

fn windowsCreateProcess(app_name: [*]u16, cmd_line: [*]u16, envp_ptr: ?[*]u16, cwd_ptr: ?[*]u16, lpStartupInfo: *windows.STARTUPINFOW, lpProcessInformation: *windows.PROCESS_INFORMATION) !void {
    // TODO the docs for environment pointer say:
    // > A pointer to the environment block for the new process. If this parameter
    // > is NULL, the new process uses the environment of the calling process.
    // > ...
    // > An environment block can contain either Unicode or ANSI characters. If
    // > the environment block pointed to by lpEnvironment contains Unicode
    // > characters, be sure that dwCreationFlags includes CREATE_UNICODE_ENVIRONMENT.
    // > If this parameter is NULL and the environment block of the parent process
    // > contains Unicode characters, you must also ensure that dwCreationFlags
    // > includes CREATE_UNICODE_ENVIRONMENT.
    // This seems to imply that we have to somehow know whether our process parent passed
    // CREATE_UNICODE_ENVIRONMENT if we want to pass NULL for the environment parameter.
    // Since we do not know this information that would imply that we must not pass NULL
    // for the parameter.
    // However this would imply that programs compiled with -DUNICODE could not pass
    // environment variables to programs that were not, which seems unlikely.
    // More investigation is needed.
    return windows.CreateProcessW(
        app_name,
        cmd_line,
        null,
        null,
        windows.TRUE,
        windows.CREATE_UNICODE_ENVIRONMENT,
        @ptrCast(?*c_void, envp_ptr),
        cwd_ptr,
        lpStartupInfo,
        lpProcessInformation,
    );
}

/// Caller must dealloc.
/// Guarantees a null byte at result[result.len].
fn windowsCreateCommandLine(allocator: *mem.Allocator, argv: []const []const u8) ![]u8 {
    var buf = try Buffer.initSize(allocator, 0);
    defer buf.deinit();

    var buf_stream = &io.BufferOutStream.init(&buf).stream;

    for (argv) |arg, arg_i| {
        if (arg_i != 0) try buf.appendByte(' ');
        if (mem.indexOfAny(u8, arg, " \t\n\"") == null) {
            try buf.append(arg);
            continue;
        }
        try buf.appendByte('"');
        var backslash_count: usize = 0;
        for (arg) |byte| {
            switch (byte) {
                '\\' => backslash_count += 1,
                '"' => {
                    try buf_stream.writeByteNTimes('\\', backslash_count * 2 + 1);
                    try buf.appendByte('"');
                    backslash_count = 0;
                },
                else => {
                    try buf_stream.writeByteNTimes('\\', backslash_count);
                    try buf.appendByte(byte);
                    backslash_count = 0;
                },
            }
        }
        try buf_stream.writeByteNTimes('\\', backslash_count * 2);
        try buf.appendByte('"');
    }

    return buf.toOwnedSlice();
}

fn windowsDestroyPipe(rd: ?windows.HANDLE, wr: ?windows.HANDLE) void {
    if (rd) |h| os.close(h);
    if (wr) |h| os.close(h);
}

fn windowsMakePipeIn(rd: *?windows.HANDLE, wr: *?windows.HANDLE, sattr: *const windows.SECURITY_ATTRIBUTES) !void {
    var rd_h: windows.HANDLE = undefined;
    var wr_h: windows.HANDLE = undefined;
    try windows.CreatePipe(&rd_h, &wr_h, sattr);
    errdefer windowsDestroyPipe(rd_h, wr_h);
    try windows.SetHandleInformation(wr_h, windows.HANDLE_FLAG_INHERIT, 0);
    rd.* = rd_h;
    wr.* = wr_h;
}

fn windowsMakePipeOut(rd: *?windows.HANDLE, wr: *?windows.HANDLE, sattr: *const windows.SECURITY_ATTRIBUTES) !void {
    var rd_h: windows.HANDLE = undefined;
    var wr_h: windows.HANDLE = undefined;
    try windows.CreatePipe(&rd_h, &wr_h, sattr);
    errdefer windowsDestroyPipe(rd_h, wr_h);
    try windows.SetHandleInformation(rd_h, windows.HANDLE_FLAG_INHERIT, 0);
    rd.* = rd_h;
    wr.* = wr_h;
}

fn destroyPipe(pipe: [2]os.fd_t) void {
    os.close(pipe[0]);
    os.close(pipe[1]);
}

// Child of fork calls this to report an error to the fork parent.
// Then the child exits.
fn forkChildErrReport(fd: i32, err: ChildProcess.SpawnError) noreturn {
    writeIntFd(fd, ErrInt(@errorToInt(err))) catch {};
    os.exit(1);
}

const ErrInt = @IntType(false, @sizeOf(anyerror) * 8);

fn writeIntFd(fd: i32, value: ErrInt) !void {
    const stream = &File.openHandle(fd).outStream().stream;
    stream.writeIntNative(ErrInt, value) catch return error.SystemResources;
}

fn readIntFd(fd: i32) !ErrInt {
    const stream = &File.openHandle(fd).inStream().stream;
    return stream.readIntNative(ErrInt) catch return error.SystemResources;
}

/// Caller must free result.
pub fn createWindowsEnvBlock(allocator: *mem.Allocator, env_map: *const BufMap) ![]u16 {
    // count bytes needed
    const max_chars_needed = x: {
        var max_chars_needed: usize = 4; // 4 for the final 4 null bytes
        var it = env_map.iterator();
        while (it.next()) |pair| {
            // +1 for '='
            // +1 for null byte
            max_chars_needed += pair.key.len + pair.value.len + 2;
        }
        break :x max_chars_needed;
    };
    const result = try allocator.alloc(u16, max_chars_needed);
    errdefer allocator.free(result);

    var it = env_map.iterator();
    var i: usize = 0;
    while (it.next()) |pair| {
        i += try unicode.utf8ToUtf16Le(result[i..], pair.key);
        result[i] = '=';
        i += 1;
        i += try unicode.utf8ToUtf16Le(result[i..], pair.value);
        result[i] = 0;
        i += 1;
    }
    result[i] = 0;
    i += 1;
    result[i] = 0;
    i += 1;
    result[i] = 0;
    i += 1;
    result[i] = 0;
    i += 1;
    return allocator.shrink(result, i);
}

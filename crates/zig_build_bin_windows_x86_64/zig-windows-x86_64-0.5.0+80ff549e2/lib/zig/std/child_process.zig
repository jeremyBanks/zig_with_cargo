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
    pid: if (builtin.os.tag == .windows) void else i32,
    handle: if (builtin.os.tag == .windows) windows.HANDLE else void,
    thread_handle: if (builtin.os.tag == .windows) windows.HANDLE else void,

    allocator: *mem.Allocator,

    stdin: ?File,
    stdout: ?File,
    stderr: ?File,

    term: ?(SpawnError!Term),

    argv: []const []const u8,

    /// Leave as null to use the current env map using the supplied allocator.
    env_map: ?*const BufMap,

    stdin_behavior: StdIo,
    stdout_behavior: StdIo,
    stderr_behavior: StdIo,

    /// Set to change the user id when spawning the child process.
    uid: if (builtin.os.tag == .windows) void else ?u32,

    /// Set to change the group id when spawning the child process.
    gid: if (builtin.os.tag == .windows) void else ?u32,

    /// Set to change the current working directory when spawning the child process.
    cwd: ?[]const u8,

    err_pipe: if (builtin.os.tag == .windows) void else [2]os.fd_t,

    expand_arg0: Arg0Expand,

    pub const Arg0Expand = os.Arg0Expand;

    pub const SpawnError = error{
        OutOfMemory,

        /// POSIX-only. `StdIo.Ignore` was selected and opening `/dev/null` returned ENODEV.
        NoDevice,

        /// Windows-only. One of:
        /// * `cwd` was provided and it could not be re-encoded into UTF16LE, or
        /// * The `PATH` or `PATHEXT` environment variable contained invalid UTF-8.
        InvalidUtf8,

        /// Windows-only. `cwd` was provided, but the path did not exist when spawning the child process.
        CurrentWorkingDirectoryUnlinked,
    } || os.ExecveError || os.SetIdError || os.ChangeCurDirError || windows.CreateProcessError || windows.WaitForSingleObjectError;

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
            .term = null,
            .env_map = null,
            .cwd = null,
            .uid = if (builtin.os.tag == .windows) {} else null,
            .gid = if (builtin.os.tag == .windows) {} else null,
            .stdin = null,
            .stdout = null,
            .stderr = null,
            .stdin_behavior = StdIo.Inherit,
            .stdout_behavior = StdIo.Inherit,
            .stderr_behavior = StdIo.Inherit,
            .expand_arg0 = .no_expand,
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
    pub fn spawn(self: *ChildProcess) SpawnError!void {
        if (builtin.os.tag == .windows) {
            return self.spawnWindows();
        } else {
            return self.spawnPosix();
        }
    }

    pub fn spawnAndWait(self: *ChildProcess) SpawnError!Term {
        try self.spawn();
        return self.wait();
    }

    /// Forcibly terminates child process and then cleans up all resources.
    pub fn kill(self: *ChildProcess) !Term {
        if (builtin.os.tag == .windows) {
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
        if (builtin.os.tag == .windows) {
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
    /// TODO deprecate in favor of exec2
    pub fn exec(
        allocator: *mem.Allocator,
        argv: []const []const u8,
        cwd: ?[]const u8,
        env_map: ?*const BufMap,
        max_output_bytes: usize,
    ) !ExecResult {
        return exec2(.{
            .allocator = allocator,
            .argv = argv,
            .cwd = cwd,
            .env_map = env_map,
            .max_output_bytes = max_output_bytes,
        });
    }

    /// Spawns a child process, waits for it, collecting stdout and stderr, and then returns.
    /// If it succeeds, the caller owns result.stdout and result.stderr memory.
    /// TODO rename to exec
    pub fn exec2(args: struct {
        allocator: *mem.Allocator,
        argv: []const []const u8,
        cwd: ?[]const u8 = null,
        env_map: ?*const BufMap = null,
        max_output_bytes: usize = 50 * 1024,
        expand_arg0: Arg0Expand = .no_expand,
    }) !ExecResult {
        const child = try ChildProcess.init(args.argv, args.allocator);
        defer child.deinit();

        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.cwd = args.cwd;
        child.env_map = args.env_map;
        child.expand_arg0 = args.expand_arg0;

        try child.spawn();

        var stdout_file_in_stream = child.stdout.?.inStream();
        var stderr_file_in_stream = child.stderr.?.inStream();

        // TODO need to poll to read these streams to prevent a deadlock (or rely on evented I/O).
        const stdout = try stdout_file_in_stream.stream.readAllAlloc(args.allocator, args.max_output_bytes);
        errdefer args.allocator.free(stdout);
        const stderr = try stderr_file_in_stream.stream.readAllAlloc(args.allocator, args.max_output_bytes);
        errdefer args.allocator.free(stderr);

        return ExecResult{
            .term = try child.wait(),
            .stdout = stdout,
            .stderr = stderr,
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
        const result = windows.WaitForSingleObjectEx(self.handle, windows.INFINITE, false);

        self.term = @as(SpawnError!Term, x: {
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
        // TODO https://github.com/ziglang/zig/issues/3190
        var term = self.cleanupAfterWait(status);
        self.term = term;
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
        defer destroyPipe(self.err_pipe);

        if (builtin.os.tag == .linux) {
            var fd = [1]std.os.pollfd{std.os.pollfd{
                .fd = self.err_pipe[0],
                .events = std.os.POLLIN,
                .revents = undefined,
            }};

            // Check if the eventfd buffer stores a non-zero value by polling
            // it, that's the error code returned by the child process.
            _ = std.os.poll(&fd, 0) catch unreachable;

            // According to eventfd(2) the descriptro is readable if the counter
            // has a value greater than 0
            if ((fd[0].revents & std.os.POLLIN) != 0) {
                const err_int = try readIntFd(self.err_pipe[0]);
                return @errSetCast(SpawnError, @intToError(err_int));
            }
        } else {
            // Write maxInt(ErrInt) to the write end of the err_pipe. This is after
            // waitpid, so this write is guaranteed to be after the child
            // pid potentially wrote an error. This way we can do a blocking
            // read on the error pipe and either get maxInt(ErrInt) (no error) or
            // an error code.
            try writeIntFd(self.err_pipe[1], maxInt(ErrInt));
            const err_int = try readIntFd(self.err_pipe[0]);
            // Here we potentially return the fork child's error from the parent
            // pid.
            if (err_int != maxInt(ErrInt)) {
                return @errSetCast(SpawnError, @intToError(err_int));
            }
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

    fn spawnPosix(self: *ChildProcess) SpawnError!void {
        const pipe_flags = if (io.is_async) os.O_NONBLOCK else 0;
        const stdin_pipe = if (self.stdin_behavior == StdIo.Pipe) try os.pipe2(pipe_flags) else undefined;
        errdefer if (self.stdin_behavior == StdIo.Pipe) {
            destroyPipe(stdin_pipe);
        };

        const stdout_pipe = if (self.stdout_behavior == StdIo.Pipe) try os.pipe2(pipe_flags) else undefined;
        errdefer if (self.stdout_behavior == StdIo.Pipe) {
            destroyPipe(stdout_pipe);
        };

        const stderr_pipe = if (self.stderr_behavior == StdIo.Pipe) try os.pipe2(pipe_flags) else undefined;
        errdefer if (self.stderr_behavior == StdIo.Pipe) {
            destroyPipe(stderr_pipe);
        };

        const any_ignore = (self.stdin_behavior == StdIo.Ignore or self.stdout_behavior == StdIo.Ignore or self.stderr_behavior == StdIo.Ignore);
        const dev_null_fd = if (any_ignore)
            os.openC("/dev/null", os.O_RDWR, 0) catch |err| switch (err) {
                error.PathAlreadyExists => unreachable,
                error.NoSpaceLeft => unreachable,
                error.FileTooBig => unreachable,
                error.DeviceBusy => unreachable,
                else => |e| return e,
            }
        else
            undefined;
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
        const err_pipe = blk: {
            if (builtin.os.tag == .linux) {
                const fd = try os.eventfd(0, 0);
                // There's no distinction between the readable and the writeable
                // end with eventfd
                break :blk [2]os.fd_t{ fd, fd };
            } else {
                break :blk try os.pipe();
            }
        };
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

            const err = os.execvpe_expandArg0(self.allocator, self.expand_arg0, self.argv, env_map);
            forkChildErrReport(err_pipe[1], err);
        }

        // we are the parent
        const pid = @intCast(i32, pid_result);
        if (self.stdin_behavior == StdIo.Pipe) {
            self.stdin = File{
                .handle = stdin_pipe[1],
                .io_mode = std.io.mode,
            };
        } else {
            self.stdin = null;
        }
        if (self.stdout_behavior == StdIo.Pipe) {
            self.stdout = File{
                .handle = stdout_pipe[0],
                .io_mode = std.io.mode,
            };
        } else {
            self.stdout = null;
        }
        if (self.stderr_behavior == StdIo.Pipe) {
            self.stderr = File{
                .handle = stderr_pipe[0],
                .io_mode = std.io.mode,
            };
        } else {
            self.stderr = null;
        }

        self.pid = pid;
        self.err_pipe = err_pipe;
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

    fn spawnWindows(self: *ChildProcess) SpawnError!void {
        const saAttr = windows.SECURITY_ATTRIBUTES{
            .nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
            .bInheritHandle = windows.TRUE,
            .lpSecurityDescriptor = null,
        };

        const any_ignore = (self.stdin_behavior == StdIo.Ignore or self.stdout_behavior == StdIo.Ignore or self.stderr_behavior == StdIo.Ignore);

        // TODO use CreateFileW here since we are using a string literal for the path
        const nul_handle = if (any_ignore)
            windows.CreateFile(
                "NUL",
                windows.GENERIC_READ,
                windows.FILE_SHARE_READ,
                null,
                windows.OPEN_EXISTING,
                windows.FILE_ATTRIBUTE_NORMAL,
                null,
            ) catch |err| switch (err) {
                error.SharingViolation => unreachable, // not possible for "NUL"
                error.PathAlreadyExists => unreachable, // not possible for "NUL"
                error.PipeBusy => unreachable, // not possible for "NUL"
                error.InvalidUtf8 => unreachable, // not possible for "NUL"
                error.BadPathName => unreachable, // not possible for "NUL"
                error.FileNotFound => unreachable, // not possible for "NUL"
                error.AccessDenied => unreachable, // not possible for "NUL"
                error.NameTooLong => unreachable, // not possible for "NUL"
                else => |e| return e,
            }
        else
            undefined;
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

        const cwd_w = if (self.cwd) |cwd| try unicode.utf8ToUtf16LeWithNull(self.allocator, cwd) else null;
        defer if (cwd_w) |cwd| self.allocator.free(cwd);
        const cwd_w_ptr = if (cwd_w) |cwd| cwd.ptr else null;

        const maybe_envp_buf = if (self.env_map) |env_map| try createWindowsEnvBlock(self.allocator, env_map) else null;
        defer if (maybe_envp_buf) |envp_buf| self.allocator.free(envp_buf);
        const envp_ptr = if (maybe_envp_buf) |envp_buf| envp_buf.ptr else null;

        // the cwd set in ChildProcess is in effect when choosing the executable path
        // to match posix semantics
        const app_path = x: {
            if (self.cwd) |cwd| {
                const resolved = try fs.path.resolve(self.allocator, &[_][]const u8{ cwd, self.argv[0] });
                defer self.allocator.free(resolved);
                break :x try cstr.addNullByte(self.allocator, resolved);
            } else {
                break :x try cstr.addNullByte(self.allocator, self.argv[0]);
            }
        };
        defer self.allocator.free(app_path);

        const app_path_w = try unicode.utf8ToUtf16LeWithNull(self.allocator, app_path);
        defer self.allocator.free(app_path_w);

        const cmd_line_w = try unicode.utf8ToUtf16LeWithNull(self.allocator, cmd_line);
        defer self.allocator.free(cmd_line_w);

        windowsCreateProcess(app_path_w.ptr, cmd_line_w.ptr, envp_ptr, cwd_w_ptr, &siStartInfo, &piProcInfo) catch |no_path_err| {
            if (no_path_err != error.FileNotFound) return no_path_err;

            var free_path = true;
            const PATH = process.getEnvVarOwned(self.allocator, "PATH") catch |err| switch (err) {
                error.EnvironmentVariableNotFound => blk: {
                    free_path = false;
                    break :blk "";
                },
                else => |e| return e,
            };
            defer if (free_path) self.allocator.free(PATH);

            var free_path_ext = true;
            const PATHEXT = process.getEnvVarOwned(self.allocator, "PATHEXT") catch |err| switch (err) {
                error.EnvironmentVariableNotFound => blk: {
                    free_path_ext = false;
                    break :blk "";
                },
                else => |e| return e,
            };
            defer if (free_path_ext) self.allocator.free(PATHEXT);

            const app_name = self.argv[0];

            var it = mem.tokenize(PATH, ";");
            retry: while (it.next()) |search_path| {
                const path_no_ext = try fs.path.join(self.allocator, &[_][]const u8{ search_path, app_name });
                defer self.allocator.free(path_no_ext);

                var ext_it = mem.tokenize(PATHEXT, ";");
                while (ext_it.next()) |app_ext| {
                    const joined_path = try mem.concat(self.allocator, u8, &[_][]const u8{ path_no_ext, app_ext });
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
            self.stdin = File{
                .handle = h,
                .io_mode = io.mode,
            };
        } else {
            self.stdin = null;
        }
        if (g_hChildStd_OUT_Rd) |h| {
            self.stdout = File{
                .handle = h,
                .io_mode = io.mode,
            };
        } else {
            self.stdout = null;
        }
        if (g_hChildStd_ERR_Rd) |h| {
            self.stderr = File{
                .handle = h,
                .io_mode = io.mode,
            };
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
            .Pipe => try os.dup2(pipe_fd, std_fileno),
            .Close => os.close(std_fileno),
            .Inherit => {},
            .Ignore => try os.dup2(dev_null_fd, std_fileno),
        }
    }
};

fn windowsCreateProcess(app_name: [*:0]u16, cmd_line: [*:0]u16, envp_ptr: ?[*]u16, cwd_ptr: ?[*:0]u16, lpStartupInfo: *windows.STARTUPINFOW, lpProcessInformation: *windows.PROCESS_INFORMATION) !void {
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
    if (pipe[0] != pipe[1]) os.close(pipe[1]);
}

// Child of fork calls this to report an error to the fork parent.
// Then the child exits.
fn forkChildErrReport(fd: i32, err: ChildProcess.SpawnError) noreturn {
    writeIntFd(fd, @as(ErrInt, @errorToInt(err))) catch {};
    os.exit(1);
}

const ErrInt = std.meta.IntType(false, @sizeOf(anyerror) * 8);

fn writeIntFd(fd: i32, value: ErrInt) !void {
    const file = File{
        .handle = fd,
        .io_mode = .blocking,
        .async_block_allowed = File.async_block_allowed_yes,
    };
    const stream = &file.outStream().stream;
    stream.writeIntNative(u64, @intCast(u64, value)) catch return error.SystemResources;
}

fn readIntFd(fd: i32) !ErrInt {
    const file = File{
        .handle = fd,
        .io_mode = .blocking,
        .async_block_allowed = File.async_block_allowed_yes,
    };
    const stream = &file.inStream().stream;
    return @intCast(ErrInt, stream.readIntNative(u64) catch return error.SystemResources);
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

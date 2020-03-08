const std = @import("../std.zig");
const builtin = std.builtin;
const build = std.build;
const Step = build.Step;
const Builder = build.Builder;
const LibExeObjStep = build.LibExeObjStep;
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const ArrayList = std.ArrayList;
const BufMap = std.BufMap;
const warn = std.debug.warn;

const max_stdout_size = 1 * 1024 * 1024; // 1 MiB

pub const RunStep = struct {
    step: Step,
    builder: *Builder,

    /// See also addArg and addArgs to modifying this directly
    argv: ArrayList(Arg),

    /// Set this to modify the current working directory
    cwd: ?[]const u8,

    /// Override this field to modify the environment, or use setEnvironmentVariable
    env_map: ?*BufMap,

    stdout_action: StdIoAction = .inherit,
    stderr_action: StdIoAction = .inherit,

    expected_exit_code: u8 = 0,

    pub const StdIoAction = union(enum) {
        inherit,
        ignore,
        expect_exact: []const u8,
        expect_matches: []const []const u8,
    };

    pub const Arg = union(enum) {
        Artifact: *LibExeObjStep,
        Bytes: []u8,
    };

    pub fn create(builder: *Builder, name: []const u8) *RunStep {
        const self = builder.allocator.create(RunStep) catch unreachable;
        self.* = RunStep{
            .builder = builder,
            .step = Step.init(name, builder.allocator, make),
            .argv = ArrayList(Arg).init(builder.allocator),
            .cwd = null,
            .env_map = null,
        };
        return self;
    }

    pub fn addArtifactArg(self: *RunStep, artifact: *LibExeObjStep) void {
        self.argv.append(Arg{ .Artifact = artifact }) catch unreachable;
        self.step.dependOn(&artifact.step);
    }

    pub fn addArg(self: *RunStep, arg: []const u8) void {
        self.argv.append(Arg{ .Bytes = self.builder.dupe(arg) }) catch unreachable;
    }

    pub fn addArgs(self: *RunStep, args: []const []const u8) void {
        for (args) |arg| {
            self.addArg(arg);
        }
    }

    pub fn clearEnvironment(self: *RunStep) void {
        const new_env_map = self.builder.allocator.create(BufMap) catch unreachable;
        new_env_map.* = BufMap.init(self.builder.allocator);
        self.env_map = new_env_map;
    }

    pub fn addPathDir(self: *RunStep, search_path: []const u8) void {
        const env_map = self.getEnvMap();

        var key: []const u8 = undefined;
        var prev_path: ?[]const u8 = undefined;
        if (builtin.os.tag == .windows) {
            key = "Path";
            prev_path = env_map.get(key);
            if (prev_path == null) {
                key = "PATH";
                prev_path = env_map.get(key);
            }
        } else {
            key = "PATH";
            prev_path = env_map.get(key);
        }

        if (prev_path) |pp| {
            const new_path = self.builder.fmt("{}" ++ [1]u8{fs.path.delimiter} ++ "{}", .{ pp, search_path });
            env_map.set(key, new_path) catch unreachable;
        } else {
            env_map.set(key, search_path) catch unreachable;
        }
    }

    pub fn getEnvMap(self: *RunStep) *BufMap {
        return self.env_map orelse {
            const env_map = self.builder.allocator.create(BufMap) catch unreachable;
            env_map.* = process.getEnvMap(self.builder.allocator) catch unreachable;
            self.env_map = env_map;
            return env_map;
        };
    }

    pub fn setEnvironmentVariable(self: *RunStep, key: []const u8, value: []const u8) void {
        const env_map = self.getEnvMap();
        env_map.set(key, value) catch unreachable;
    }

    pub fn expectStdErrEqual(self: *RunStep, bytes: []const u8) void {
        self.stderr_action = .{ .expect_exact = bytes };
    }

    pub fn expectStdOutEqual(self: *RunStep, bytes: []const u8) void {
        self.stdout_action = .{ .expect_exact = bytes };
    }

    fn stdIoActionToBehavior(action: StdIoAction) std.ChildProcess.StdIo {
        return switch (action) {
            .ignore => .Ignore,
            .inherit => .Inherit,
            .expect_exact, .expect_matches => .Pipe,
        };
    }

    fn make(step: *Step) !void {
        const self = @fieldParentPtr(RunStep, "step", step);

        const cwd = if (self.cwd) |cwd| self.builder.pathFromRoot(cwd) else self.builder.build_root;

        var argv_list = ArrayList([]const u8).init(self.builder.allocator);
        for (self.argv.toSlice()) |arg| {
            switch (arg) {
                Arg.Bytes => |bytes| try argv_list.append(bytes),
                Arg.Artifact => |artifact| {
                    if (artifact.target.isWindows()) {
                        // On Windows we don't have rpaths so we have to add .dll search paths to PATH
                        self.addPathForDynLibs(artifact);
                    }
                    const executable_path = artifact.installed_path orelse artifact.getOutputPath();
                    try argv_list.append(executable_path);
                },
            }
        }

        const argv = argv_list.toSliceConst();

        const child = std.ChildProcess.init(argv, self.builder.allocator) catch unreachable;
        defer child.deinit();

        child.cwd = cwd;
        child.env_map = self.env_map orelse self.builder.env_map;

        child.stdin_behavior = .Ignore;
        child.stdout_behavior = stdIoActionToBehavior(self.stdout_action);
        child.stderr_behavior = stdIoActionToBehavior(self.stderr_action);

        child.spawn() catch |err| {
            warn("Unable to spawn {}: {}\n", .{ argv[0], @errorName(err) });
            return err;
        };

        // TODO need to poll to read these streams to prevent a deadlock (or rely on evented I/O).

        var stdout: ?[]const u8 = null;
        defer if (stdout) |s| self.builder.allocator.free(s);

        switch (self.stdout_action) {
            .expect_exact, .expect_matches => {
                var stdout_file_in_stream = child.stdout.?.inStream();
                stdout = stdout_file_in_stream.stream.readAllAlloc(self.builder.allocator, max_stdout_size) catch unreachable;
            },
            .inherit, .ignore => {},
        }

        var stderr: ?[]const u8 = null;
        defer if (stderr) |s| self.builder.allocator.free(s);

        switch (self.stderr_action) {
            .expect_exact, .expect_matches => {
                var stderr_file_in_stream = child.stderr.?.inStream();
                stderr = stderr_file_in_stream.stream.readAllAlloc(self.builder.allocator, max_stdout_size) catch unreachable;
            },
            .inherit, .ignore => {},
        }

        const term = child.wait() catch |err| {
            warn("Unable to spawn {}: {}\n", .{ argv[0], @errorName(err) });
            return err;
        };

        switch (term) {
            .Exited => |code| {
                if (code != self.expected_exit_code) {
                    warn("The following command exited with error code {} (expected {}):\n", .{
                        code,
                        self.expected_exit_code,
                    });
                    printCmd(cwd, argv);
                    return error.UncleanExit;
                }
            },
            else => {
                warn("The following command terminated unexpectedly:\n", .{});
                printCmd(cwd, argv);
                return error.UncleanExit;
            },
        }

        switch (self.stderr_action) {
            .inherit, .ignore => {},
            .expect_exact => |expected_bytes| {
                if (!mem.eql(u8, expected_bytes, stderr.?)) {
                    warn(
                        \\
                        \\========= Expected this stderr: =========
                        \\{}
                        \\========= But found: ====================
                        \\{}
                        \\
                    , .{ expected_bytes, stderr.? });
                    printCmd(cwd, argv);
                    return error.TestFailed;
                }
            },
            .expect_matches => |matches| for (matches) |match| {
                if (mem.indexOf(u8, stderr.?, match) == null) {
                    warn(
                        \\
                        \\========= Expected to find in stderr: =========
                        \\{}
                        \\========= But stderr does not contain it: =====
                        \\{}
                        \\
                    , .{ match, stderr.? });
                    printCmd(cwd, argv);
                    return error.TestFailed;
                }
            },
        }

        switch (self.stdout_action) {
            .inherit, .ignore => {},
            .expect_exact => |expected_bytes| {
                if (!mem.eql(u8, expected_bytes, stdout.?)) {
                    warn(
                        \\
                        \\========= Expected this stdout: =========
                        \\{}
                        \\========= But found: ====================
                        \\{}
                        \\
                    , .{ expected_bytes, stdout.? });
                    printCmd(cwd, argv);
                    return error.TestFailed;
                }
            },
            .expect_matches => |matches| for (matches) |match| {
                if (mem.indexOf(u8, stdout.?, match) == null) {
                    warn(
                        \\
                        \\========= Expected to find in stdout: =========
                        \\{}
                        \\========= But stdout does not contain it: =====
                        \\{}
                        \\
                    , .{ match, stdout.? });
                    printCmd(cwd, argv);
                    return error.TestFailed;
                }
            },
        }
    }

    fn printCmd(cwd: ?[]const u8, argv: []const []const u8) void {
        if (cwd) |yes_cwd| warn("cd {} && ", .{yes_cwd});
        for (argv) |arg| {
            warn("{} ", .{arg});
        }
        warn("\n", .{});
    }

    fn addPathForDynLibs(self: *RunStep, artifact: *LibExeObjStep) void {
        for (artifact.link_objects.toSliceConst()) |link_object| {
            switch (link_object) {
                .OtherStep => |other| {
                    if (other.target.isWindows() and other.isDynamicLibrary()) {
                        self.addPathDir(fs.path.dirname(other.getOutputPath()).?);
                        self.addPathForDynLibs(other);
                    }
                },
                else => {},
            }
        }
    }
};

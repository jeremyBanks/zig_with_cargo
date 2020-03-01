const root = @import("@build");
const std = @import("std");
const builtin = @import("builtin");
const io = std.io;
const fmt = std.fmt;
const Builder = std.build.Builder;
const mem = std.mem;
const process = std.process;
const ArrayList = std.ArrayList;
const warn = std.debug.warn;
const File = std.fs.File;

pub fn main() !void {
    var arg_it = process.args();

    // Here we use an ArenaAllocator backed by a DirectAllocator because a build is a short-lived,
    // one shot program. We don't need to waste time freeing memory and finding places to squish
    // bytes into. So we free everything all at once at the very end.

    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    // skip my own exe name
    _ = arg_it.skip();

    const zig_exe = try unwrapArg(arg_it.next(allocator) orelse {
        warn("Expected first argument to be path to zig compiler\n");
        return error.InvalidArgs;
    });
    const build_root = try unwrapArg(arg_it.next(allocator) orelse {
        warn("Expected second argument to be build root directory path\n");
        return error.InvalidArgs;
    });
    const cache_root = try unwrapArg(arg_it.next(allocator) orelse {
        warn("Expected third argument to be cache root directory path\n");
        return error.InvalidArgs;
    });

    const builder = try Builder.create(allocator, zig_exe, build_root, cache_root);
    defer builder.destroy();

    var targets = ArrayList([]const u8).init(allocator);

    var stderr_file = io.getStdErr();
    var stderr_file_stream: File.OutStream = undefined;
    var stderr_stream = if (stderr_file) |f| x: {
        stderr_file_stream = f.outStream();
        break :x &stderr_file_stream.stream;
    } else |err| err;

    var stdout_file = io.getStdOut();
    var stdout_file_stream: File.OutStream = undefined;
    var stdout_stream = if (stdout_file) |f| x: {
        stdout_file_stream = f.outStream();
        break :x &stdout_file_stream.stream;
    } else |err| err;

    while (arg_it.next(allocator)) |err_or_arg| {
        const arg = try unwrapArg(err_or_arg);
        if (mem.startsWith(u8, arg, "-D")) {
            const option_contents = arg[2..];
            if (option_contents.len == 0) {
                warn("Expected option name after '-D'\n\n");
                return usageAndErr(builder, false, try stderr_stream);
            }
            if (mem.indexOfScalar(u8, option_contents, '=')) |name_end| {
                const option_name = option_contents[0..name_end];
                const option_value = option_contents[name_end + 1 ..];
                if (try builder.addUserInputOption(option_name, option_value))
                    return usageAndErr(builder, false, try stderr_stream);
            } else {
                if (try builder.addUserInputFlag(option_contents))
                    return usageAndErr(builder, false, try stderr_stream);
            }
        } else if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "--verbose")) {
                builder.verbose = true;
            } else if (mem.eql(u8, arg, "--help")) {
                return usage(builder, false, try stdout_stream);
            } else if (mem.eql(u8, arg, "--prefix")) {
                builder.install_prefix = try unwrapArg(arg_it.next(allocator) orelse {
                    warn("Expected argument after --prefix\n\n");
                    return usageAndErr(builder, false, try stderr_stream);
                });
            } else if (mem.eql(u8, arg, "--search-prefix")) {
                const search_prefix = try unwrapArg(arg_it.next(allocator) orelse {
                    warn("Expected argument after --search-prefix\n\n");
                    return usageAndErr(builder, false, try stderr_stream);
                });
                builder.addSearchPrefix(search_prefix);
            } else if (mem.eql(u8, arg, "--override-lib-dir")) {
                builder.override_lib_dir = try unwrapArg(arg_it.next(allocator) orelse {
                    warn("Expected argument after --override-lib-dir\n\n");
                    return usageAndErr(builder, false, try stderr_stream);
                });
            } else if (mem.eql(u8, arg, "--verbose-tokenize")) {
                builder.verbose_tokenize = true;
            } else if (mem.eql(u8, arg, "--verbose-ast")) {
                builder.verbose_ast = true;
            } else if (mem.eql(u8, arg, "--verbose-link")) {
                builder.verbose_link = true;
            } else if (mem.eql(u8, arg, "--verbose-ir")) {
                builder.verbose_ir = true;
            } else if (mem.eql(u8, arg, "--verbose-llvm-ir")) {
                builder.verbose_llvm_ir = true;
            } else if (mem.eql(u8, arg, "--verbose-cimport")) {
                builder.verbose_cimport = true;
            } else if (mem.eql(u8, arg, "--verbose-cc")) {
                builder.verbose_cc = true;
            } else {
                warn("Unrecognized argument: {}\n\n", arg);
                return usageAndErr(builder, false, try stderr_stream);
            }
        } else {
            try targets.append(arg);
        }
    }

    builder.resolveInstallPrefix();
    try runBuild(builder);

    if (builder.validateUserInputDidItFail())
        return usageAndErr(builder, true, try stderr_stream);

    builder.make(targets.toSliceConst()) catch |err| {
        switch (err) {
            error.InvalidStepName => {
                return usageAndErr(builder, true, try stderr_stream);
            },
            error.UncleanExit => process.exit(1),
            else => return err,
        }
    };
}

fn runBuild(builder: *Builder) anyerror!void {
    switch (@typeId(@typeOf(root.build).ReturnType)) {
        .Void => root.build(builder),
        .ErrorUnion => try root.build(builder),
        else => @compileError("expected return type of build to be 'void' or '!void'"),
    }
}

fn usage(builder: *Builder, already_ran_build: bool, out_stream: var) !void {
    // run the build script to collect the options
    if (!already_ran_build) {
        builder.setInstallPrefix(null);
        builder.resolveInstallPrefix();
        try runBuild(builder);
    }

    try out_stream.print(
        \\Usage: {} build [steps] [options]
        \\
        \\Steps:
        \\
    , builder.zig_exe);

    const allocator = builder.allocator;
    for (builder.top_level_steps.toSliceConst()) |top_level_step| {
        const name = if (&top_level_step.step == builder.default_step)
            try fmt.allocPrint(allocator, "{} (default)", top_level_step.step.name)
        else
            top_level_step.step.name;
        try out_stream.print("  {s:22} {}\n", name, top_level_step.description);
    }

    try out_stream.write(
        \\
        \\General Options:
        \\  --help                 Print this help and exit
        \\  --verbose              Print commands before executing them
        \\  --prefix [path]        Override default install prefix
        \\  --search-prefix [path] Add a path to look for binaries, libraries, headers
        \\
        \\Project-Specific Options:
        \\
    );

    if (builder.available_options_list.len == 0) {
        try out_stream.print("  (none)\n");
    } else {
        for (builder.available_options_list.toSliceConst()) |option| {
            const name = try fmt.allocPrint(allocator, "  -D{}=[{}]", option.name, Builder.typeIdName(option.type_id));
            defer allocator.free(name);
            try out_stream.print("{s:24} {}\n", name, option.description);
        }
    }

    try out_stream.write(
        \\
        \\Advanced Options:
        \\  --build-file [file]      Override path to build.zig
        \\  --cache-dir [path]       Override path to zig cache directory
        \\  --override-lib-dir [arg] Override path to Zig lib directory
        \\  --verbose-tokenize       Enable compiler debug output for tokenization
        \\  --verbose-ast            Enable compiler debug output for parsing into an AST
        \\  --verbose-link           Enable compiler debug output for linking
        \\  --verbose-ir             Enable compiler debug output for Zig IR
        \\  --verbose-llvm-ir        Enable compiler debug output for LLVM IR
        \\  --verbose-cimport        Enable compiler debug output for C imports
        \\  --verbose-cc             Enable compiler debug output for C compilation
        \\
    );
}

fn usageAndErr(builder: *Builder, already_ran_build: bool, out_stream: var) void {
    usage(builder, already_ran_build, out_stream) catch {};
    process.exit(1);
}

const UnwrapArgError = error{OutOfMemory};

fn unwrapArg(arg: UnwrapArgError![]u8) UnwrapArgError![]u8 {
    return arg catch |err| {
        warn("Unable to parse command line: {}\n", err);
        return err;
    };
}

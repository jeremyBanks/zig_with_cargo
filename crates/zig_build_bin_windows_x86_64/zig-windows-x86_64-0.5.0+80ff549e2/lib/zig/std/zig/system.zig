const std = @import("../std.zig");
const elf = std.elf;
const mem = std.mem;
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const process = std.process;
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;

const is_windows = Target.current.os.tag == .windows;

pub const NativePaths = struct {
    include_dirs: ArrayList([:0]u8),
    lib_dirs: ArrayList([:0]u8),
    rpaths: ArrayList([:0]u8),
    warnings: ArrayList([:0]u8),

    pub fn detect(allocator: *Allocator) !NativePaths {
        var self: NativePaths = .{
            .include_dirs = ArrayList([:0]u8).init(allocator),
            .lib_dirs = ArrayList([:0]u8).init(allocator),
            .rpaths = ArrayList([:0]u8).init(allocator),
            .warnings = ArrayList([:0]u8).init(allocator),
        };
        errdefer self.deinit();

        var is_nix = false;
        if (process.getEnvVarOwned(allocator, "NIX_CFLAGS_COMPILE")) |nix_cflags_compile| {
            defer allocator.free(nix_cflags_compile);

            is_nix = true;
            var it = mem.tokenize(nix_cflags_compile, " ");
            while (true) {
                const word = it.next() orelse break;
                if (mem.eql(u8, word, "-isystem")) {
                    const include_path = it.next() orelse {
                        try self.addWarning("Expected argument after -isystem in NIX_CFLAGS_COMPILE");
                        break;
                    };
                    try self.addIncludeDir(include_path);
                } else {
                    try self.addWarningFmt("Unrecognized C flag from NIX_CFLAGS_COMPILE: {}", .{word});
                    break;
                }
            }
        } else |err| switch (err) {
            error.InvalidUtf8 => {},
            error.EnvironmentVariableNotFound => {},
            error.OutOfMemory => |e| return e,
        }
        if (process.getEnvVarOwned(allocator, "NIX_LDFLAGS")) |nix_ldflags| {
            defer allocator.free(nix_ldflags);

            is_nix = true;
            var it = mem.tokenize(nix_ldflags, " ");
            while (true) {
                const word = it.next() orelse break;
                if (mem.eql(u8, word, "-rpath")) {
                    const rpath = it.next() orelse {
                        try self.addWarning("Expected argument after -rpath in NIX_LDFLAGS");
                        break;
                    };
                    try self.addRPath(rpath);
                } else if (word.len > 2 and word[0] == '-' and word[1] == 'L') {
                    const lib_path = word[2..];
                    try self.addLibDir(lib_path);
                } else {
                    try self.addWarningFmt("Unrecognized C flag from NIX_LDFLAGS: {}", .{word});
                    break;
                }
            }
        } else |err| switch (err) {
            error.InvalidUtf8 => {},
            error.EnvironmentVariableNotFound => {},
            error.OutOfMemory => |e| return e,
        }
        if (is_nix) {
            return self;
        }

        if (!is_windows) {
            const triple = try Target.current.linuxTriple(allocator);

            // TODO: $ ld --verbose | grep SEARCH_DIR
            // the output contains some paths that end with lib64, maybe include them too?
            // TODO: what is the best possible order of things?
            // TODO: some of these are suspect and should only be added on some systems. audit needed.

            try self.addIncludeDir("/usr/local/include");
            try self.addLibDir("/usr/local/lib");
            try self.addLibDir("/usr/local/lib64");

            try self.addIncludeDirFmt("/usr/include/{}", .{triple});
            try self.addLibDirFmt("/usr/lib/{}", .{triple});

            try self.addIncludeDir("/usr/include");
            try self.addLibDir("/lib");
            try self.addLibDir("/lib64");
            try self.addLibDir("/usr/lib");
            try self.addLibDir("/usr/lib64");

            // example: on a 64-bit debian-based linux distro, with zlib installed from apt:
            // zlib.h is in /usr/include (added above)
            // libz.so.1 is in /lib/x86_64-linux-gnu (added here)
            try self.addLibDirFmt("/lib/{}", .{triple});
        }

        return self;
    }

    pub fn deinit(self: *NativePaths) void {
        deinitArray(&self.include_dirs);
        deinitArray(&self.lib_dirs);
        deinitArray(&self.rpaths);
        deinitArray(&self.warnings);
        self.* = undefined;
    }

    fn deinitArray(array: *ArrayList([:0]u8)) void {
        for (array.toSlice()) |item| {
            array.allocator.free(item);
        }
        array.deinit();
    }

    pub fn addIncludeDir(self: *NativePaths, s: []const u8) !void {
        return self.appendArray(&self.include_dirs, s);
    }

    pub fn addIncludeDirFmt(self: *NativePaths, comptime fmt: []const u8, args: var) !void {
        const item = try std.fmt.allocPrint0(self.include_dirs.allocator, fmt, args);
        errdefer self.include_dirs.allocator.free(item);
        try self.include_dirs.append(item);
    }

    pub fn addLibDir(self: *NativePaths, s: []const u8) !void {
        return self.appendArray(&self.lib_dirs, s);
    }

    pub fn addLibDirFmt(self: *NativePaths, comptime fmt: []const u8, args: var) !void {
        const item = try std.fmt.allocPrint0(self.lib_dirs.allocator, fmt, args);
        errdefer self.lib_dirs.allocator.free(item);
        try self.lib_dirs.append(item);
    }

    pub fn addWarning(self: *NativePaths, s: []const u8) !void {
        return self.appendArray(&self.warnings, s);
    }

    pub fn addWarningFmt(self: *NativePaths, comptime fmt: []const u8, args: var) !void {
        const item = try std.fmt.allocPrint0(self.warnings.allocator, fmt, args);
        errdefer self.warnings.allocator.free(item);
        try self.warnings.append(item);
    }

    pub fn addRPath(self: *NativePaths, s: []const u8) !void {
        return self.appendArray(&self.rpaths, s);
    }

    fn appendArray(self: *NativePaths, array: *ArrayList([:0]u8), s: []const u8) !void {
        const item = try std.mem.dupeZ(array.allocator, u8, s);
        errdefer array.allocator.free(item);
        try array.append(item);
    }
};

pub const NativeTargetInfo = struct {
    target: Target,

    dynamic_linker: DynamicLinker = DynamicLinker{},

    /// Only some architectures have CPU detection implemented. This field reveals whether
    /// CPU detection actually occurred. When this is `true` it means that the reported
    /// CPU is baseline only because of a missing implementation for that architecture.
    cpu_detection_unimplemented: bool = false,

    pub const DynamicLinker = Target.DynamicLinker;

    pub const DetectError = error{
        OutOfMemory,
        FileSystem,
        SystemResources,
        SymLinkLoop,
        ProcessFdQuotaExceeded,
        SystemFdQuotaExceeded,
        DeviceBusy,
    };

    /// Given a `CrossTarget`, which specifies in detail which parts of the target should be detected
    /// natively, which should be standard or default, and which are provided explicitly, this function
    /// resolves the native components by detecting the native system, and then resolves standard/default parts
    /// relative to that.
    /// Any resources this function allocates are released before returning, and so there is no
    /// deinitialization method.
    /// TODO Remove the Allocator requirement from this function.
    pub fn detect(allocator: *Allocator, cross_target: CrossTarget) DetectError!NativeTargetInfo {
        var os = Target.Os.defaultVersionRange(cross_target.getOsTag());
        if (cross_target.os_tag == null) {
            switch (Target.current.os.tag) {
                .linux => {
                    const uts = std.os.uname();
                    const release = mem.toSliceConst(u8, @ptrCast([*:0]const u8, &uts.release));
                    if (std.builtin.Version.parse(release)) |ver| {
                        os.version_range.linux.range.min = ver;
                        os.version_range.linux.range.max = ver;
                    } else |err| switch (err) {
                        error.Overflow => {},
                        error.InvalidCharacter => {},
                        error.InvalidVersion => {},
                    }
                },
                .windows => {
                    var version_info: std.os.windows.RTL_OSVERSIONINFOW = undefined;
                    version_info.dwOSVersionInfoSize = @sizeOf(@TypeOf(version_info));

                    switch (std.os.windows.ntdll.RtlGetVersion(&version_info)) {
                        .SUCCESS => {},
                        else => unreachable,
                    }

                    // Starting from the system infos build a NTDDI-like version
                    // constant whose format is:
                    //   B0 B1 B2 B3
                    //   `---` `` ``--> Sub-version (Starting from Windows 10 onwards)
                    //     \    `--> Service pack (Always zero in the constants defined)
                    //      `--> OS version (Major & minor)
                    const os_ver: u16 = //
                        @intCast(u16, version_info.dwMajorVersion & 0xff) << 8 |
                        @intCast(u16, version_info.dwMinorVersion & 0xff);
                    const sp_ver: u8 = 0;
                    const sub_ver: u8 = if (os_ver >= 0x0A00) subver: {
                        // There's no other way to obtain this info beside
                        // checking the build number against a known set of
                        // values
                        const known_build_numbers = [_]u32{
                            10240, 10586, 14393, 15063, 16299, 17134, 17763,
                            18362, 18363,
                        };
                        var last_idx: usize = 0;
                        for (known_build_numbers) |build, i| {
                            if (version_info.dwBuildNumber >= build)
                                last_idx = i;
                        }
                        break :subver @truncate(u8, last_idx);
                    } else 0;

                    const version: u32 = @as(u32, os_ver) << 16 | @as(u32, sp_ver) << 8 | sub_ver;

                    os.version_range.windows.max = @intToEnum(Target.Os.WindowsVersion, version);
                    os.version_range.windows.min = @intToEnum(Target.Os.WindowsVersion, version);
                },
                .macosx => {
                    var product_version: [32]u8 = undefined;
                    var size: usize = product_version.len;

                    // The osproductversion sysctl was introduced first with
                    // High Sierra, thankfully that's also the baseline that Zig
                    // supports
                    std.os.sysctlbynameC(
                        "kern.osproductversion",
                        &product_version,
                        &size,
                        null,
                        0,
                    ) catch |err| switch (err) {
                        error.UnknownName => unreachable,
                        else => unreachable,
                    };

                    const string_version = product_version[0 .. size - 1 :0];
                    if (std.builtin.Version.parse(string_version)) |ver| {
                        os.version_range.semver.min = ver;
                        os.version_range.semver.max = ver;
                    } else |err| switch (err) {
                        error.Overflow => {},
                        error.InvalidCharacter => {},
                        error.InvalidVersion => {},
                    }
                },
                .freebsd => {
                    // Unimplemented, fall back to default.
                    // https://github.com/ziglang/zig/issues/4582
                },
                else => {
                    // Unimplemented, fall back to default version range.
                },
            }
        }

        if (cross_target.os_version_min) |min| switch (min) {
            .none => {},
            .semver => |semver| switch (cross_target.getOsTag()) {
                .linux => os.version_range.linux.range.min = semver,
                else => os.version_range.semver.min = semver,
            },
            .windows => |win_ver| os.version_range.windows.min = win_ver,
        };

        if (cross_target.os_version_max) |max| switch (max) {
            .none => {},
            .semver => |semver| switch (cross_target.getOsTag()) {
                .linux => os.version_range.linux.range.max = semver,
                else => os.version_range.semver.max = semver,
            },
            .windows => |win_ver| os.version_range.windows.max = win_ver,
        };

        if (cross_target.glibc_version) |glibc| {
            assert(cross_target.isGnuLibC());
            os.version_range.linux.glibc = glibc;
        }

        var cpu_detection_unimplemented = false;

        // Until https://github.com/ziglang/zig/issues/4592 is implemented (support detecting the
        // native CPU architecture as being different than the current target), we use this:
        const cpu_arch = cross_target.getCpuArch();

        const cpu = switch (cross_target.cpu_model) {
            .native => detectNativeCpuAndFeatures(cpu_arch, os, cross_target),
            .baseline => baselineCpuAndFeatures(cpu_arch, cross_target),
            .determined_by_cpu_arch => if (cross_target.cpu_arch == null)
                detectNativeCpuAndFeatures(cpu_arch, os, cross_target)
            else
                baselineCpuAndFeatures(cpu_arch, cross_target),
            .explicit => |model| blk: {
                var adjusted_model = model.toCpu(cpu_arch);
                cross_target.updateCpuFeatures(&adjusted_model.features);
                break :blk adjusted_model;
            },
        } orelse backup_cpu_detection: {
            cpu_detection_unimplemented = true;
            break :backup_cpu_detection baselineCpuAndFeatures(cpu_arch, cross_target);
        };

        var target = try detectAbiAndDynamicLinker(allocator, cpu, os, cross_target);
        target.cpu_detection_unimplemented = cpu_detection_unimplemented;
        return target;
    }

    /// First we attempt to use the executable's own binary. If it is dynamically
    /// linked, then it should answer both the C ABI question and the dynamic linker question.
    /// If it is statically linked, then we try /usr/bin/env. If that does not provide the answer, then
    /// we fall back to the defaults.
    /// TODO Remove the Allocator requirement from this function.
    fn detectAbiAndDynamicLinker(
        allocator: *Allocator,
        cpu: Target.Cpu,
        os: Target.Os,
        cross_target: CrossTarget,
    ) DetectError!NativeTargetInfo {
        const native_target_has_ld = comptime Target.current.hasDynamicLinker();
        const is_linux = Target.current.os.tag == .linux;
        const have_all_info = cross_target.dynamic_linker.get() != null and
            cross_target.abi != null and (!is_linux or cross_target.abi.?.isGnu());
        const os_is_non_native = cross_target.os_tag != null;
        if (!native_target_has_ld or have_all_info or os_is_non_native) {
            return defaultAbiAndDynamicLinker(cpu, os, cross_target);
        }
        // The current target's ABI cannot be relied on for this. For example, we may build the zig
        // compiler for target riscv64-linux-musl and provide a tarball for users to download.
        // A user could then run that zig compiler on riscv64-linux-gnu. This use case is well-defined
        // and supported by Zig. But that means that we must detect the system ABI here rather than
        // relying on `Target.current`.
        const all_abis = comptime blk: {
            assert(@enumToInt(Target.Abi.none) == 0);
            const fields = std.meta.fields(Target.Abi)[1..];
            var array: [fields.len]Target.Abi = undefined;
            inline for (fields) |field, i| {
                array[i] = @field(Target.Abi, field.name);
            }
            break :blk array;
        };
        var ld_info_list_buffer: [all_abis.len]LdInfo = undefined;
        var ld_info_list_len: usize = 0;

        for (all_abis) |abi| {
            // This may be a nonsensical parameter. We detect this with error.UnknownDynamicLinkerPath and
            // skip adding it to `ld_info_list`.
            const target: Target = .{
                .cpu = cpu,
                .os = os,
                .abi = abi,
            };
            const ld = target.standardDynamicLinkerPath();
            if (ld.get() == null) continue;

            ld_info_list_buffer[ld_info_list_len] = .{
                .ld = ld,
                .abi = abi,
            };
            ld_info_list_len += 1;
        }
        const ld_info_list = ld_info_list_buffer[0..ld_info_list_len];

        if (cross_target.dynamic_linker.get()) |explicit_ld| {
            const explicit_ld_basename = fs.path.basename(explicit_ld);
            for (ld_info_list) |ld_info| {
                const standard_ld_basename = fs.path.basename(ld_info.ld.get().?);
            }
        }

        // Best case scenario: the executable is dynamically linked, and we can iterate
        // over our own shared objects and find a dynamic linker.
        self_exe: {
            const lib_paths = try std.process.getSelfExeSharedLibPaths(allocator);
            defer allocator.free(lib_paths);

            var found_ld_info: LdInfo = undefined;
            var found_ld_path: [:0]const u8 = undefined;

            // Look for dynamic linker.
            // This is O(N^M) but typical case here is N=2 and M=10.
            find_ld: for (lib_paths) |lib_path| {
                for (ld_info_list) |ld_info| {
                    const standard_ld_basename = fs.path.basename(ld_info.ld.get().?);
                    if (std.mem.endsWith(u8, lib_path, standard_ld_basename)) {
                        found_ld_info = ld_info;
                        found_ld_path = lib_path;
                        break :find_ld;
                    }
                }
            } else break :self_exe;

            // Look for glibc version.
            var os_adjusted = os;
            if (Target.current.os.tag == .linux and found_ld_info.abi.isGnu() and
                cross_target.glibc_version == null)
            {
                for (lib_paths) |lib_path| {
                    if (std.mem.endsWith(u8, lib_path, glibc_so_basename)) {
                        os_adjusted.version_range.linux.glibc = glibcVerFromSO(lib_path) catch |err| switch (err) {
                            error.UnrecognizedGnuLibCFileName => continue,
                            error.InvalidGnuLibCVersion => continue,
                            error.GnuLibCVersionUnavailable => continue,
                            else => |e| return e,
                        };
                        break;
                    }
                }
            }

            var result: NativeTargetInfo = .{
                .target = .{
                    .cpu = cpu,
                    .os = os_adjusted,
                    .abi = cross_target.abi orelse found_ld_info.abi,
                },
                .dynamic_linker = if (cross_target.dynamic_linker.get() == null)
                    DynamicLinker.init(found_ld_path)
                else
                    cross_target.dynamic_linker,
            };
            return result;
        }

        const env_file = std.fs.openFileAbsoluteC("/usr/bin/env", .{}) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
            error.NameTooLong => unreachable,
            error.PathAlreadyExists => unreachable,
            error.SharingViolation => unreachable,
            error.InvalidUtf8 => unreachable,
            error.BadPathName => unreachable,
            error.PipeBusy => unreachable,

            error.IsDir,
            error.NotDir,
            error.AccessDenied,
            error.NoDevice,
            error.FileNotFound,
            error.FileTooBig,
            error.Unexpected,
            => return defaultAbiAndDynamicLinker(cpu, os, cross_target),

            else => |e| return e,
        };
        defer env_file.close();

        // If Zig is statically linked, such as via distributed binary static builds, the above
        // trick won't work. The next thing we fall back to is the same thing, but for /usr/bin/env.
        // Since that path is hard-coded into the shebang line of many portable scripts, it's a
        // reasonably reliable path to check for.
        return abiAndDynamicLinkerFromFile(env_file, cpu, os, ld_info_list, cross_target) catch |err| switch (err) {
            error.FileSystem,
            error.SystemResources,
            error.SymLinkLoop,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            => |e| return e,

            error.UnableToReadElfFile,
            error.InvalidElfClass,
            error.InvalidElfVersion,
            error.InvalidElfEndian,
            error.InvalidElfFile,
            error.InvalidElfMagic,
            error.Unexpected,
            error.UnexpectedEndOfFile,
            error.NameTooLong,
            // Finally, we fall back on the standard path.
            => defaultAbiAndDynamicLinker(cpu, os, cross_target),
        };
    }

    const glibc_so_basename = "libc.so.6";

    fn glibcVerFromSO(so_path: [:0]const u8) !std.builtin.Version {
        var link_buf: [std.os.PATH_MAX]u8 = undefined;
        const link_name = std.os.readlinkC(so_path.ptr, &link_buf) catch |err| switch (err) {
            error.AccessDenied => return error.GnuLibCVersionUnavailable,
            error.FileSystem => return error.FileSystem,
            error.SymLinkLoop => return error.SymLinkLoop,
            error.NameTooLong => unreachable,
            error.FileNotFound => return error.GnuLibCVersionUnavailable,
            error.SystemResources => return error.SystemResources,
            error.NotDir => return error.GnuLibCVersionUnavailable,
            error.Unexpected => return error.GnuLibCVersionUnavailable,
        };
        return glibcVerFromLinkName(link_name);
    }

    fn glibcVerFromLinkName(link_name: []const u8) !std.builtin.Version {
        // example: "libc-2.3.4.so"
        // example: "libc-2.27.so"
        const prefix = "libc-";
        const suffix = ".so";
        if (!mem.startsWith(u8, link_name, prefix) or !mem.endsWith(u8, link_name, suffix)) {
            return error.UnrecognizedGnuLibCFileName;
        }
        // chop off "libc-" and ".so"
        const link_name_chopped = link_name[prefix.len .. link_name.len - suffix.len];
        return std.builtin.Version.parse(link_name_chopped) catch |err| switch (err) {
            error.Overflow => return error.InvalidGnuLibCVersion,
            error.InvalidCharacter => return error.InvalidGnuLibCVersion,
            error.InvalidVersion => return error.InvalidGnuLibCVersion,
        };
    }

    pub const AbiAndDynamicLinkerFromFileError = error{
        FileSystem,
        SystemResources,
        SymLinkLoop,
        ProcessFdQuotaExceeded,
        SystemFdQuotaExceeded,
        UnableToReadElfFile,
        InvalidElfClass,
        InvalidElfVersion,
        InvalidElfEndian,
        InvalidElfFile,
        InvalidElfMagic,
        Unexpected,
        UnexpectedEndOfFile,
        NameTooLong,
    };

    pub fn abiAndDynamicLinkerFromFile(
        file: fs.File,
        cpu: Target.Cpu,
        os: Target.Os,
        ld_info_list: []const LdInfo,
        cross_target: CrossTarget,
    ) AbiAndDynamicLinkerFromFileError!NativeTargetInfo {
        var hdr_buf: [@sizeOf(elf.Elf64_Ehdr)]u8 align(@alignOf(elf.Elf64_Ehdr)) = undefined;
        _ = try preadFull(file, &hdr_buf, 0, hdr_buf.len);
        const hdr32 = @ptrCast(*elf.Elf32_Ehdr, &hdr_buf);
        const hdr64 = @ptrCast(*elf.Elf64_Ehdr, &hdr_buf);
        if (!mem.eql(u8, hdr32.e_ident[0..4], "\x7fELF")) return error.InvalidElfMagic;
        const elf_endian: std.builtin.Endian = switch (hdr32.e_ident[elf.EI_DATA]) {
            elf.ELFDATA2LSB => .Little,
            elf.ELFDATA2MSB => .Big,
            else => return error.InvalidElfEndian,
        };
        const need_bswap = elf_endian != std.builtin.endian;
        if (hdr32.e_ident[elf.EI_VERSION] != 1) return error.InvalidElfVersion;

        const is_64 = switch (hdr32.e_ident[elf.EI_CLASS]) {
            elf.ELFCLASS32 => false,
            elf.ELFCLASS64 => true,
            else => return error.InvalidElfClass,
        };
        var phoff = elfInt(is_64, need_bswap, hdr32.e_phoff, hdr64.e_phoff);
        const phentsize = elfInt(is_64, need_bswap, hdr32.e_phentsize, hdr64.e_phentsize);
        const phnum = elfInt(is_64, need_bswap, hdr32.e_phnum, hdr64.e_phnum);

        var result: NativeTargetInfo = .{
            .target = .{
                .cpu = cpu,
                .os = os,
                .abi = cross_target.abi orelse Target.Abi.default(cpu.arch, os),
            },
            .dynamic_linker = cross_target.dynamic_linker,
        };
        var rpath_offset: ?u64 = null; // Found inside PT_DYNAMIC
        const look_for_ld = cross_target.dynamic_linker.get() == null;

        var ph_buf: [16 * @sizeOf(elf.Elf64_Phdr)]u8 align(@alignOf(elf.Elf64_Phdr)) = undefined;
        if (phentsize > @sizeOf(elf.Elf64_Phdr)) return error.InvalidElfFile;

        var ph_i: u16 = 0;
        while (ph_i < phnum) {
            // Reserve some bytes so that we can deref the 64-bit struct fields
            // even when the ELF file is 32-bits.
            const ph_reserve: usize = @sizeOf(elf.Elf64_Phdr) - @sizeOf(elf.Elf32_Phdr);
            const ph_read_byte_len = try preadFull(file, ph_buf[0 .. ph_buf.len - ph_reserve], phoff, phentsize);
            var ph_buf_i: usize = 0;
            while (ph_buf_i < ph_read_byte_len and ph_i < phnum) : ({
                ph_i += 1;
                phoff += phentsize;
                ph_buf_i += phentsize;
            }) {
                const ph32 = @ptrCast(*elf.Elf32_Phdr, @alignCast(@alignOf(elf.Elf32_Phdr), &ph_buf[ph_buf_i]));
                const ph64 = @ptrCast(*elf.Elf64_Phdr, @alignCast(@alignOf(elf.Elf64_Phdr), &ph_buf[ph_buf_i]));
                const p_type = elfInt(is_64, need_bswap, ph32.p_type, ph64.p_type);
                switch (p_type) {
                    elf.PT_INTERP => if (look_for_ld) {
                        const p_offset = elfInt(is_64, need_bswap, ph32.p_offset, ph64.p_offset);
                        const p_filesz = elfInt(is_64, need_bswap, ph32.p_filesz, ph64.p_filesz);
                        if (p_filesz > result.dynamic_linker.buffer.len) return error.NameTooLong;
                        _ = try preadFull(file, result.dynamic_linker.buffer[0..p_filesz], p_offset, p_filesz);
                        // PT_INTERP includes a null byte in p_filesz.
                        const len = p_filesz - 1;
                        // dynamic_linker.max_byte is "max", not "len".
                        // We know it will fit in u8 because we check against dynamic_linker.buffer.len above.
                        result.dynamic_linker.max_byte = @intCast(u8, len - 1);

                        // Use it to determine ABI.
                        const full_ld_path = result.dynamic_linker.buffer[0..len];
                        for (ld_info_list) |ld_info| {
                            const standard_ld_basename = fs.path.basename(ld_info.ld.get().?);
                            if (std.mem.endsWith(u8, full_ld_path, standard_ld_basename)) {
                                result.target.abi = ld_info.abi;
                                break;
                            }
                        }
                    },
                    // We only need this for detecting glibc version.
                    elf.PT_DYNAMIC => if (Target.current.os.tag == .linux and result.target.isGnuLibC() and
                        cross_target.glibc_version == null)
                    {
                        var dyn_off = elfInt(is_64, need_bswap, ph32.p_offset, ph64.p_offset);
                        const p_filesz = elfInt(is_64, need_bswap, ph32.p_filesz, ph64.p_filesz);
                        const dyn_size: u64 = if (is_64) @sizeOf(elf.Elf64_Dyn) else @sizeOf(elf.Elf32_Dyn);
                        const dyn_num = p_filesz / dyn_size;
                        var dyn_buf: [16 * @sizeOf(elf.Elf64_Dyn)]u8 align(@alignOf(elf.Elf64_Dyn)) = undefined;
                        var dyn_i: usize = 0;
                        dyn: while (dyn_i < dyn_num) {
                            // Reserve some bytes so that we can deref the 64-bit struct fields
                            // even when the ELF file is 32-bits.
                            const dyn_reserve: usize = @sizeOf(elf.Elf64_Dyn) - @sizeOf(elf.Elf32_Dyn);
                            const dyn_read_byte_len = try preadFull(
                                file,
                                dyn_buf[0 .. dyn_buf.len - dyn_reserve],
                                dyn_off,
                                dyn_size,
                            );
                            var dyn_buf_i: usize = 0;
                            while (dyn_buf_i < dyn_read_byte_len and dyn_i < dyn_num) : ({
                                dyn_i += 1;
                                dyn_off += dyn_size;
                                dyn_buf_i += dyn_size;
                            }) {
                                const dyn32 = @ptrCast(
                                    *elf.Elf32_Dyn,
                                    @alignCast(@alignOf(elf.Elf32_Dyn), &dyn_buf[dyn_buf_i]),
                                );
                                const dyn64 = @ptrCast(
                                    *elf.Elf64_Dyn,
                                    @alignCast(@alignOf(elf.Elf64_Dyn), &dyn_buf[dyn_buf_i]),
                                );
                                const tag = elfInt(is_64, need_bswap, dyn32.d_tag, dyn64.d_tag);
                                const val = elfInt(is_64, need_bswap, dyn32.d_val, dyn64.d_val);
                                if (tag == elf.DT_RUNPATH) {
                                    rpath_offset = val;
                                    break :dyn;
                                }
                            }
                        }
                    },
                    else => continue,
                }
            }
        }

        if (Target.current.os.tag == .linux and result.target.isGnuLibC() and cross_target.glibc_version == null) {
            if (rpath_offset) |rpoff| {
                const shstrndx = elfInt(is_64, need_bswap, hdr32.e_shstrndx, hdr64.e_shstrndx);

                var shoff = elfInt(is_64, need_bswap, hdr32.e_shoff, hdr64.e_shoff);
                const shentsize = elfInt(is_64, need_bswap, hdr32.e_shentsize, hdr64.e_shentsize);
                const str_section_off = shoff + @as(u64, shentsize) * @as(u64, shstrndx);

                var sh_buf: [16 * @sizeOf(elf.Elf64_Shdr)]u8 align(@alignOf(elf.Elf64_Shdr)) = undefined;
                if (sh_buf.len < shentsize) return error.InvalidElfFile;

                _ = try preadFull(file, &sh_buf, str_section_off, shentsize);
                const shstr32 = @ptrCast(*elf.Elf32_Shdr, @alignCast(@alignOf(elf.Elf32_Shdr), &sh_buf));
                const shstr64 = @ptrCast(*elf.Elf64_Shdr, @alignCast(@alignOf(elf.Elf64_Shdr), &sh_buf));
                const shstrtab_off = elfInt(is_64, need_bswap, shstr32.sh_offset, shstr64.sh_offset);
                const shstrtab_size = elfInt(is_64, need_bswap, shstr32.sh_size, shstr64.sh_size);
                var strtab_buf: [4096:0]u8 = undefined;
                const shstrtab_len = std.math.min(shstrtab_size, strtab_buf.len);
                const shstrtab_read_len = try preadFull(file, &strtab_buf, shstrtab_off, shstrtab_len);
                const shstrtab = strtab_buf[0..shstrtab_read_len];

                const shnum = elfInt(is_64, need_bswap, hdr32.e_shnum, hdr64.e_shnum);
                var sh_i: u16 = 0;
                const dynstr: ?struct { offset: u64, size: u64 } = find_dyn_str: while (sh_i < shnum) {
                    // Reserve some bytes so that we can deref the 64-bit struct fields
                    // even when the ELF file is 32-bits.
                    const sh_reserve: usize = @sizeOf(elf.Elf64_Shdr) - @sizeOf(elf.Elf32_Shdr);
                    const sh_read_byte_len = try preadFull(
                        file,
                        sh_buf[0 .. sh_buf.len - sh_reserve],
                        shoff,
                        shentsize,
                    );
                    var sh_buf_i: usize = 0;
                    while (sh_buf_i < sh_read_byte_len and sh_i < shnum) : ({
                        sh_i += 1;
                        shoff += shentsize;
                        sh_buf_i += shentsize;
                    }) {
                        const sh32 = @ptrCast(
                            *elf.Elf32_Shdr,
                            @alignCast(@alignOf(elf.Elf32_Shdr), &sh_buf[sh_buf_i]),
                        );
                        const sh64 = @ptrCast(
                            *elf.Elf64_Shdr,
                            @alignCast(@alignOf(elf.Elf64_Shdr), &sh_buf[sh_buf_i]),
                        );
                        const sh_name_off = elfInt(is_64, need_bswap, sh32.sh_name, sh64.sh_name);
                        // TODO this pointer cast should not be necessary
                        const sh_name = mem.toSliceConst(u8, @ptrCast([*:0]u8, shstrtab[sh_name_off..].ptr));
                        if (mem.eql(u8, sh_name, ".dynstr")) {
                            break :find_dyn_str .{
                                .offset = elfInt(is_64, need_bswap, sh32.sh_offset, sh64.sh_offset),
                                .size = elfInt(is_64, need_bswap, sh32.sh_size, sh64.sh_size),
                            };
                        }
                    }
                } else null;

                if (dynstr) |ds| {
                    const strtab_len = std.math.min(ds.size, strtab_buf.len);
                    const strtab_read_len = try preadFull(file, &strtab_buf, ds.offset, shstrtab_len);
                    const strtab = strtab_buf[0..strtab_read_len];
                    // TODO this pointer cast should not be necessary
                    const rpath_list = mem.toSliceConst(u8, @ptrCast([*:0]u8, strtab[rpoff..].ptr));
                    var it = mem.tokenize(rpath_list, ":");
                    while (it.next()) |rpath| {
                        var dir = fs.cwd().openDirList(rpath) catch |err| switch (err) {
                            error.NameTooLong => unreachable,
                            error.InvalidUtf8 => unreachable,
                            error.BadPathName => unreachable,
                            error.DeviceBusy => unreachable,

                            error.FileNotFound,
                            error.NotDir,
                            error.AccessDenied,
                            error.NoDevice,
                            => continue,

                            error.ProcessFdQuotaExceeded,
                            error.SystemFdQuotaExceeded,
                            error.SystemResources,
                            error.SymLinkLoop,
                            error.Unexpected,
                            => |e| return e,
                        };
                        defer dir.close();

                        var link_buf: [std.os.PATH_MAX]u8 = undefined;
                        const link_name = std.os.readlinkatC(
                            dir.fd,
                            glibc_so_basename,
                            &link_buf,
                        ) catch |err| switch (err) {
                            error.NameTooLong => unreachable,

                            error.AccessDenied,
                            error.FileNotFound,
                            error.NotDir,
                            => continue,

                            error.SystemResources,
                            error.FileSystem,
                            error.SymLinkLoop,
                            error.Unexpected,
                            => |e| return e,
                        };
                        result.target.os.version_range.linux.glibc = glibcVerFromLinkName(
                            link_name,
                        ) catch |err| switch (err) {
                            error.UnrecognizedGnuLibCFileName,
                            error.InvalidGnuLibCVersion,
                            => continue,
                        };
                        break;
                    }
                }
            }
        }

        return result;
    }

    fn preadFull(file: fs.File, buf: []u8, offset: u64, min_read_len: usize) !usize {
        var i: u64 = 0;
        while (i < min_read_len) {
            const len = file.pread(buf[i .. buf.len - i], offset + i) catch |err| switch (err) {
                error.OperationAborted => unreachable, // Windows-only
                error.WouldBlock => unreachable, // Did not request blocking mode
                error.SystemResources => return error.SystemResources,
                error.IsDir => return error.UnableToReadElfFile,
                error.BrokenPipe => return error.UnableToReadElfFile,
                error.Unseekable => return error.UnableToReadElfFile,
                error.ConnectionResetByPeer => return error.UnableToReadElfFile,
                error.Unexpected => return error.Unexpected,
                error.InputOutput => return error.FileSystem,
            };
            if (len == 0) return error.UnexpectedEndOfFile;
            i += len;
        }
        return i;
    }

    fn defaultAbiAndDynamicLinker(cpu: Target.Cpu, os: Target.Os, cross_target: CrossTarget) !NativeTargetInfo {
        const target: Target = .{
            .cpu = cpu,
            .os = os,
            .abi = cross_target.abi orelse Target.Abi.default(cpu.arch, os),
        };
        return NativeTargetInfo{
            .target = target,
            .dynamic_linker = if (cross_target.dynamic_linker.get() == null)
                target.standardDynamicLinkerPath()
            else
                cross_target.dynamic_linker,
        };
    }

    pub const LdInfo = struct {
        ld: DynamicLinker,
        abi: Target.Abi,
    };

    fn elfInt(is_64: bool, need_bswap: bool, int_32: var, int_64: var) @TypeOf(int_64) {
        if (is_64) {
            if (need_bswap) {
                return @byteSwap(@TypeOf(int_64), int_64);
            } else {
                return int_64;
            }
        } else {
            if (need_bswap) {
                return @byteSwap(@TypeOf(int_32), int_32);
            } else {
                return int_32;
            }
        }
    }

    fn detectNativeCpuAndFeatures(cpu_arch: Target.Cpu.Arch, os: Target.Os, cross_target: CrossTarget) ?Target.Cpu {
        // Here we switch on a comptime value rather than `cpu_arch`. This is valid because `cpu_arch`,
        // although it is a runtime value, is guaranteed to be one of the architectures in the set
        // of the respective switch prong.
        switch (std.Target.current.cpu.arch) {
            .x86_64, .i386 => {
                return @import("system/x86.zig").detectNativeCpuAndFeatures(cpu_arch, os, cross_target);
            },
            else => {
                // This architecture does not have CPU model & feature detection yet.
                // See https://github.com/ziglang/zig/issues/4591
                return null;
            },
        }
    }

    fn baselineCpuAndFeatures(cpu_arch: Target.Cpu.Arch, cross_target: CrossTarget) Target.Cpu {
        var adjusted_baseline = Target.Cpu.baseline(cpu_arch);
        cross_target.updateCpuFeatures(&adjusted_baseline.features);
        return adjusted_baseline;
    }
};

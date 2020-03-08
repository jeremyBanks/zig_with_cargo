const std = @import("std.zig");
const builtin = @import("builtin");
const debug = std.debug;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const math = std.math;
const leb = @import("debug/leb128.zig");

const ArrayList = std.ArrayList;

usingnamespace @import("dwarf_bits.zig");

pub const DwarfSeekableStream = io.SeekableStream(anyerror, anyerror);
pub const DwarfInStream = io.InStream(anyerror);

const PcRange = struct {
    start: u64,
    end: u64,
};

const Func = struct {
    pc_range: ?PcRange,
    name: ?[]const u8,
};

const CompileUnit = struct {
    version: u16,
    is_64: bool,
    die: *Die,
    pc_range: ?PcRange,
};

const AbbrevTable = ArrayList(AbbrevTableEntry);

const AbbrevTableHeader = struct {
    // offset from .debug_abbrev
    offset: u64,
    table: AbbrevTable,
};

const AbbrevTableEntry = struct {
    has_children: bool,
    abbrev_code: u64,
    tag_id: u64,
    attrs: ArrayList(AbbrevAttr),
};

const AbbrevAttr = struct {
    attr_id: u64,
    form_id: u64,
};

const FormValue = union(enum) {
    Address: u64,
    Block: []u8,
    Const: Constant,
    ExprLoc: []u8,
    Flag: bool,
    SecOffset: u64,
    Ref: u64,
    RefAddr: u64,
    String: []const u8,
    StrPtr: u64,
};

const Constant = struct {
    payload: u64,
    signed: bool,

    fn asUnsignedLe(self: *const Constant) !u64 {
        if (self.signed) return error.InvalidDebugInfo;
        return self.payload;
    }
};

const Die = struct {
    tag_id: u64,
    has_children: bool,
    attrs: ArrayList(Attr),

    const Attr = struct {
        id: u64,
        value: FormValue,
    };

    fn getAttr(self: *const Die, id: u64) ?*const FormValue {
        for (self.attrs.toSliceConst()) |*attr| {
            if (attr.id == id) return &attr.value;
        }
        return null;
    }

    fn getAttrAddr(self: *const Die, id: u64) !u64 {
        const form_value = self.getAttr(id) orelse return error.MissingDebugInfo;
        return switch (form_value.*) {
            FormValue.Address => |value| value,
            else => error.InvalidDebugInfo,
        };
    }

    fn getAttrSecOffset(self: *const Die, id: u64) !u64 {
        const form_value = self.getAttr(id) orelse return error.MissingDebugInfo;
        return switch (form_value.*) {
            FormValue.Const => |value| value.asUnsignedLe(),
            FormValue.SecOffset => |value| value,
            else => error.InvalidDebugInfo,
        };
    }

    fn getAttrUnsignedLe(self: *const Die, id: u64) !u64 {
        const form_value = self.getAttr(id) orelse return error.MissingDebugInfo;
        return switch (form_value.*) {
            FormValue.Const => |value| value.asUnsignedLe(),
            else => error.InvalidDebugInfo,
        };
    }

    fn getAttrRef(self: *const Die, id: u64) !u64 {
        const form_value = self.getAttr(id) orelse return error.MissingDebugInfo;
        return switch (form_value.*) {
            FormValue.Ref => |value| value,
            else => error.InvalidDebugInfo,
        };
    }

    fn getAttrString(self: *const Die, di: *DwarfInfo, id: u64) ![]const u8 {
        const form_value = self.getAttr(id) orelse return error.MissingDebugInfo;
        return switch (form_value.*) {
            FormValue.String => |value| value,
            FormValue.StrPtr => |offset| di.getString(offset),
            else => error.InvalidDebugInfo,
        };
    }
};

const FileEntry = struct {
    file_name: []const u8,
    dir_index: usize,
    mtime: usize,
    len_bytes: usize,
};

const LineNumberProgram = struct {
    address: usize,
    file: usize,
    line: i64,
    column: u64,
    is_stmt: bool,
    basic_block: bool,
    end_sequence: bool,

    default_is_stmt: bool,
    target_address: usize,
    include_dirs: []const []const u8,
    file_entries: *ArrayList(FileEntry),

    prev_address: usize,
    prev_file: usize,
    prev_line: i64,
    prev_column: u64,
    prev_is_stmt: bool,
    prev_basic_block: bool,
    prev_end_sequence: bool,

    // Reset the state machine following the DWARF specification
    pub fn reset(self: *LineNumberProgram) void {
        self.address = 0;
        self.file = 1;
        self.line = 1;
        self.column = 0;
        self.is_stmt = self.default_is_stmt;
        self.basic_block = false;
        self.end_sequence = false;
        // Invalidate all the remaining fields
        self.prev_address = 0;
        self.prev_file = undefined;
        self.prev_line = undefined;
        self.prev_column = undefined;
        self.prev_is_stmt = undefined;
        self.prev_basic_block = undefined;
        self.prev_end_sequence = undefined;
    }

    pub fn init(is_stmt: bool, include_dirs: []const []const u8, file_entries: *ArrayList(FileEntry), target_address: usize) LineNumberProgram {
        return LineNumberProgram{
            .address = 0,
            .file = 1,
            .line = 1,
            .column = 0,
            .is_stmt = is_stmt,
            .basic_block = false,
            .end_sequence = false,
            .include_dirs = include_dirs,
            .file_entries = file_entries,
            .default_is_stmt = is_stmt,
            .target_address = target_address,
            .prev_address = 0,
            .prev_file = undefined,
            .prev_line = undefined,
            .prev_column = undefined,
            .prev_is_stmt = undefined,
            .prev_basic_block = undefined,
            .prev_end_sequence = undefined,
        };
    }

    pub fn checkLineMatch(self: *LineNumberProgram) !?debug.LineInfo {
        if (self.target_address >= self.prev_address and self.target_address < self.address) {
            const file_entry = if (self.prev_file == 0) {
                return error.MissingDebugInfo;
            } else if (self.prev_file - 1 >= self.file_entries.len) {
                return error.InvalidDebugInfo;
            } else
                &self.file_entries.items[self.prev_file - 1];

            const dir_name = if (file_entry.dir_index >= self.include_dirs.len) {
                return error.InvalidDebugInfo;
            } else
                self.include_dirs[file_entry.dir_index];
            const file_name = try fs.path.join(self.file_entries.allocator, &[_][]const u8{ dir_name, file_entry.file_name });
            errdefer self.file_entries.allocator.free(file_name);
            return debug.LineInfo{
                .line = if (self.prev_line >= 0) @intCast(u64, self.prev_line) else 0,
                .column = self.prev_column,
                .file_name = file_name,
                .allocator = self.file_entries.allocator,
            };
        }

        self.prev_address = self.address;
        self.prev_file = self.file;
        self.prev_line = self.line;
        self.prev_column = self.column;
        self.prev_is_stmt = self.is_stmt;
        self.prev_basic_block = self.basic_block;
        self.prev_end_sequence = self.end_sequence;
        return null;
    }
};

fn readInitialLength(comptime E: type, in_stream: *io.InStream(E), is_64: *bool) !u64 {
    const first_32_bits = try in_stream.readIntLittle(u32);
    is_64.* = (first_32_bits == 0xffffffff);
    if (is_64.*) {
        return in_stream.readIntLittle(u64);
    } else {
        if (first_32_bits >= 0xfffffff0) return error.InvalidDebugInfo;
        // TODO this cast should not be needed
        return @as(u64, first_32_bits);
    }
}

// TODO the noasyncs here are workarounds
fn readAllocBytes(allocator: *mem.Allocator, in_stream: var, size: usize) ![]u8 {
    const buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf);
    if ((try noasync in_stream.read(buf)) < size) return error.EndOfFile;
    return buf;
}

fn parseFormValueBlockLen(allocator: *mem.Allocator, in_stream: var, size: usize) !FormValue {
    const buf = try readAllocBytes(allocator, in_stream, size);
    return FormValue{ .Block = buf };
}

// TODO the noasyncs here are workarounds
fn parseFormValueBlock(allocator: *mem.Allocator, in_stream: var, size: usize) !FormValue {
    const block_len = try noasync in_stream.readVarInt(usize, builtin.Endian.Little, size);
    return parseFormValueBlockLen(allocator, in_stream, block_len);
}

fn parseFormValueConstant(allocator: *mem.Allocator, in_stream: var, signed: bool, comptime size: i32) !FormValue {
    // TODO: Please forgive me, I've worked around zig not properly spilling some intermediate values here.
    // `noasync` should be removed from all the function calls once it is fixed.
    return FormValue{
        .Const = Constant{
            .signed = signed,
            .payload = switch (size) {
                1 => try noasync in_stream.readIntLittle(u8),
                2 => try noasync in_stream.readIntLittle(u16),
                4 => try noasync in_stream.readIntLittle(u32),
                8 => try noasync in_stream.readIntLittle(u64),
                -1 => blk: {
                    if (signed) {
                        const x = try noasync leb.readILEB128(i64, in_stream);
                        break :blk @bitCast(u64, x);
                    } else {
                        const x = try noasync leb.readULEB128(u64, in_stream);
                        break :blk x;
                    }
                },
                else => @compileError("Invalid size"),
            },
        },
    };
}

// TODO the noasyncs here are workarounds
fn parseFormValueDwarfOffsetSize(in_stream: var, is_64: bool) !u64 {
    return if (is_64) try noasync in_stream.readIntLittle(u64) else @as(u64, try noasync in_stream.readIntLittle(u32));
}

// TODO the noasyncs here are workarounds
fn parseFormValueTargetAddrSize(in_stream: var) !u64 {
    if (@sizeOf(usize) == 4) {
        // TODO this cast should not be needed
        return @as(u64, try noasync in_stream.readIntLittle(u32));
    } else if (@sizeOf(usize) == 8) {
        return noasync in_stream.readIntLittle(u64);
    } else {
        unreachable;
    }
}

// TODO the noasyncs here are workarounds
fn parseFormValueRef(allocator: *mem.Allocator, in_stream: var, size: i32) !FormValue {
    return FormValue{
        .Ref = switch (size) {
            1 => try noasync in_stream.readIntLittle(u8),
            2 => try noasync in_stream.readIntLittle(u16),
            4 => try noasync in_stream.readIntLittle(u32),
            8 => try noasync in_stream.readIntLittle(u64),
            -1 => try noasync leb.readULEB128(u64, in_stream),
            else => unreachable,
        },
    };
}

// TODO the noasyncs here are workarounds
fn parseFormValue(allocator: *mem.Allocator, in_stream: var, form_id: u64, is_64: bool) anyerror!FormValue {
    return switch (form_id) {
        FORM_addr => FormValue{ .Address = try parseFormValueTargetAddrSize(in_stream) },
        FORM_block1 => parseFormValueBlock(allocator, in_stream, 1),
        FORM_block2 => parseFormValueBlock(allocator, in_stream, 2),
        FORM_block4 => parseFormValueBlock(allocator, in_stream, 4),
        FORM_block => x: {
            const block_len = try noasync leb.readULEB128(usize, in_stream);
            return parseFormValueBlockLen(allocator, in_stream, block_len);
        },
        FORM_data1 => parseFormValueConstant(allocator, in_stream, false, 1),
        FORM_data2 => parseFormValueConstant(allocator, in_stream, false, 2),
        FORM_data4 => parseFormValueConstant(allocator, in_stream, false, 4),
        FORM_data8 => parseFormValueConstant(allocator, in_stream, false, 8),
        FORM_udata, FORM_sdata => {
            const signed = form_id == FORM_sdata;
            return parseFormValueConstant(allocator, in_stream, signed, -1);
        },
        FORM_exprloc => {
            const size = try noasync leb.readULEB128(usize, in_stream);
            const buf = try readAllocBytes(allocator, in_stream, size);
            return FormValue{ .ExprLoc = buf };
        },
        FORM_flag => FormValue{ .Flag = (try noasync in_stream.readByte()) != 0 },
        FORM_flag_present => FormValue{ .Flag = true },
        FORM_sec_offset => FormValue{ .SecOffset = try parseFormValueDwarfOffsetSize(in_stream, is_64) },

        FORM_ref1 => parseFormValueRef(allocator, in_stream, 1),
        FORM_ref2 => parseFormValueRef(allocator, in_stream, 2),
        FORM_ref4 => parseFormValueRef(allocator, in_stream, 4),
        FORM_ref8 => parseFormValueRef(allocator, in_stream, 8),
        FORM_ref_udata => parseFormValueRef(allocator, in_stream, -1),

        FORM_ref_addr => FormValue{ .RefAddr = try parseFormValueDwarfOffsetSize(in_stream, is_64) },
        FORM_ref_sig8 => FormValue{ .Ref = try noasync in_stream.readIntLittle(u64) },

        FORM_string => FormValue{ .String = try in_stream.readUntilDelimiterAlloc(allocator, 0, math.maxInt(usize)) },
        FORM_strp => FormValue{ .StrPtr = try parseFormValueDwarfOffsetSize(in_stream, is_64) },
        FORM_indirect => {
            const child_form_id = try noasync leb.readULEB128(u64, in_stream);
            const F = @TypeOf(async parseFormValue(allocator, in_stream, child_form_id, is_64));
            var frame = try allocator.create(F);
            defer allocator.destroy(frame);
            return await @asyncCall(frame, {}, parseFormValue, allocator, in_stream, child_form_id, is_64);
        },
        else => error.InvalidDebugInfo,
    };
}

fn getAbbrevTableEntry(abbrev_table: *const AbbrevTable, abbrev_code: u64) ?*const AbbrevTableEntry {
    for (abbrev_table.toSliceConst()) |*table_entry| {
        if (table_entry.abbrev_code == abbrev_code) return table_entry;
    }
    return null;
}

pub const DwarfInfo = struct {
    endian: builtin.Endian,
    // No memory is owned by the DwarfInfo
    debug_info: []const u8,
    debug_abbrev: []const u8,
    debug_str: []const u8,
    debug_line: []const u8,
    debug_ranges: ?[]const u8,
    // Filled later by the initializer
    abbrev_table_list: ArrayList(AbbrevTableHeader) = undefined,
    compile_unit_list: ArrayList(CompileUnit) = undefined,
    func_list: ArrayList(Func) = undefined,

    pub fn allocator(self: DwarfInfo) *mem.Allocator {
        return self.abbrev_table_list.allocator;
    }

    fn getSymbolName(di: *DwarfInfo, address: u64) ?[]const u8 {
        for (di.func_list.toSliceConst()) |*func| {
            if (func.pc_range) |range| {
                if (address >= range.start and address < range.end) {
                    return func.name;
                }
            }
        }

        return null;
    }

    fn scanAllFunctions(di: *DwarfInfo) !void {
        var s = io.SliceSeekableInStream.init(di.debug_info);
        var this_unit_offset: u64 = 0;

        while (this_unit_offset < try s.seekable_stream.getEndPos()) {
            s.seekable_stream.seekTo(this_unit_offset) catch |err| switch (err) {
                error.EndOfStream => unreachable,
                else => return err,
            };

            var is_64: bool = undefined;
            const unit_length = try readInitialLength(@TypeOf(s.stream.readFn).ReturnType.ErrorSet, &s.stream, &is_64);
            if (unit_length == 0) return;
            const next_offset = unit_length + (if (is_64) @as(usize, 12) else @as(usize, 4));

            const version = try s.stream.readInt(u16, di.endian);
            if (version < 2 or version > 5) return error.InvalidDebugInfo;

            const debug_abbrev_offset = if (is_64) try s.stream.readInt(u64, di.endian) else try s.stream.readInt(u32, di.endian);

            const address_size = try s.stream.readByte();
            if (address_size != @sizeOf(usize)) return error.InvalidDebugInfo;

            const compile_unit_pos = try s.seekable_stream.getPos();
            const abbrev_table = try di.getAbbrevTable(debug_abbrev_offset);

            try s.seekable_stream.seekTo(compile_unit_pos);

            const next_unit_pos = this_unit_offset + next_offset;

            while ((try s.seekable_stream.getPos()) < next_unit_pos) {
                const die_obj = (try di.parseDie(&s.stream, abbrev_table, is_64)) orelse continue;
                defer die_obj.attrs.deinit();

                const after_die_offset = try s.seekable_stream.getPos();

                switch (die_obj.tag_id) {
                    TAG_subprogram, TAG_inlined_subroutine, TAG_subroutine, TAG_entry_point => {
                        const fn_name = x: {
                            var depth: i32 = 3;
                            var this_die_obj = die_obj;
                            // Prenvent endless loops
                            while (depth > 0) : (depth -= 1) {
                                if (this_die_obj.getAttr(AT_name)) |_| {
                                    const name = try this_die_obj.getAttrString(di, AT_name);
                                    break :x name;
                                } else if (this_die_obj.getAttr(AT_abstract_origin)) |ref| {
                                    // Follow the DIE it points to and repeat
                                    const ref_offset = try this_die_obj.getAttrRef(AT_abstract_origin);
                                    if (ref_offset > next_offset) return error.InvalidDebugInfo;
                                    try s.seekable_stream.seekTo(this_unit_offset + ref_offset);
                                    this_die_obj = (try di.parseDie(&s.stream, abbrev_table, is_64)) orelse return error.InvalidDebugInfo;
                                } else if (this_die_obj.getAttr(AT_specification)) |ref| {
                                    // Follow the DIE it points to and repeat
                                    const ref_offset = try this_die_obj.getAttrRef(AT_specification);
                                    if (ref_offset > next_offset) return error.InvalidDebugInfo;
                                    try s.seekable_stream.seekTo(this_unit_offset + ref_offset);
                                    this_die_obj = (try di.parseDie(&s.stream, abbrev_table, is_64)) orelse return error.InvalidDebugInfo;
                                } else {
                                    break :x null;
                                }
                            }

                            break :x null;
                        };

                        const pc_range = x: {
                            if (die_obj.getAttrAddr(AT_low_pc)) |low_pc| {
                                if (die_obj.getAttr(AT_high_pc)) |high_pc_value| {
                                    const pc_end = switch (high_pc_value.*) {
                                        FormValue.Address => |value| value,
                                        FormValue.Const => |value| b: {
                                            const offset = try value.asUnsignedLe();
                                            break :b (low_pc + offset);
                                        },
                                        else => return error.InvalidDebugInfo,
                                    };
                                    break :x PcRange{
                                        .start = low_pc,
                                        .end = pc_end,
                                    };
                                } else {
                                    break :x null;
                                }
                            } else |err| {
                                if (err != error.MissingDebugInfo) return err;
                                break :x null;
                            }
                        };

                        try di.func_list.append(Func{
                            .name = fn_name,
                            .pc_range = pc_range,
                        });
                    },
                    else => {},
                }

                try s.seekable_stream.seekTo(after_die_offset);
            }

            this_unit_offset += next_offset;
        }
    }

    fn scanAllCompileUnits(di: *DwarfInfo) !void {
        var s = io.SliceSeekableInStream.init(di.debug_info);
        var this_unit_offset: u64 = 0;

        while (this_unit_offset < try s.seekable_stream.getEndPos()) {
            s.seekable_stream.seekTo(this_unit_offset) catch |err| switch (err) {
                error.EndOfStream => unreachable,
                else => return err,
            };

            var is_64: bool = undefined;
            const unit_length = try readInitialLength(@TypeOf(s.stream.readFn).ReturnType.ErrorSet, &s.stream, &is_64);
            if (unit_length == 0) return;
            const next_offset = unit_length + (if (is_64) @as(usize, 12) else @as(usize, 4));

            const version = try s.stream.readInt(u16, di.endian);
            if (version < 2 or version > 5) return error.InvalidDebugInfo;

            const debug_abbrev_offset = if (is_64) try s.stream.readInt(u64, di.endian) else try s.stream.readInt(u32, di.endian);

            const address_size = try s.stream.readByte();
            if (address_size != @sizeOf(usize)) return error.InvalidDebugInfo;

            const compile_unit_pos = try s.seekable_stream.getPos();
            const abbrev_table = try di.getAbbrevTable(debug_abbrev_offset);

            try s.seekable_stream.seekTo(compile_unit_pos);

            const compile_unit_die = try di.allocator().create(Die);
            compile_unit_die.* = (try di.parseDie(&s.stream, abbrev_table, is_64)) orelse return error.InvalidDebugInfo;

            if (compile_unit_die.tag_id != TAG_compile_unit) return error.InvalidDebugInfo;

            const pc_range = x: {
                if (compile_unit_die.getAttrAddr(AT_low_pc)) |low_pc| {
                    if (compile_unit_die.getAttr(AT_high_pc)) |high_pc_value| {
                        const pc_end = switch (high_pc_value.*) {
                            FormValue.Address => |value| value,
                            FormValue.Const => |value| b: {
                                const offset = try value.asUnsignedLe();
                                break :b (low_pc + offset);
                            },
                            else => return error.InvalidDebugInfo,
                        };
                        break :x PcRange{
                            .start = low_pc,
                            .end = pc_end,
                        };
                    } else {
                        break :x null;
                    }
                } else |err| {
                    if (err != error.MissingDebugInfo) return err;
                    break :x null;
                }
            };

            try di.compile_unit_list.append(CompileUnit{
                .version = version,
                .is_64 = is_64,
                .pc_range = pc_range,
                .die = compile_unit_die,
            });

            this_unit_offset += next_offset;
        }
    }

    fn findCompileUnit(di: *DwarfInfo, target_address: u64) !*const CompileUnit {
        for (di.compile_unit_list.toSlice()) |*compile_unit| {
            if (compile_unit.pc_range) |range| {
                if (target_address >= range.start and target_address < range.end) return compile_unit;
            }
            if (di.debug_ranges) |debug_ranges| {
                if (compile_unit.die.getAttrSecOffset(AT_ranges)) |ranges_offset| {
                    var s = io.SliceSeekableInStream.init(debug_ranges);

                    // All the addresses in the list are relative to the value
                    // specified by DW_AT_low_pc or to some other value encoded
                    // in the list itself.
                    // If no starting value is specified use zero.
                    var base_address = compile_unit.die.getAttrAddr(AT_low_pc) catch |err| switch (err) {
                        error.MissingDebugInfo => 0,
                        else => return err,
                    };

                    try s.seekable_stream.seekTo(ranges_offset);

                    while (true) {
                        const begin_addr = try s.stream.readIntLittle(usize);
                        const end_addr = try s.stream.readIntLittle(usize);
                        if (begin_addr == 0 and end_addr == 0) {
                            break;
                        }
                        // This entry selects a new value for the base address
                        if (begin_addr == math.maxInt(usize)) {
                            base_address = end_addr;
                            continue;
                        }
                        if (target_address >= base_address + begin_addr and target_address < base_address + end_addr) {
                            return compile_unit;
                        }
                    }
                } else |err| {
                    if (err != error.MissingDebugInfo) return err;
                    continue;
                }
            }
        }
        return error.MissingDebugInfo;
    }

    /// Gets an already existing AbbrevTable given the abbrev_offset, or if not found,
    /// seeks in the stream and parses it.
    fn getAbbrevTable(di: *DwarfInfo, abbrev_offset: u64) !*const AbbrevTable {
        for (di.abbrev_table_list.toSlice()) |*header| {
            if (header.offset == abbrev_offset) {
                return &header.table;
            }
        }
        try di.abbrev_table_list.append(AbbrevTableHeader{
            .offset = abbrev_offset,
            .table = try di.parseAbbrevTable(abbrev_offset),
        });
        return &di.abbrev_table_list.items[di.abbrev_table_list.len - 1].table;
    }

    fn parseAbbrevTable(di: *DwarfInfo, offset: u64) !AbbrevTable {
        var s = io.SliceSeekableInStream.init(di.debug_abbrev);

        try s.seekable_stream.seekTo(offset);
        var result = AbbrevTable.init(di.allocator());
        errdefer result.deinit();
        while (true) {
            const abbrev_code = try leb.readULEB128(u64, &s.stream);
            if (abbrev_code == 0) return result;
            try result.append(AbbrevTableEntry{
                .abbrev_code = abbrev_code,
                .tag_id = try leb.readULEB128(u64, &s.stream),
                .has_children = (try s.stream.readByte()) == CHILDREN_yes,
                .attrs = ArrayList(AbbrevAttr).init(di.allocator()),
            });
            const attrs = &result.items[result.len - 1].attrs;

            while (true) {
                const attr_id = try leb.readULEB128(u64, &s.stream);
                const form_id = try leb.readULEB128(u64, &s.stream);
                if (attr_id == 0 and form_id == 0) break;
                try attrs.append(AbbrevAttr{
                    .attr_id = attr_id,
                    .form_id = form_id,
                });
            }
        }
    }

    fn parseDie(di: *DwarfInfo, in_stream: var, abbrev_table: *const AbbrevTable, is_64: bool) !?Die {
        const abbrev_code = try leb.readULEB128(u64, in_stream);
        if (abbrev_code == 0) return null;
        const table_entry = getAbbrevTableEntry(abbrev_table, abbrev_code) orelse return error.InvalidDebugInfo;

        var result = Die{
            .tag_id = table_entry.tag_id,
            .has_children = table_entry.has_children,
            .attrs = ArrayList(Die.Attr).init(di.allocator()),
        };
        try result.attrs.resize(table_entry.attrs.len);
        for (table_entry.attrs.toSliceConst()) |attr, i| {
            result.attrs.items[i] = Die.Attr{
                .id = attr.attr_id,
                .value = try parseFormValue(di.allocator(), in_stream, attr.form_id, is_64),
            };
        }
        return result;
    }

    fn getLineNumberInfo(di: *DwarfInfo, compile_unit: CompileUnit, target_address: usize) !debug.LineInfo {
        var s = io.SliceSeekableInStream.init(di.debug_line);

        const compile_unit_cwd = try compile_unit.die.getAttrString(di, AT_comp_dir);
        const line_info_offset = try compile_unit.die.getAttrSecOffset(AT_stmt_list);

        try s.seekable_stream.seekTo(line_info_offset);

        var is_64: bool = undefined;
        const unit_length = try readInitialLength(@TypeOf(s.stream.readFn).ReturnType.ErrorSet, &s.stream, &is_64);
        if (unit_length == 0) {
            return error.MissingDebugInfo;
        }
        const next_offset = unit_length + (if (is_64) @as(usize, 12) else @as(usize, 4));

        const version = try s.stream.readInt(u16, di.endian);
        // TODO support 3 and 5
        if (version != 2 and version != 4) return error.InvalidDebugInfo;

        const prologue_length = if (is_64) try s.stream.readInt(u64, di.endian) else try s.stream.readInt(u32, di.endian);
        const prog_start_offset = (try s.seekable_stream.getPos()) + prologue_length;

        const minimum_instruction_length = try s.stream.readByte();
        if (minimum_instruction_length == 0) return error.InvalidDebugInfo;

        if (version >= 4) {
            // maximum_operations_per_instruction
            _ = try s.stream.readByte();
        }

        const default_is_stmt = (try s.stream.readByte()) != 0;
        const line_base = try s.stream.readByteSigned();

        const line_range = try s.stream.readByte();
        if (line_range == 0) return error.InvalidDebugInfo;

        const opcode_base = try s.stream.readByte();

        const standard_opcode_lengths = try di.allocator().alloc(u8, opcode_base - 1);
        defer di.allocator().free(standard_opcode_lengths);

        {
            var i: usize = 0;
            while (i < opcode_base - 1) : (i += 1) {
                standard_opcode_lengths[i] = try s.stream.readByte();
            }
        }

        var include_directories = ArrayList([]const u8).init(di.allocator());
        try include_directories.append(compile_unit_cwd);
        while (true) {
            const dir = try s.stream.readUntilDelimiterAlloc(di.allocator(), 0, math.maxInt(usize));
            if (dir.len == 0) break;
            try include_directories.append(dir);
        }

        var file_entries = ArrayList(FileEntry).init(di.allocator());
        var prog = LineNumberProgram.init(default_is_stmt, include_directories.toSliceConst(), &file_entries, target_address);

        while (true) {
            const file_name = try s.stream.readUntilDelimiterAlloc(di.allocator(), 0, math.maxInt(usize));
            if (file_name.len == 0) break;
            const dir_index = try leb.readULEB128(usize, &s.stream);
            const mtime = try leb.readULEB128(usize, &s.stream);
            const len_bytes = try leb.readULEB128(usize, &s.stream);
            try file_entries.append(FileEntry{
                .file_name = file_name,
                .dir_index = dir_index,
                .mtime = mtime,
                .len_bytes = len_bytes,
            });
        }

        try s.seekable_stream.seekTo(prog_start_offset);

        const next_unit_pos = line_info_offset + next_offset;

        while ((try s.seekable_stream.getPos()) < next_unit_pos) {
            const opcode = try s.stream.readByte();

            if (opcode == LNS_extended_op) {
                const op_size = try leb.readULEB128(u64, &s.stream);
                if (op_size < 1) return error.InvalidDebugInfo;
                var sub_op = try s.stream.readByte();
                switch (sub_op) {
                    LNE_end_sequence => {
                        prog.end_sequence = true;
                        if (try prog.checkLineMatch()) |info| return info;
                        prog.reset();
                    },
                    LNE_set_address => {
                        const addr = try s.stream.readInt(usize, di.endian);
                        prog.address = addr;
                    },
                    LNE_define_file => {
                        const file_name = try s.stream.readUntilDelimiterAlloc(di.allocator(), 0, math.maxInt(usize));
                        const dir_index = try leb.readULEB128(usize, &s.stream);
                        const mtime = try leb.readULEB128(usize, &s.stream);
                        const len_bytes = try leb.readULEB128(usize, &s.stream);
                        try file_entries.append(FileEntry{
                            .file_name = file_name,
                            .dir_index = dir_index,
                            .mtime = mtime,
                            .len_bytes = len_bytes,
                        });
                    },
                    else => {
                        const fwd_amt = math.cast(isize, op_size - 1) catch return error.InvalidDebugInfo;
                        try s.seekable_stream.seekBy(fwd_amt);
                    },
                }
            } else if (opcode >= opcode_base) {
                // special opcodes
                const adjusted_opcode = opcode - opcode_base;
                const inc_addr = minimum_instruction_length * (adjusted_opcode / line_range);
                const inc_line = @as(i32, line_base) + @as(i32, adjusted_opcode % line_range);
                prog.line += inc_line;
                prog.address += inc_addr;
                if (try prog.checkLineMatch()) |info| return info;
                prog.basic_block = false;
            } else {
                switch (opcode) {
                    LNS_copy => {
                        if (try prog.checkLineMatch()) |info| return info;
                        prog.basic_block = false;
                    },
                    LNS_advance_pc => {
                        const arg = try leb.readULEB128(usize, &s.stream);
                        prog.address += arg * minimum_instruction_length;
                    },
                    LNS_advance_line => {
                        const arg = try leb.readILEB128(i64, &s.stream);
                        prog.line += arg;
                    },
                    LNS_set_file => {
                        const arg = try leb.readULEB128(usize, &s.stream);
                        prog.file = arg;
                    },
                    LNS_set_column => {
                        const arg = try leb.readULEB128(u64, &s.stream);
                        prog.column = arg;
                    },
                    LNS_negate_stmt => {
                        prog.is_stmt = !prog.is_stmt;
                    },
                    LNS_set_basic_block => {
                        prog.basic_block = true;
                    },
                    LNS_const_add_pc => {
                        const inc_addr = minimum_instruction_length * ((255 - opcode_base) / line_range);
                        prog.address += inc_addr;
                    },
                    LNS_fixed_advance_pc => {
                        const arg = try s.stream.readInt(u16, di.endian);
                        prog.address += arg;
                    },
                    LNS_set_prologue_end => {},
                    else => {
                        if (opcode - 1 >= standard_opcode_lengths.len) return error.InvalidDebugInfo;
                        const len_bytes = standard_opcode_lengths[opcode - 1];
                        try s.seekable_stream.seekBy(len_bytes);
                    },
                }
            }
        }

        return error.MissingDebugInfo;
    }

    fn getString(di: *DwarfInfo, offset: u64) ![]const u8 {
        if (offset > di.debug_str.len)
            return error.InvalidDebugInfo;
        const casted_offset = math.cast(usize, offset) catch
            return error.InvalidDebugInfo;

        // Valid strings always have a terminating zero byte
        if (mem.indexOfScalarPos(u8, di.debug_str, casted_offset, 0)) |last| {
            return di.debug_str[casted_offset..last];
        }

        return error.InvalidDebugInfo;
    }
};

/// Initialize DWARF info. The caller has the responsibility to initialize most
/// the DwarfInfo fields before calling. These fields can be left undefined:
/// * abbrev_table_list
/// * compile_unit_list
pub fn openDwarfDebugInfo(di: *DwarfInfo, allocator: *mem.Allocator) !void {
    di.abbrev_table_list = ArrayList(AbbrevTableHeader).init(allocator);
    di.compile_unit_list = ArrayList(CompileUnit).init(allocator);
    di.func_list = ArrayList(Func).init(allocator);
    try di.scanAllFunctions();
    try di.scanAllCompileUnits();
}

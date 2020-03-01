const std = @import("std.zig");
const math = std.math;
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const mem = std.mem;
const builtin = @import("builtin");
const errol = @import("fmt/errol.zig");
const lossyCast = std.math.lossyCast;

pub const default_max_depth = 3;

pub const Alignment = enum {
    Left,
    Center,
    Right,
};

pub const FormatOptions = struct {
    precision: ?usize = null,
    width: ?usize = null,
    alignment: ?Alignment = null,
    fill: u8 = ' ',
};

fn nextArg(comptime used_pos_args: *u32, comptime maybe_pos_arg: ?comptime_int, comptime next_arg: *comptime_int) comptime_int {
    if (maybe_pos_arg) |pos_arg| {
        used_pos_args.* |= 1 << pos_arg;
        return pos_arg;
    } else {
        const arg = next_arg.*;
        next_arg.* += 1;
        return arg;
    }
}

fn peekIsAlign(comptime fmt: []const u8) bool {
    // Should only be called during a state transition to the format segment.
    std.debug.assert(fmt[0] == ':');

    inline for (([_]u8{ 1, 2 })[0..]) |i| {
        if (fmt.len > i and (fmt[i] == '<' or fmt[i] == '^' or fmt[i] == '>')) {
            return true;
        }
    }
    return false;
}

/// Renders fmt string with args, calling output with slices of bytes.
/// If `output` returns an error, the error is returned from `format` and
/// `output` is not called again.
pub fn format(
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
    comptime fmt: []const u8,
    args: ...,
) Errors!void {
    const ArgSetType = @IntType(false, 32);
    if (args.len > ArgSetType.bit_count) {
        @compileError("32 arguments max are supported per format call");
    }

    const State = enum {
        Start,
        Positional,
        CloseBrace,
        Specifier,
        FormatFillAndAlign,
        FormatWidth,
        FormatPrecision,
    };

    comptime var start_index = 0;
    comptime var state = State.Start;
    comptime var next_arg = 0;
    comptime var maybe_pos_arg: ?comptime_int = null;
    comptime var used_pos_args: ArgSetType = 0;
    comptime var specifier_start = 0;
    comptime var specifier_end = 0;
    comptime var options = FormatOptions{};

    inline for (fmt) |c, i| {
        switch (state) {
            .Start => switch (c) {
                '{' => {
                    if (start_index < i) {
                        try output(context, fmt[start_index..i]);
                    }

                    start_index = i;
                    specifier_start = i + 1;
                    specifier_end = i + 1;
                    maybe_pos_arg = null;
                    state = .Positional;
                    options = FormatOptions{};
                },
                '}' => {
                    if (start_index < i) {
                        try output(context, fmt[start_index..i]);
                    }
                    state = .CloseBrace;
                },
                else => {},
            },
            .Positional => switch (c) {
                '{' => {
                    state = .Start;
                    start_index = i;
                },
                ':' => {
                    state = if (comptime peekIsAlign(fmt[i..])) State.FormatFillAndAlign else State.FormatWidth;
                    specifier_end = i;
                },
                '0'...'9' => {
                    if (maybe_pos_arg == null) {
                        maybe_pos_arg = 0;
                    }

                    maybe_pos_arg.? *= 10;
                    maybe_pos_arg.? += c - '0';
                    specifier_start = i + 1;

                    if (maybe_pos_arg.? >= args.len) {
                        @compileError("Positional value refers to non-existent argument");
                    }
                },
                '}' => {
                    const arg_to_print = comptime nextArg(&used_pos_args, maybe_pos_arg, &next_arg);

                    try formatType(
                        args[arg_to_print],
                        fmt[0..0],
                        options,
                        context,
                        Errors,
                        output,
                        default_max_depth,
                    );

                    state = .Start;
                    start_index = i + 1;
                },
                else => {
                    state = .Specifier;
                    specifier_start = i;
                },
            },
            .CloseBrace => switch (c) {
                '}' => {
                    state = .Start;
                    start_index = i;
                },
                else => @compileError("Single '}' encountered in format string"),
            },
            .Specifier => switch (c) {
                ':' => {
                    specifier_end = i;
                    state = if (comptime peekIsAlign(fmt[i..])) State.FormatFillAndAlign else State.FormatWidth;
                },
                '}' => {
                    const arg_to_print = comptime nextArg(&used_pos_args, maybe_pos_arg, &next_arg);

                    try formatType(
                        args[arg_to_print],
                        fmt[specifier_start..i],
                        options,
                        context,
                        Errors,
                        output,
                        default_max_depth,
                    );
                    state = .Start;
                    start_index = i + 1;
                },
                else => {},
            },
            // Only entered if the format string contains a fill/align segment.
            .FormatFillAndAlign => switch (c) {
                '<' => {
                    options.alignment = Alignment.Left;
                    state = .FormatWidth;
                },
                '^' => {
                    options.alignment = Alignment.Center;
                    state = .FormatWidth;
                },
                '>' => {
                    options.alignment = Alignment.Right;
                    state = .FormatWidth;
                },
                else => {
                    options.fill = c;
                },
            },
            .FormatWidth => switch (c) {
                '0'...'9' => {
                    if (options.width == null) {
                        options.width = 0;
                    }

                    options.width.? *= 10;
                    options.width.? += c - '0';
                },
                '.' => {
                    state = .FormatPrecision;
                },
                '}' => {
                    const arg_to_print = comptime nextArg(&used_pos_args, maybe_pos_arg, &next_arg);

                    try formatType(
                        args[arg_to_print],
                        fmt[specifier_start..specifier_end],
                        options,
                        context,
                        Errors,
                        output,
                        default_max_depth,
                    );
                    state = .Start;
                    start_index = i + 1;
                },
                else => {
                    @compileError("Unexpected character in width value: " ++ [_]u8{c});
                },
            },
            .FormatPrecision => switch (c) {
                '0'...'9' => {
                    if (options.precision == null) {
                        options.precision = 0;
                    }

                    options.precision.? *= 10;
                    options.precision.? += c - '0';
                },
                '}' => {
                    const arg_to_print = comptime nextArg(&used_pos_args, maybe_pos_arg, &next_arg);

                    try formatType(
                        args[arg_to_print],
                        fmt[specifier_start..specifier_end],
                        options,
                        context,
                        Errors,
                        output,
                        default_max_depth,
                    );
                    state = .Start;
                    start_index = i + 1;
                },
                else => {
                    @compileError("Unexpected character in precision value: " ++ [_]u8{c});
                },
            },
        }
    }
    comptime {
        // All arguments must have been printed but we allow mixing positional and fixed to achieve this.
        var i: usize = 0;
        inline while (i < next_arg) : (i += 1) {
            used_pos_args |= 1 << i;
        }

        if (@popCount(ArgSetType, used_pos_args) != args.len) {
            @compileError("Unused arguments");
        }
        if (state != State.Start) {
            @compileError("Incomplete format string: " ++ fmt);
        }
    }
    if (start_index < fmt.len) {
        try output(context, fmt[start_index..]);
    }
}

pub fn formatType(
    value: var,
    comptime fmt: []const u8,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
    max_depth: usize,
) Errors!void {
    if (comptime std.mem.eql(u8, fmt, "*")) {
        try output(context, @typeName(@typeOf(value).Child));
        try output(context, "@");
        try formatInt(@ptrToInt(value), 16, false, FormatOptions{}, context, Errors, output);
        return;
    }

    const T = @typeOf(value);
    switch (@typeInfo(T)) {
        .ComptimeInt, .Int, .Float => {
            return formatValue(value, fmt, options, context, Errors, output);
        },
        .Void => {
            return output(context, "void");
        },
        .Bool => {
            return output(context, if (value) "true" else "false");
        },
        .Optional => {
            if (value) |payload| {
                return formatType(payload, fmt, options, context, Errors, output, max_depth);
            } else {
                return output(context, "null");
            }
        },
        .ErrorUnion => {
            if (value) |payload| {
                return formatType(payload, fmt, options, context, Errors, output, max_depth);
            } else |err| {
                return formatType(err, fmt, options, context, Errors, output, max_depth);
            }
        },
        .ErrorSet => {
            try output(context, "error.");
            return output(context, @errorName(value));
        },
        .Enum => {
            if (comptime std.meta.trait.hasFn("format")(T)) {
                return value.format(fmt, options, context, Errors, output);
            }

            try output(context, @typeName(T));
            try output(context, ".");
            return formatType(@tagName(value), "", options, context, Errors, output, max_depth);
        },
        .Union => {
            if (comptime std.meta.trait.hasFn("format")(T)) {
                return value.format(fmt, options, context, Errors, output);
            }

            try output(context, @typeName(T));
            if (max_depth == 0) {
                return output(context, "{ ... }");
            }
            const info = @typeInfo(T).Union;
            if (info.tag_type) |UnionTagType| {
                try output(context, "{ .");
                try output(context, @tagName(UnionTagType(value)));
                try output(context, " = ");
                inline for (info.fields) |u_field| {
                    if (@enumToInt(UnionTagType(value)) == u_field.enum_field.?.value) {
                        try formatType(@field(value, u_field.name), "", options, context, Errors, output, max_depth - 1);
                    }
                }
                try output(context, " }");
            } else {
                try format(context, Errors, output, "@{x}", @ptrToInt(&value));
            }
        },
        .Struct => {
            if (comptime std.meta.trait.hasFn("format")(T)) {
                return value.format(fmt, options, context, Errors, output);
            }

            try output(context, @typeName(T));
            if (max_depth == 0) {
                return output(context, "{ ... }");
            }
            comptime var field_i = 0;
            try output(context, "{");
            inline while (field_i < @memberCount(T)) : (field_i += 1) {
                if (field_i == 0) {
                    try output(context, " .");
                } else {
                    try output(context, ", .");
                }
                try output(context, @memberName(T, field_i));
                try output(context, " = ");
                try formatType(@field(value, @memberName(T, field_i)), "", options, context, Errors, output, max_depth - 1);
            }
            try output(context, " }");
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                builtin.TypeId.Array => |info| {
                    if (info.child == u8) {
                        return formatText(value, fmt, options, context, Errors, output);
                    }
                    return format(context, Errors, output, "{}@{x}", @typeName(T.Child), @ptrToInt(value));
                },
                builtin.TypeId.Enum, builtin.TypeId.Union, builtin.TypeId.Struct => {
                    return formatType(value.*, fmt, options, context, Errors, output, max_depth);
                },
                else => return format(context, Errors, output, "{}@{x}", @typeName(T.Child), @ptrToInt(value)),
            },
            .Many => {
                if (ptr_info.child == u8) {
                    if (fmt.len > 0 and fmt[0] == 's') {
                        const len = mem.len(u8, value);
                        return formatText(value[0..len], fmt, options, context, Errors, output);
                    }
                }
                return format(context, Errors, output, "{}@{x}", @typeName(T.Child), @ptrToInt(value));
            },
            .Slice => {
                if (fmt.len > 0 and ((fmt[0] == 'x') or (fmt[0] == 'X'))) {
                    return formatText(value, fmt, options, context, Errors, output);
                }
                if (ptr_info.child == u8) {
                    return formatText(value, fmt, options, context, Errors, output);
                }
                return format(context, Errors, output, "{}@{x}", @typeName(ptr_info.child), @ptrToInt(value.ptr));
            },
            .C => {
                return format(context, Errors, output, "{}@{x}", @typeName(T.Child), @ptrToInt(value));
            },
        },
        .Array => |info| {
            if (info.child == u8) {
                return formatText(value, fmt, options, context, Errors, output);
            }
            if (value.len == 0) {
                return format(context, Errors, output, "[0]{}", @typeName(T.Child));
            }
            return format(context, Errors, output, "{}@{x}", @typeName(T.Child), @ptrToInt(&value));
        },
        .Fn => {
            return format(context, Errors, output, "{}@{x}", @typeName(T), @ptrToInt(value));
        },
        else => @compileError("Unable to format type '" ++ @typeName(T) ++ "'"),
    }
}

fn formatValue(
    value: var,
    comptime fmt: []const u8,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    if (comptime std.mem.eql(u8, fmt, "B")) {
        return formatBytes(value, options, 1000, context, Errors, output);
    } else if (comptime std.mem.eql(u8, fmt, "Bi")) {
        return formatBytes(value, options, 1024, context, Errors, output);
    }

    const T = @typeOf(value);
    switch (@typeId(T)) {
        .Float => return formatFloatValue(value, fmt, options, context, Errors, output),
        .Int, .ComptimeInt => return formatIntValue(value, fmt, options, context, Errors, output),
        else => comptime unreachable,
    }
}

pub fn formatIntValue(
    value: var,
    comptime fmt: []const u8,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    comptime var radix = 10;
    comptime var uppercase = false;

    const int_value = if (@typeOf(value) == comptime_int) blk: {
        const Int = math.IntFittingRange(value, value);
        break :blk Int(value);
    } else
        value;

    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "d")) {
        radix = 10;
        uppercase = false;
    } else if (comptime std.mem.eql(u8, fmt, "c")) {
        if (@typeOf(int_value).bit_count <= 8) {
            return formatAsciiChar(u8(int_value), options, context, Errors, output);
        } else {
            @compileError("Cannot print integer that is larger than 8 bits as a ascii");
        }
    } else if (comptime std.mem.eql(u8, fmt, "b")) {
        radix = 2;
        uppercase = false;
    } else if (comptime std.mem.eql(u8, fmt, "x")) {
        radix = 16;
        uppercase = false;
    } else if (comptime std.mem.eql(u8, fmt, "X")) {
        radix = 16;
        uppercase = true;
    } else {
        @compileError("Unknown format string: '" ++ fmt ++ "'");
    }

    return formatInt(int_value, radix, uppercase, options, context, Errors, output);
}

fn formatFloatValue(
    value: var,
    comptime fmt: []const u8,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "e")) {
        return formatFloatScientific(value, options, context, Errors, output);
    } else if (comptime std.mem.eql(u8, fmt, "d")) {
        return formatFloatDecimal(value, options, context, Errors, output);
    } else {
        @compileError("Unknown format string: '" ++ fmt ++ "'");
    }
}

pub fn formatText(
    bytes: []const u8,
    comptime fmt: []const u8,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    if (fmt.len == 0) {
        return output(context, bytes);
    } else if (comptime std.mem.eql(u8, fmt, "s")) {
        return formatBuf(bytes, options, context, Errors, output);
    } else if (comptime (std.mem.eql(u8, fmt, "x") or std.mem.eql(u8, fmt, "X"))) {
        for (bytes) |c| {
            try formatInt(c, 16, fmt[0] == 'X', FormatOptions{ .width = 2, .fill = '0' }, context, Errors, output);
        }
        return;
    } else {
        @compileError("Unknown format string: '" ++ fmt ++ "'");
    }
}

pub fn formatAsciiChar(
    c: u8,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    return output(context, (*const [1]u8)(&c)[0..]);
}

pub fn formatBuf(
    buf: []const u8,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    try output(context, buf);

    const width = options.width orelse 0;
    var leftover_padding = if (width > buf.len) (width - buf.len) else return;
    const pad_byte: u8 = options.fill;
    while (leftover_padding > 0) : (leftover_padding -= 1) {
        try output(context, (*const [1]u8)(&pad_byte)[0..1]);
    }
}

// Print a float in scientific notation to the specified precision. Null uses full precision.
// It should be the case that every full precision, printed value can be re-parsed back to the
// same type unambiguously.
pub fn formatFloatScientific(
    value: var,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    var x = @floatCast(f64, value);

    // Errol doesn't handle these special cases.
    if (math.signbit(x)) {
        try output(context, "-");
        x = -x;
    }

    if (math.isNan(x)) {
        return output(context, "nan");
    }
    if (math.isPositiveInf(x)) {
        return output(context, "inf");
    }
    if (x == 0.0) {
        try output(context, "0");

        if (options.precision) |precision| {
            if (precision != 0) {
                try output(context, ".");
                var i: usize = 0;
                while (i < precision) : (i += 1) {
                    try output(context, "0");
                }
            }
        } else {
            try output(context, ".0");
        }

        try output(context, "e+00");
        return;
    }

    var buffer: [32]u8 = undefined;
    var float_decimal = errol.errol3(x, buffer[0..]);

    if (options.precision) |precision| {
        errol.roundToPrecision(&float_decimal, precision, errol.RoundMode.Scientific);

        try output(context, float_decimal.digits[0..1]);

        // {e0} case prints no `.`
        if (precision != 0) {
            try output(context, ".");

            var printed: usize = 0;
            if (float_decimal.digits.len > 1) {
                const num_digits = math.min(float_decimal.digits.len, precision + 1);
                try output(context, float_decimal.digits[1..num_digits]);
                printed += num_digits - 1;
            }

            while (printed < precision) : (printed += 1) {
                try output(context, "0");
            }
        }
    } else {
        try output(context, float_decimal.digits[0..1]);
        try output(context, ".");
        if (float_decimal.digits.len > 1) {
            const num_digits = if (@typeOf(value) == f32) math.min(usize(9), float_decimal.digits.len) else float_decimal.digits.len;

            try output(context, float_decimal.digits[1..num_digits]);
        } else {
            try output(context, "0");
        }
    }

    try output(context, "e");
    const exp = float_decimal.exp - 1;

    if (exp >= 0) {
        try output(context, "+");
        if (exp > -10 and exp < 10) {
            try output(context, "0");
        }
        try formatInt(exp, 10, false, FormatOptions{ .width = 0 }, context, Errors, output);
    } else {
        try output(context, "-");
        if (exp > -10 and exp < 10) {
            try output(context, "0");
        }
        try formatInt(-exp, 10, false, FormatOptions{ .width = 0 }, context, Errors, output);
    }
}

// Print a float of the format x.yyyyy where the number of y is specified by the precision argument.
// By default floats are printed at full precision (no rounding).
pub fn formatFloatDecimal(
    value: var,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    var x = f64(value);

    // Errol doesn't handle these special cases.
    if (math.signbit(x)) {
        try output(context, "-");
        x = -x;
    }

    if (math.isNan(x)) {
        return output(context, "nan");
    }
    if (math.isPositiveInf(x)) {
        return output(context, "inf");
    }
    if (x == 0.0) {
        try output(context, "0");

        if (options.precision) |precision| {
            if (precision != 0) {
                try output(context, ".");
                var i: usize = 0;
                while (i < precision) : (i += 1) {
                    try output(context, "0");
                }
            } else {
                try output(context, ".0");
            }
        } else {
            try output(context, "0");
        }

        return;
    }

    // non-special case, use errol3
    var buffer: [32]u8 = undefined;
    var float_decimal = errol.errol3(x, buffer[0..]);

    if (options.precision) |precision| {
        errol.roundToPrecision(&float_decimal, precision, errol.RoundMode.Decimal);

        // exp < 0 means the leading is always 0 as errol result is normalized.
        var num_digits_whole = if (float_decimal.exp > 0) @intCast(usize, float_decimal.exp) else 0;

        // the actual slice into the buffer, we may need to zero-pad between num_digits_whole and this.
        var num_digits_whole_no_pad = math.min(num_digits_whole, float_decimal.digits.len);

        if (num_digits_whole > 0) {
            // We may have to zero pad, for instance 1e4 requires zero padding.
            try output(context, float_decimal.digits[0..num_digits_whole_no_pad]);

            var i = num_digits_whole_no_pad;
            while (i < num_digits_whole) : (i += 1) {
                try output(context, "0");
            }
        } else {
            try output(context, "0");
        }

        // {.0} special case doesn't want a trailing '.'
        if (precision == 0) {
            return;
        }

        try output(context, ".");

        // Keep track of fractional count printed for case where we pre-pad then post-pad with 0's.
        var printed: usize = 0;

        // Zero-fill until we reach significant digits or run out of precision.
        if (float_decimal.exp <= 0) {
            const zero_digit_count = @intCast(usize, -float_decimal.exp);
            const zeros_to_print = math.min(zero_digit_count, precision);

            var i: usize = 0;
            while (i < zeros_to_print) : (i += 1) {
                try output(context, "0");
                printed += 1;
            }

            if (printed >= precision) {
                return;
            }
        }

        // Remaining fractional portion, zero-padding if insufficient.
        assert(precision >= printed);
        if (num_digits_whole_no_pad + precision - printed < float_decimal.digits.len) {
            try output(context, float_decimal.digits[num_digits_whole_no_pad .. num_digits_whole_no_pad + precision - printed]);
            return;
        } else {
            try output(context, float_decimal.digits[num_digits_whole_no_pad..]);
            printed += float_decimal.digits.len - num_digits_whole_no_pad;

            while (printed < precision) : (printed += 1) {
                try output(context, "0");
            }
        }
    } else {
        // exp < 0 means the leading is always 0 as errol result is normalized.
        var num_digits_whole = if (float_decimal.exp > 0) @intCast(usize, float_decimal.exp) else 0;

        // the actual slice into the buffer, we may need to zero-pad between num_digits_whole and this.
        var num_digits_whole_no_pad = math.min(num_digits_whole, float_decimal.digits.len);

        if (num_digits_whole > 0) {
            // We may have to zero pad, for instance 1e4 requires zero padding.
            try output(context, float_decimal.digits[0..num_digits_whole_no_pad]);

            var i = num_digits_whole_no_pad;
            while (i < num_digits_whole) : (i += 1) {
                try output(context, "0");
            }
        } else {
            try output(context, "0");
        }

        // Omit `.` if no fractional portion
        if (float_decimal.exp >= 0 and num_digits_whole_no_pad == float_decimal.digits.len) {
            return;
        }

        try output(context, ".");

        // Zero-fill until we reach significant digits or run out of precision.
        if (float_decimal.exp < 0) {
            const zero_digit_count = @intCast(usize, -float_decimal.exp);

            var i: usize = 0;
            while (i < zero_digit_count) : (i += 1) {
                try output(context, "0");
            }
        }

        try output(context, float_decimal.digits[num_digits_whole_no_pad..]);
    }
}

pub fn formatBytes(
    value: var,
    options: FormatOptions,
    comptime radix: usize,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    if (value == 0) {
        return output(context, "0B");
    }

    const mags_si = " kMGTPEZY";
    const mags_iec = " KMGTPEZY";
    const magnitude = switch (radix) {
        1000 => math.min(math.log2(value) / comptime math.log2(1000), mags_si.len - 1),
        1024 => math.min(math.log2(value) / 10, mags_iec.len - 1),
        else => unreachable,
    };
    const new_value = lossyCast(f64, value) / math.pow(f64, lossyCast(f64, radix), lossyCast(f64, magnitude));
    const suffix = switch (radix) {
        1000 => mags_si[magnitude],
        1024 => mags_iec[magnitude],
        else => unreachable,
    };

    try formatFloatDecimal(new_value, options, context, Errors, output);

    if (suffix == ' ') {
        return output(context, "B");
    }

    const buf = switch (radix) {
        1000 => [_]u8{ suffix, 'B' },
        1024 => [_]u8{ suffix, 'i', 'B' },
        else => unreachable,
    };
    return output(context, buf);
}

pub fn formatInt(
    value: var,
    base: u8,
    uppercase: bool,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    const int_value = if (@typeOf(value) == comptime_int) blk: {
        const Int = math.IntFittingRange(value, value);
        break :blk Int(value);
    } else
        value;

    if (@typeOf(int_value).is_signed) {
        return formatIntSigned(int_value, base, uppercase, options, context, Errors, output);
    } else {
        return formatIntUnsigned(int_value, base, uppercase, options, context, Errors, output);
    }
}

fn formatIntSigned(
    value: var,
    base: u8,
    uppercase: bool,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    const new_options = FormatOptions{
        .width = if (options.width) |w| (if (w == 0) 0 else w - 1) else null,
        .precision = options.precision,
        .fill = options.fill,
    };

    const uint = @IntType(false, @typeOf(value).bit_count);
    if (value < 0) {
        const minus_sign: u8 = '-';
        try output(context, (*const [1]u8)(&minus_sign)[0..]);
        const new_value = @intCast(uint, -(value + 1)) + 1;
        return formatIntUnsigned(new_value, base, uppercase, new_options, context, Errors, output);
    } else if (options.width == null or options.width.? == 0) {
        return formatIntUnsigned(@intCast(uint, value), base, uppercase, options, context, Errors, output);
    } else {
        const plus_sign: u8 = '+';
        try output(context, (*const [1]u8)(&plus_sign)[0..]);
        const new_value = @intCast(uint, value);
        return formatIntUnsigned(new_value, base, uppercase, new_options, context, Errors, output);
    }
}

fn formatIntUnsigned(
    value: var,
    base: u8,
    uppercase: bool,
    options: FormatOptions,
    context: var,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
) Errors!void {
    assert(base >= 2);
    var buf: [math.max(@typeOf(value).bit_count, 1)]u8 = undefined;
    const min_int_bits = comptime math.max(@typeOf(value).bit_count, @typeOf(base).bit_count);
    const MinInt = @IntType(@typeOf(value).is_signed, min_int_bits);
    var a: MinInt = value;
    var index: usize = buf.len;

    while (true) {
        const digit = a % base;
        index -= 1;
        buf[index] = digitToChar(@intCast(u8, digit), uppercase);
        a /= base;
        if (a == 0) break;
    }

    const digits_buf = buf[index..];
    const width = options.width orelse 0;
    const padding = if (width > digits_buf.len) (width - digits_buf.len) else 0;

    if (padding > index) {
        const zero_byte: u8 = options.fill;
        var leftover_padding = padding - index;
        while (true) {
            try output(context, (*const [1]u8)(&zero_byte)[0..]);
            leftover_padding -= 1;
            if (leftover_padding == 0) break;
        }
        mem.set(u8, buf[0..index], options.fill);
        return output(context, buf);
    } else {
        const padded_buf = buf[index - padding ..];
        mem.set(u8, padded_buf[0..padding], options.fill);
        return output(context, padded_buf);
    }
}

pub fn formatIntBuf(out_buf: []u8, value: var, base: u8, uppercase: bool, options: FormatOptions) usize {
    var context = FormatIntBuf{
        .out_buf = out_buf,
        .index = 0,
    };
    formatInt(value, base, uppercase, options, &context, error{}, formatIntCallback) catch unreachable;
    return context.index;
}
const FormatIntBuf = struct {
    out_buf: []u8,
    index: usize,
};
fn formatIntCallback(context: *FormatIntBuf, bytes: []const u8) (error{}!void) {
    mem.copy(u8, context.out_buf[context.index..], bytes);
    context.index += bytes.len;
}

pub fn parseInt(comptime T: type, buf: []const u8, radix: u8) !T {
    if (!T.is_signed) return parseUnsigned(T, buf, radix);
    if (buf.len == 0) return T(0);
    if (buf[0] == '-') {
        return math.negate(try parseUnsigned(T, buf[1..], radix));
    } else if (buf[0] == '+') {
        return parseUnsigned(T, buf[1..], radix);
    } else {
        return parseUnsigned(T, buf, radix);
    }
}

test "parseInt" {
    testing.expect((parseInt(i32, "-10", 10) catch unreachable) == -10);
    testing.expect((parseInt(i32, "+10", 10) catch unreachable) == 10);
    testing.expect(if (parseInt(i32, " 10", 10)) |_| false else |err| err == error.InvalidCharacter);
    testing.expect(if (parseInt(i32, "10 ", 10)) |_| false else |err| err == error.InvalidCharacter);
    testing.expect(if (parseInt(u32, "-10", 10)) |_| false else |err| err == error.InvalidCharacter);
    testing.expect((parseInt(u8, "255", 10) catch unreachable) == 255);
    testing.expect(if (parseInt(u8, "256", 10)) |_| false else |err| err == error.Overflow);
}

const ParseUnsignedError = error{
    /// The result cannot fit in the type specified
    Overflow,

    /// The input had a byte that was not a digit
    InvalidCharacter,
};

pub fn parseUnsigned(comptime T: type, buf: []const u8, radix: u8) ParseUnsignedError!T {
    var x: T = 0;

    for (buf) |c| {
        const digit = try charToDigit(c, radix);

        if (x != 0) x = try math.mul(T, x, try math.cast(T, radix));
        x = try math.add(T, x, try math.cast(T, digit));
    }

    return x;
}

test "parseUnsigned" {
    testing.expect((try parseUnsigned(u16, "050124", 10)) == 50124);
    testing.expect((try parseUnsigned(u16, "65535", 10)) == 65535);
    testing.expectError(error.Overflow, parseUnsigned(u16, "65536", 10));

    testing.expect((try parseUnsigned(u64, "0ffffffffffffffff", 16)) == 0xffffffffffffffff);
    testing.expectError(error.Overflow, parseUnsigned(u64, "10000000000000000", 16));

    testing.expect((try parseUnsigned(u32, "DeadBeef", 16)) == 0xDEADBEEF);

    testing.expect((try parseUnsigned(u7, "1", 10)) == 1);
    testing.expect((try parseUnsigned(u7, "1000", 2)) == 8);

    testing.expectError(error.InvalidCharacter, parseUnsigned(u32, "f", 10));
    testing.expectError(error.InvalidCharacter, parseUnsigned(u8, "109", 8));

    testing.expect((try parseUnsigned(u32, "NUMBER", 36)) == 1442151747);

    // these numbers should fit even though the radix itself doesn't fit in the destination type
    testing.expect((try parseUnsigned(u1, "0", 10)) == 0);
    testing.expect((try parseUnsigned(u1, "1", 10)) == 1);
    testing.expectError(error.Overflow, parseUnsigned(u1, "2", 10));
    testing.expect((try parseUnsigned(u1, "001", 16)) == 1);
    testing.expect((try parseUnsigned(u2, "3", 16)) == 3);
    testing.expectError(error.Overflow, parseUnsigned(u2, "4", 16));
}

pub const parseFloat = @import("fmt/parse_float.zig").parseFloat;

test "parseFloat" {
    _ = @import("fmt/parse_float.zig");
}

pub fn charToDigit(c: u8, radix: u8) (error{InvalidCharacter}!u8) {
    const value = switch (c) {
        '0'...'9' => c - '0',
        'A'...'Z' => c - 'A' + 10,
        'a'...'z' => c - 'a' + 10,
        else => return error.InvalidCharacter,
    };

    if (value >= radix) return error.InvalidCharacter;

    return value;
}

fn digitToChar(digit: u8, uppercase: bool) u8 {
    return switch (digit) {
        0...9 => digit + '0',
        10...35 => digit + ((if (uppercase) u8('A') else u8('a')) - 10),
        else => unreachable,
    };
}

const BufPrintContext = struct {
    remaining: []u8,
};

fn bufPrintWrite(context: *BufPrintContext, bytes: []const u8) !void {
    if (context.remaining.len < bytes.len) return error.BufferTooSmall;
    mem.copy(u8, context.remaining, bytes);
    context.remaining = context.remaining[bytes.len..];
}

pub fn bufPrint(buf: []u8, comptime fmt: []const u8, args: ...) ![]u8 {
    var context = BufPrintContext{ .remaining = buf };
    try format(&context, error{BufferTooSmall}, bufPrintWrite, fmt, args);
    return buf[0 .. buf.len - context.remaining.len];
}

pub const AllocPrintError = error{OutOfMemory};

pub fn allocPrint(allocator: *mem.Allocator, comptime fmt: []const u8, args: ...) AllocPrintError![]u8 {
    var size: usize = 0;
    format(&size, error{}, countSize, fmt, args) catch |err| switch (err) {};
    const buf = try allocator.alloc(u8, size);
    return bufPrint(buf, fmt, args) catch |err| switch (err) {
        error.BufferTooSmall => unreachable, // we just counted the size above
    };
}

fn countSize(size: *usize, bytes: []const u8) (error{}!void) {
    size.* += bytes.len;
}

test "bufPrintInt" {
    var buffer: [100]u8 = undefined;
    const buf = buffer[0..];
    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, i32(-12345678), 2, false, FormatOptions{}), "-101111000110000101001110"));
    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, i32(-12345678), 10, false, FormatOptions{}), "-12345678"));
    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, i32(-12345678), 16, false, FormatOptions{}), "-bc614e"));
    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, i32(-12345678), 16, true, FormatOptions{}), "-BC614E"));

    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, u32(12345678), 10, true, FormatOptions{}), "12345678"));

    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, u32(666), 10, false, FormatOptions{ .width = 6 }), "   666"));
    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, u32(0x1234), 16, false, FormatOptions{ .width = 6 }), "  1234"));
    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, u32(0x1234), 16, false, FormatOptions{ .width = 1 }), "1234"));

    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, i32(42), 10, false, FormatOptions{ .width = 3 }), "+42"));
    testing.expect(mem.eql(u8, bufPrintIntToSlice(buf, i32(-42), 10, false, FormatOptions{ .width = 3 }), "-42"));
}

fn bufPrintIntToSlice(buf: []u8, value: var, base: u8, uppercase: bool, options: FormatOptions) []u8 {
    return buf[0..formatIntBuf(buf, value, base, uppercase, options)];
}

test "parse u64 digit too big" {
    _ = parseUnsigned(u64, "123a", 10) catch |err| {
        if (err == error.InvalidCharacter) return;
        unreachable;
    };
    unreachable;
}

test "parse unsigned comptime" {
    comptime {
        testing.expect((try parseUnsigned(usize, "2", 10)) == 2);
    }
}

test "optional" {
    {
        const value: ?i32 = 1234;
        try testFmt("optional: 1234\n", "optional: {}\n", value);
    }
    {
        const value: ?i32 = null;
        try testFmt("optional: null\n", "optional: {}\n", value);
    }
}

test "error" {
    {
        const value: anyerror!i32 = 1234;
        try testFmt("error union: 1234\n", "error union: {}\n", value);
    }
    {
        const value: anyerror!i32 = error.InvalidChar;
        try testFmt("error union: error.InvalidChar\n", "error union: {}\n", value);
    }
}

test "int.small" {
    {
        const value: u3 = 0b101;
        try testFmt("u3: 5\n", "u3: {}\n", value);
    }
}

test "int.specifier" {
    {
        const value: u8 = 'a';
        try testFmt("u8: a\n", "u8: {c}\n", value);
    }
    {
        const value: u8 = 0b1100;
        try testFmt("u8: 0b1100\n", "u8: 0b{b}\n", value);
    }
}

test "int.padded" {
    try testFmt("u8: '   1'", "u8: '{:4}'", u8(1));
    try testFmt("u8: 'xxx1'", "u8: '{:x<4}'", u8(1));
}

test "buffer" {
    {
        var buf1: [32]u8 = undefined;
        var context = BufPrintContext{ .remaining = buf1[0..] };
        try formatType(1234, "", FormatOptions{}, &context, error{BufferTooSmall}, bufPrintWrite, default_max_depth);
        var res = buf1[0 .. buf1.len - context.remaining.len];
        testing.expect(mem.eql(u8, res, "1234"));

        context = BufPrintContext{ .remaining = buf1[0..] };
        try formatType('a', "c", FormatOptions{}, &context, error{BufferTooSmall}, bufPrintWrite, default_max_depth);
        res = buf1[0 .. buf1.len - context.remaining.len];
        testing.expect(mem.eql(u8, res, "a"));

        context = BufPrintContext{ .remaining = buf1[0..] };
        try formatType(0b1100, "b", FormatOptions{}, &context, error{BufferTooSmall}, bufPrintWrite, default_max_depth);
        res = buf1[0 .. buf1.len - context.remaining.len];
        testing.expect(mem.eql(u8, res, "1100"));
    }
}

test "array" {
    {
        const value: [3]u8 = "abc";
        try testFmt("array: abc\n", "array: {}\n", value);
        try testFmt("array: abc\n", "array: {}\n", &value);

        var buf: [100]u8 = undefined;
        try testFmt(
            try bufPrint(buf[0..], "array: [3]u8@{x}\n", @ptrToInt(&value)),
            "array: {*}\n",
            &value,
        );
    }
}

test "slice" {
    {
        const value: []const u8 = "abc";
        try testFmt("slice: abc\n", "slice: {}\n", value);
    }
    {
        const value = @intToPtr([*]const []const u8, 0xdeadbeef)[0..0];
        try testFmt("slice: []const u8@deadbeef\n", "slice: {}\n", value);
    }

    try testFmt("buf: Test \n", "buf: {s:5}\n", "Test");
    try testFmt("buf: Test\n Other text", "buf: {s}\n Other text", "Test");
}

test "pointer" {
    {
        const value = @intToPtr(*i32, 0xdeadbeef);
        try testFmt("pointer: i32@deadbeef\n", "pointer: {}\n", value);
        try testFmt("pointer: i32@deadbeef\n", "pointer: {*}\n", value);
    }
    {
        const value = @intToPtr(fn () void, 0xdeadbeef);
        try testFmt("pointer: fn() void@deadbeef\n", "pointer: {}\n", value);
    }
    {
        const value = @intToPtr(fn () void, 0xdeadbeef);
        try testFmt("pointer: fn() void@deadbeef\n", "pointer: {}\n", value);
    }
}

test "cstr" {
    try testFmt("cstr: Test C\n", "cstr: {s}\n", c"Test C");
    try testFmt("cstr: Test C    \n", "cstr: {s:10}\n", c"Test C");
}

test "filesize" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    try testFmt("file size: 63MiB\n", "file size: {Bi}\n", usize(63 * 1024 * 1024));
    try testFmt("file size: 66.06MB\n", "file size: {B:.2}\n", usize(63 * 1024 * 1024));
}

test "struct" {
    {
        const Struct = struct {
            field: u8,
        };
        const value = Struct{ .field = 42 };
        try testFmt("struct: Struct{ .field = 42 }\n", "struct: {}\n", value);
        try testFmt("struct: Struct{ .field = 42 }\n", "struct: {}\n", &value);
    }
    {
        const Struct = struct {
            a: u0,
            b: u1,
        };
        const value = Struct{ .a = 0, .b = 1 };
        try testFmt("struct: Struct{ .a = 0, .b = 1 }\n", "struct: {}\n", value);
    }
}

test "enum" {
    const Enum = enum {
        One,
        Two,
    };
    const value = Enum.Two;
    try testFmt("enum: Enum.Two\n", "enum: {}\n", value);
    try testFmt("enum: Enum.Two\n", "enum: {}\n", &value);
}

test "float.scientific" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    try testFmt("f32: 1.34000003e+00", "f32: {e}", f32(1.34));
    try testFmt("f32: 1.23400001e+01", "f32: {e}", f32(12.34));
    try testFmt("f64: -1.234e+11", "f64: {e}", f64(-12.34e10));
    try testFmt("f64: 9.99996e-40", "f64: {e}", f64(9.999960e-40));
}

test "float.scientific.precision" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    try testFmt("f64: 1.40971e-42", "f64: {e:.5}", f64(1.409706e-42));
    try testFmt("f64: 1.00000e-09", "f64: {e:.5}", f64(@bitCast(f32, u32(814313563))));
    try testFmt("f64: 7.81250e-03", "f64: {e:.5}", f64(@bitCast(f32, u32(1006632960))));
    // libc rounds 1.000005e+05 to 1.00000e+05 but zig does 1.00001e+05.
    // In fact, libc doesn't round a lot of 5 cases up when one past the precision point.
    try testFmt("f64: 1.00001e+05", "f64: {e:.5}", f64(@bitCast(f32, u32(1203982400))));
}

test "float.special" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    try testFmt("f64: nan", "f64: {}", math.nan_f64);
    // negative nan is not defined by IEE 754,
    // and ARM thus normalizes it to positive nan
    if (builtin.arch != builtin.Arch.arm) {
        try testFmt("f64: -nan", "f64: {}", -math.nan_f64);
    }
    try testFmt("f64: inf", "f64: {}", math.inf_f64);
    try testFmt("f64: -inf", "f64: {}", -math.inf_f64);
}

test "float.decimal" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    try testFmt("f64: 152314000000000000000000000000", "f64: {d}", f64(1.52314e+29));
    try testFmt("f32: 1.1", "f32: {d:.1}", f32(1.1234));
    try testFmt("f32: 1234.57", "f32: {d:.2}", f32(1234.567));
    // -11.1234 is converted to f64 -11.12339... internally (errol3() function takes f64).
    // -11.12339... is rounded back up to -11.1234
    try testFmt("f32: -11.1234", "f32: {d:.4}", f32(-11.1234));
    try testFmt("f32: 91.12345", "f32: {d:.5}", f32(91.12345));
    try testFmt("f64: 91.1234567890", "f64: {d:.10}", f64(91.12345678901235));
    try testFmt("f64: 0.00000", "f64: {d:.5}", f64(0.0));
    try testFmt("f64: 6", "f64: {d:.0}", f64(5.700));
    try testFmt("f64: 10.0", "f64: {d:.1}", f64(9.999));
    try testFmt("f64: 1.000", "f64: {d:.3}", f64(1.0));
    try testFmt("f64: 0.00030000", "f64: {d:.8}", f64(0.0003));
    try testFmt("f64: 0.00000", "f64: {d:.5}", f64(1.40130e-45));
    try testFmt("f64: 0.00000", "f64: {d:.5}", f64(9.999960e-40));
}

test "float.libc.sanity" {
    if (builtin.os == .linux and builtin.arch == .arm and builtin.abi == .musleabihf) {
        // TODO https://github.com/ziglang/zig/issues/3289
        return error.SkipZigTest;
    }
    try testFmt("f64: 0.00001", "f64: {d:.5}", f64(@bitCast(f32, u32(916964781))));
    try testFmt("f64: 0.00001", "f64: {d:.5}", f64(@bitCast(f32, u32(925353389))));
    try testFmt("f64: 0.10000", "f64: {d:.5}", f64(@bitCast(f32, u32(1036831278))));
    try testFmt("f64: 1.00000", "f64: {d:.5}", f64(@bitCast(f32, u32(1065353133))));
    try testFmt("f64: 10.00000", "f64: {d:.5}", f64(@bitCast(f32, u32(1092616192))));

    // libc differences
    //
    // This is 0.015625 exactly according to gdb. We thus round down,
    // however glibc rounds up for some reason. This occurs for all
    // floats of the form x.yyyy25 on a precision point.
    try testFmt("f64: 0.01563", "f64: {d:.5}", f64(@bitCast(f32, u32(1015021568))));
    // errol3 rounds to ... 630 but libc rounds to ...632. Grisu3
    // also rounds to 630 so I'm inclined to believe libc is not
    // optimal here.
    try testFmt("f64: 18014400656965630.00000", "f64: {d:.5}", f64(@bitCast(f32, u32(1518338049))));
}

test "custom" {
    const Vec2 = struct {
        const SelfType = @This();
        x: f32,
        y: f32,

        pub fn format(
            self: SelfType,
            comptime fmt: []const u8,
            options: FormatOptions,
            context: var,
            comptime Errors: type,
            output: fn (@typeOf(context), []const u8) Errors!void,
        ) Errors!void {
            if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "p")) {
                return std.fmt.format(context, Errors, output, "({d:.3},{d:.3})", self.x, self.y);
            } else if (comptime std.mem.eql(u8, fmt, "d")) {
                return std.fmt.format(context, Errors, output, "{d:.3}x{d:.3}", self.x, self.y);
            } else {
                @compileError("Unknown format character: '" ++ fmt ++ "'");
            }
        }
    };

    var buf1: [32]u8 = undefined;
    var value = Vec2{
        .x = 10.2,
        .y = 2.22,
    };
    try testFmt("point: (10.200,2.220)\n", "point: {}\n", &value);
    try testFmt("dim: 10.200x2.220\n", "dim: {d}\n", &value);

    // same thing but not passing a pointer
    try testFmt("point: (10.200,2.220)\n", "point: {}\n", value);
    try testFmt("dim: 10.200x2.220\n", "dim: {d}\n", value);
}

test "struct" {
    const S = struct {
        a: u32,
        b: anyerror,
    };

    const inst = S{
        .a = 456,
        .b = error.Unused,
    };

    try testFmt("S{ .a = 456, .b = error.Unused }", "{}", inst);
}

test "union" {
    const TU = union(enum) {
        float: f32,
        int: u32,
    };

    const UU = union {
        float: f32,
        int: u32,
    };

    const EU = extern union {
        float: f32,
        int: u32,
    };

    const tu_inst = TU{ .int = 123 };
    const uu_inst = UU{ .int = 456 };
    const eu_inst = EU{ .float = 321.123 };

    try testFmt("TU{ .int = 123 }", "{}", tu_inst);

    var buf: [100]u8 = undefined;
    const uu_result = try bufPrint(buf[0..], "{}", uu_inst);
    testing.expect(mem.eql(u8, uu_result[0..3], "UU@"));

    const eu_result = try bufPrint(buf[0..], "{}", eu_inst);
    testing.expect(mem.eql(u8, uu_result[0..3], "EU@"));
}

test "enum" {
    const E = enum {
        One,
        Two,
        Three,
    };

    const inst = E.Two;

    try testFmt("E.Two", "{}", inst);
}

test "struct.self-referential" {
    const S = struct {
        const SelfType = @This();
        a: ?*SelfType,
    };

    var inst = S{
        .a = null,
    };
    inst.a = &inst;

    try testFmt("S{ .a = S{ .a = S{ .a = S{ ... } } } }", "{}", inst);
}

test "struct.zero-size" {
    const A = struct {
        fn foo() void {}
    };
    const B = struct {
        a: A,
        c: i32,
    };

    const a = A{};
    const b = B{ .a = a, .c = 0 };

    try testFmt("B{ .a = A{ }, .c = 0 }", "{}", b);
}

test "bytes.hex" {
    const some_bytes = "\xCA\xFE\xBA\xBE";
    try testFmt("lowercase: cafebabe\n", "lowercase: {x}\n", some_bytes);
    try testFmt("uppercase: CAFEBABE\n", "uppercase: {X}\n", some_bytes);
    //Test Slices
    try testFmt("uppercase: CAFE\n", "uppercase: {X}\n", some_bytes[0..2]);
    try testFmt("lowercase: babe\n", "lowercase: {x}\n", some_bytes[2..]);
    const bytes_with_zeros = "\x00\x0E\xBA\xBE";
    try testFmt("lowercase: 000ebabe\n", "lowercase: {x}\n", bytes_with_zeros);
}

fn testFmt(expected: []const u8, comptime template: []const u8, args: ...) !void {
    var buf: [100]u8 = undefined;
    const result = try bufPrint(buf[0..], template, args);
    if (mem.eql(u8, result, expected)) return;

    std.debug.warn("\n====== expected this output: =========\n");
    std.debug.warn("{}", expected);
    std.debug.warn("\n======== instead found this: =========\n");
    std.debug.warn("{}", result);
    std.debug.warn("\n======================================\n");
    return error.TestFailed;
}

pub fn trim(buf: []const u8) []const u8 {
    var start: usize = 0;
    while (start < buf.len and isWhiteSpace(buf[start])) : (start += 1) {}

    var end: usize = buf.len;
    while (true) {
        if (end > start) {
            const new_end = end - 1;
            if (isWhiteSpace(buf[new_end])) {
                end = new_end;
                continue;
            }
        }
        break;
    }
    return buf[start..end];
}

test "trim" {
    testing.expect(mem.eql(u8, "abc", trim("\n  abc  \t")));
    testing.expect(mem.eql(u8, "", trim("   ")));
    testing.expect(mem.eql(u8, "", trim("")));
    testing.expect(mem.eql(u8, "abc", trim(" abc")));
    testing.expect(mem.eql(u8, "abc", trim("abc ")));
}

pub fn isWhiteSpace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r' => true,
        else => false,
    };
}

pub fn hexToBytes(out: []u8, input: []const u8) !void {
    if (out.len * 2 < input.len)
        return error.InvalidLength;

    var in_i: usize = 0;
    while (in_i != input.len) : (in_i += 2) {
        const hi = try charToDigit(input[in_i], 16);
        const lo = try charToDigit(input[in_i + 1], 16);
        out[in_i / 2] = (hi << 4) | lo;
    }
}

test "hexToBytes" {
    const test_hex_str = "909A312BB12ED1F819B3521AC4C1E896F2160507FFC1C8381E3B07BB16BD1706";
    var pb: [32]u8 = undefined;
    try hexToBytes(pb[0..], test_hex_str);
    try testFmt(test_hex_str, "{X}", pb);
}

test "formatIntValue with comptime_int" {
    const value: comptime_int = 123456789123456789;

    var buf = try std.Buffer.init(std.debug.global_allocator, "");
    try formatIntValue(value, "", FormatOptions{}, &buf, @typeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append);
    assert(mem.eql(u8, buf.toSlice(), "123456789123456789"));
}

test "formatType max_depth" {
    const Vec2 = struct {
        const SelfType = @This();
        x: f32,
        y: f32,

        pub fn format(
            self: SelfType,
            comptime fmt: []const u8,
            options: FormatOptions,
            context: var,
            comptime Errors: type,
            output: fn (@typeOf(context), []const u8) Errors!void,
        ) Errors!void {
            if (fmt.len == 0) {
                return std.fmt.format(context, Errors, output, "({d:.3},{d:.3})", self.x, self.y);
            } else {
                @compileError("Unknown format string: '" ++ fmt ++ "'");
            }
        }
    };
    const E = enum {
        One,
        Two,
        Three,
    };
    const TU = union(enum) {
        const SelfType = @This();
        float: f32,
        int: u32,
        ptr: ?*SelfType,
    };
    const S = struct {
        const SelfType = @This();
        a: ?*SelfType,
        tu: TU,
        e: E,
        vec: Vec2,
    };

    var inst = S{
        .a = null,
        .tu = TU{ .ptr = null },
        .e = E.Two,
        .vec = Vec2{ .x = 10.2, .y = 2.22 },
    };
    inst.a = &inst;
    inst.tu.ptr = &inst.tu;

    var buf0 = try std.Buffer.init(std.debug.global_allocator, "");
    try formatType(inst, "", FormatOptions{}, &buf0, @typeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append, 0);
    assert(mem.eql(u8, buf0.toSlice(), "S{ ... }"));

    var buf1 = try std.Buffer.init(std.debug.global_allocator, "");
    try formatType(inst, "", FormatOptions{}, &buf1, @typeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append, 1);
    assert(mem.eql(u8, buf1.toSlice(), "S{ .a = S{ ... }, .tu = TU{ ... }, .e = E.Two, .vec = (10.200,2.220) }"));

    var buf2 = try std.Buffer.init(std.debug.global_allocator, "");
    try formatType(inst, "", FormatOptions{}, &buf2, @typeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append, 2);
    assert(mem.eql(u8, buf2.toSlice(), "S{ .a = S{ .a = S{ ... }, .tu = TU{ ... }, .e = E.Two, .vec = (10.200,2.220) }, .tu = TU{ .ptr = TU{ ... } }, .e = E.Two, .vec = (10.200,2.220) }"));

    var buf3 = try std.Buffer.init(std.debug.global_allocator, "");
    try formatType(inst, "", FormatOptions{}, &buf3, @typeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append, 3);
    assert(mem.eql(u8, buf3.toSlice(), "S{ .a = S{ .a = S{ .a = S{ ... }, .tu = TU{ ... }, .e = E.Two, .vec = (10.200,2.220) }, .tu = TU{ .ptr = TU{ ... } }, .e = E.Two, .vec = (10.200,2.220) }, .tu = TU{ .ptr = TU{ .ptr = TU{ ... } } }, .e = E.Two, .vec = (10.200,2.220) }"));
}

test "positional" {
    try testFmt("2 1 0", "{2} {1} {0}", usize(0), usize(1), usize(2));
    try testFmt("2 1 0", "{2} {1} {}", usize(0), usize(1), usize(2));
    try testFmt("0 0", "{0} {0}", usize(0));
    try testFmt("0 1", "{} {1}", usize(0), usize(1));
    try testFmt("1 0 0 1", "{1} {} {0} {}", usize(0), usize(1));
}

test "positional with specifier" {
    try testFmt("10.0", "{0d:.1}", f64(9.999));
}

test "positional/alignment/width/precision" {
    try testFmt("10.0", "{0d: >3.1}", f64(9.999));
}

const builtin = @import("builtin");
const TypeId = builtin.TypeId;
const std = @import("std.zig");

/// This function is intended to be used only in tests. It prints diagnostics to stderr
/// and then aborts when actual_error_union is not expected_error.
pub fn expectError(expected_error: anyerror, actual_error_union: var) void {
    if (actual_error_union) |actual_payload| {
        // TODO remove workaround here for https://github.com/ziglang/zig/issues/557
        if (@sizeOf(@typeOf(actual_payload)) == 0) {
            std.debug.panic("expected error.{}, found {} value", @errorName(expected_error), @typeName(@typeOf(actual_payload)));
        } else {
            std.debug.panic("expected error.{}, found {}", @errorName(expected_error), actual_payload);
        }
    } else |actual_error| {
        if (expected_error != actual_error) {
            std.debug.panic("expected error.{}, found error.{}", @errorName(expected_error), @errorName(actual_error));
        }
    }
}

/// This function is intended to be used only in tests. When the two values are not
/// equal, prints diagnostics to stderr to show exactly how they are not equal,
/// then aborts.
/// The types must match exactly.
pub fn expectEqual(expected: var, actual: @typeOf(expected)) void {
    switch (@typeInfo(@typeOf(actual))) {
        .NoReturn,
        .BoundFn,
        .ArgTuple,
        .Opaque,
        .Frame,
        .AnyFrame,
        => @compileError("value of type " ++ @typeName(@typeOf(actual)) ++ " encountered"),

        .Undefined,
        .Null,
        .Void,
        => return,

        .Type,
        .Bool,
        .Int,
        .Float,
        .ComptimeFloat,
        .ComptimeInt,
        .EnumLiteral,
        .Enum,
        .Fn,
        .Vector,
        .ErrorSet,
        => {
            if (actual != expected) {
                std.debug.panic("expected {}, found {}", expected, actual);
            }
        },

        .Pointer => |pointer| {
            switch (pointer.size) {
                builtin.TypeInfo.Pointer.Size.One,
                builtin.TypeInfo.Pointer.Size.Many,
                builtin.TypeInfo.Pointer.Size.C,
                => {
                    if (actual != expected) {
                        std.debug.panic("expected {}, found {}", expected, actual);
                    }
                },

                builtin.TypeInfo.Pointer.Size.Slice => {
                    if (actual.ptr != expected.ptr) {
                        std.debug.panic("expected slice ptr {}, found {}", expected.ptr, actual.ptr);
                    }
                    if (actual.len != expected.len) {
                        std.debug.panic("expected slice len {}, found {}", expected.len, actual.len);
                    }
                },
            }
        },

        .Array => |array| expectEqualSlices(array.child, &expected, &actual),

        .Struct => |structType| {
            inline for (structType.fields) |field| {
                expectEqual(@field(expected, field.name), @field(actual, field.name));
            }
        },

        .Union => |union_info| {
            if (union_info.tag_type == null) {
                @compileError("Unable to compare untagged union values");
            }
            @compileError("TODO implement testing.expectEqual for tagged unions");
        },

        .Optional => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    expectEqual(expected_payload, actual_payload);
                } else {
                    std.debug.panic("expected {}, found null", expected_payload);
                }
            } else {
                if (actual) |actual_payload| {
                    std.debug.panic("expected null, found {}", actual_payload);
                }
            }
        },

        .ErrorUnion => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    expectEqual(expected_payload, actual_payload);
                } else |actual_err| {
                    std.debug.panic("expected {}, found {}", expected_payload, actual_err);
                }
            } else |expected_err| {
                if (actual) |actual_payload| {
                    std.debug.panic("expected {}, found {}", expected_err, actual_payload);
                } else |actual_err| {
                    expectEqual(expected_err, actual_err);
                }
            }
        },
    }
}

/// This function is intended to be used only in tests. When the two slices are not
/// equal, prints diagnostics to stderr to show exactly how they are not equal,
/// then aborts.
pub fn expectEqualSlices(comptime T: type, expected: []const T, actual: []const T) void {
    // TODO better printing of the difference
    // If the arrays are small enough we could print the whole thing
    // If the child type is u8 and no weird bytes, we could print it as strings
    // Even for the length difference, it would be useful to see the values of the slices probably.
    if (expected.len != actual.len) {
        std.debug.panic("slice lengths differ. expected {}, found {}", expected.len, actual.len);
    }
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        if (expected[i] != actual[i]) {
            std.debug.panic("index {} incorrect. expected {}, found {}", i, expected[i], actual[i]);
        }
    }
}

/// This function is intended to be used only in tests. When `ok` is false, the test fails.
/// A message is printed to stderr and then abort is called.
pub fn expect(ok: bool) void {
    if (!ok) @panic("test failure");
}

const std = @import("std.zig");
const builtin = @import("builtin");
const debug = std.debug;
const mem = std.mem;
const math = std.math;
const testing = std.testing;

pub const trait = @import("meta/trait.zig");

const TypeInfo = builtin.TypeInfo;

pub fn tagName(v: var) []const u8 {
    const T = @TypeOf(v);
    switch (@typeInfo(T)) {
        .ErrorSet => return @errorName(v),
        else => return @tagName(v),
    }
}

test "std.meta.tagName" {
    const E1 = enum {
        A,
        B,
    };
    const E2 = enum(u8) {
        C = 33,
        D,
    };
    const U1 = union(enum) {
        G: u8,
        H: u16,
    };
    const U2 = union(E2) {
        C: u8,
        D: u16,
    };

    var u1g = U1{ .G = 0 };
    var u1h = U1{ .H = 0 };
    var u2a = U2{ .C = 0 };
    var u2b = U2{ .D = 0 };

    testing.expect(mem.eql(u8, tagName(E1.A), "A"));
    testing.expect(mem.eql(u8, tagName(E1.B), "B"));
    testing.expect(mem.eql(u8, tagName(E2.C), "C"));
    testing.expect(mem.eql(u8, tagName(E2.D), "D"));
    testing.expect(mem.eql(u8, tagName(error.E), "E"));
    testing.expect(mem.eql(u8, tagName(error.F), "F"));
    testing.expect(mem.eql(u8, tagName(u1g), "G"));
    testing.expect(mem.eql(u8, tagName(u1h), "H"));
    testing.expect(mem.eql(u8, tagName(u2a), "C"));
    testing.expect(mem.eql(u8, tagName(u2b), "D"));
}

pub fn stringToEnum(comptime T: type, str: []const u8) ?T {
    inline for (@typeInfo(T).Enum.fields) |enumField| {
        if (mem.eql(u8, str, enumField.name)) {
            return @field(T, enumField.name);
        }
    }
    return null;
}

test "std.meta.stringToEnum" {
    const E1 = enum {
        A,
        B,
    };
    testing.expect(E1.A == stringToEnum(E1, "A").?);
    testing.expect(E1.B == stringToEnum(E1, "B").?);
    testing.expect(null == stringToEnum(E1, "C"));
}

pub fn bitCount(comptime T: type) comptime_int {
    return switch (@typeInfo(T)) {
        .Bool => 1,
        .Int => |info| info.bits,
        .Float => |info| info.bits,
        else => @compileError("Expected bool, int or float type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.bitCount" {
    testing.expect(bitCount(u8) == 8);
    testing.expect(bitCount(f32) == 32);
}

pub fn alignment(comptime T: type) comptime_int {
    //@alignOf works on non-pointer types
    const P = if (comptime trait.is(.Pointer)(T)) T else *T;
    return @typeInfo(P).Pointer.alignment;
}

test "std.meta.alignment" {
    testing.expect(alignment(u8) == 1);
    testing.expect(alignment(*align(1) u8) == 1);
    testing.expect(alignment(*align(2) u8) == 2);
    testing.expect(alignment([]align(1) u8) == 1);
    testing.expect(alignment([]align(2) u8) == 2);
}

pub fn Child(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Array => |info| info.child,
        .Pointer => |info| info.child,
        .Optional => |info| info.child,
        else => @compileError("Expected pointer, optional, or array type, " ++ "found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.Child" {
    testing.expect(Child([1]u8) == u8);
    testing.expect(Child(*u8) == u8);
    testing.expect(Child([]u8) == u8);
    testing.expect(Child(?u8) == u8);
}

/// Given a type with a sentinel e.g. `[:0]u8`, returns the sentinel
pub fn Sentinel(comptime T: type) Child(T) {
    // comptime asserts that ptr has a sentinel
    switch (@typeInfo(T)) {
        .Array => |arrayInfo| {
            return comptime arrayInfo.sentinel.?;
        },
        .Pointer => |ptrInfo| {
            switch (ptrInfo.size) {
                .Many, .Slice => {
                    return comptime ptrInfo.sentinel.?;
                },
                else => {},
            }
        },
        else => {},
    }
    @compileError("not a sentinel type, found '" ++ @typeName(T) ++ "'");
}

test "std.meta.Sentinel" {
    testing.expectEqual(@as(u8, 0), Sentinel([:0]u8));
    testing.expectEqual(@as(u8, 0), Sentinel([*:0]u8));
    testing.expectEqual(@as(u8, 0), Sentinel([5:0]u8));
}

pub fn containerLayout(comptime T: type) TypeInfo.ContainerLayout {
    return switch (@typeInfo(T)) {
        .Struct => |info| info.layout,
        .Enum => |info| info.layout,
        .Union => |info| info.layout,
        else => @compileError("Expected struct, enum or union type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.containerLayout" {
    const E1 = enum {
        A,
    };
    const E2 = packed enum {
        A,
    };
    const E3 = extern enum {
        A,
    };
    const S1 = struct {};
    const S2 = packed struct {};
    const S3 = extern struct {};
    const U1 = union {
        a: u8,
    };
    const U2 = packed union {
        a: u8,
    };
    const U3 = extern union {
        a: u8,
    };

    testing.expect(containerLayout(E1) == .Auto);
    testing.expect(containerLayout(E2) == .Packed);
    testing.expect(containerLayout(E3) == .Extern);
    testing.expect(containerLayout(S1) == .Auto);
    testing.expect(containerLayout(S2) == .Packed);
    testing.expect(containerLayout(S3) == .Extern);
    testing.expect(containerLayout(U1) == .Auto);
    testing.expect(containerLayout(U2) == .Packed);
    testing.expect(containerLayout(U3) == .Extern);
}

pub fn declarations(comptime T: type) []TypeInfo.Declaration {
    return switch (@typeInfo(T)) {
        .Struct => |info| info.decls,
        .Enum => |info| info.decls,
        .Union => |info| info.decls,
        else => @compileError("Expected struct, enum or union type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.declarations" {
    const E1 = enum {
        A,

        fn a() void {}
    };
    const S1 = struct {
        fn a() void {}
    };
    const U1 = union {
        a: u8,

        fn a() void {}
    };

    const decls = comptime [_][]TypeInfo.Declaration{
        declarations(E1),
        declarations(S1),
        declarations(U1),
    };

    inline for (decls) |decl| {
        testing.expect(decl.len == 1);
        testing.expect(comptime mem.eql(u8, decl[0].name, "a"));
    }
}

pub fn declarationInfo(comptime T: type, comptime decl_name: []const u8) TypeInfo.Declaration {
    inline for (comptime declarations(T)) |decl| {
        if (comptime mem.eql(u8, decl.name, decl_name))
            return decl;
    }

    @compileError("'" ++ @typeName(T) ++ "' has no declaration '" ++ decl_name ++ "'");
}

test "std.meta.declarationInfo" {
    const E1 = enum {
        A,

        fn a() void {}
    };
    const S1 = struct {
        fn a() void {}
    };
    const U1 = union {
        a: u8,

        fn a() void {}
    };

    const infos = comptime [_]TypeInfo.Declaration{
        declarationInfo(E1, "a"),
        declarationInfo(S1, "a"),
        declarationInfo(U1, "a"),
    };

    inline for (infos) |info| {
        testing.expect(comptime mem.eql(u8, info.name, "a"));
        testing.expect(!info.is_pub);
    }
}

pub fn fields(comptime T: type) switch (@typeInfo(T)) {
    .Struct => []TypeInfo.StructField,
    .Union => []TypeInfo.UnionField,
    .ErrorSet => []TypeInfo.Error,
    .Enum => []TypeInfo.EnumField,
    else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
} {
    return switch (@typeInfo(T)) {
        .Struct => |info| info.fields,
        .Union => |info| info.fields,
        .Enum => |info| info.fields,
        .ErrorSet => |errors| errors.?, // must be non global error set
        else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.fields" {
    const E1 = enum {
        A,
    };
    const E2 = error{A};
    const S1 = struct {
        a: u8,
    };
    const U1 = union {
        a: u8,
    };

    const e1f = comptime fields(E1);
    const e2f = comptime fields(E2);
    const sf = comptime fields(S1);
    const uf = comptime fields(U1);

    testing.expect(e1f.len == 1);
    testing.expect(e2f.len == 1);
    testing.expect(sf.len == 1);
    testing.expect(uf.len == 1);
    testing.expect(mem.eql(u8, e1f[0].name, "A"));
    testing.expect(mem.eql(u8, e2f[0].name, "A"));
    testing.expect(mem.eql(u8, sf[0].name, "a"));
    testing.expect(mem.eql(u8, uf[0].name, "a"));
    testing.expect(comptime sf[0].field_type == u8);
    testing.expect(comptime uf[0].field_type == u8);
}

pub fn fieldInfo(comptime T: type, comptime field_name: []const u8) switch (@typeInfo(T)) {
    .Struct => TypeInfo.StructField,
    .Union => TypeInfo.UnionField,
    .ErrorSet => TypeInfo.Error,
    .Enum => TypeInfo.EnumField,
    else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
} {
    inline for (comptime fields(T)) |field| {
        if (comptime mem.eql(u8, field.name, field_name))
            return field;
    }

    @compileError("'" ++ @typeName(T) ++ "' has no field '" ++ field_name ++ "'");
}

test "std.meta.fieldInfo" {
    const E1 = enum {
        A,
    };
    const E2 = error{A};
    const S1 = struct {
        a: u8,
    };
    const U1 = union {
        a: u8,
    };

    const e1f = comptime fieldInfo(E1, "A");
    const e2f = comptime fieldInfo(E2, "A");
    const sf = comptime fieldInfo(S1, "a");
    const uf = comptime fieldInfo(U1, "a");

    testing.expect(mem.eql(u8, e1f.name, "A"));
    testing.expect(mem.eql(u8, e2f.name, "A"));
    testing.expect(mem.eql(u8, sf.name, "a"));
    testing.expect(mem.eql(u8, uf.name, "a"));
    testing.expect(comptime sf.field_type == u8);
    testing.expect(comptime uf.field_type == u8);
}

pub fn TagType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Enum => |info| info.tag_type,
        .Union => |info| if (info.tag_type) |Tag| Tag else null,
        else => @compileError("expected enum or union type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.TagType" {
    const E = enum(u8) {
        C = 33,
        D,
    };
    const U = union(E) {
        C: u8,
        D: u16,
    };

    testing.expect(TagType(E) == u8);
    testing.expect(TagType(U) == E);
}

///Returns the active tag of a tagged union
pub fn activeTag(u: var) @TagType(@TypeOf(u)) {
    const T = @TypeOf(u);
    return @as(@TagType(T), u);
}

test "std.meta.activeTag" {
    const UE = enum {
        Int,
        Float,
    };

    const U = union(UE) {
        Int: u32,
        Float: f32,
    };

    var u = U{ .Int = 32 };
    testing.expect(activeTag(u) == UE.Int);

    u = U{ .Float = 112.9876 };
    testing.expect(activeTag(u) == UE.Float);
}

///Given a tagged union type, and an enum, return the type of the union
/// field corresponding to the enum tag.
pub fn TagPayloadType(comptime U: type, tag: @TagType(U)) type {
    testing.expect(trait.is(.Union)(U));

    const info = @typeInfo(U).Union;

    inline for (info.fields) |field_info| {
        if (field_info.enum_field.?.value == @enumToInt(tag)) return field_info.field_type;
    }
    unreachable;
}

test "std.meta.TagPayloadType" {
    const Event = union(enum) {
        Moved: struct {
            from: i32,
            to: i32,
        },
    };
    const MovedEvent = TagPayloadType(Event, Event.Moved);
    var e: Event = undefined;
    testing.expect(MovedEvent == @TypeOf(e.Moved));
}

/// Compares two of any type for equality. Containers are compared on a field-by-field basis,
/// where possible. Pointers are not followed.
pub fn eql(a: var, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    switch (@typeInfo(T)) {
        .Struct => |info| {
            inline for (info.fields) |field_info| {
                if (!eql(@field(a, field_info.name), @field(b, field_info.name))) return false;
            }
            return true;
        },
        .ErrorUnion => {
            if (a) |a_p| {
                if (b) |b_p| return eql(a_p, b_p) else |_| return false;
            } else |a_e| {
                if (b) |_| return false else |b_e| return a_e == b_e;
            }
        },
        .Union => |info| {
            if (info.tag_type) |_| {
                const tag_a = activeTag(a);
                const tag_b = activeTag(b);
                if (tag_a != tag_b) return false;

                inline for (info.fields) |field_info| {
                    const enum_field = field_info.enum_field.?;
                    if (enum_field.value == @enumToInt(tag_a)) {
                        return eql(@field(a, enum_field.name), @field(b, enum_field.name));
                    }
                }
                return false;
            }

            @compileError("cannot compare untagged union type " ++ @typeName(T));
        },
        .Array => {
            if (a.len != b.len) return false;
            for (a) |e, i|
                if (!eql(e, b[i])) return false;
            return true;
        },
        .Vector => |info| {
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                if (!eql(a[i], b[i])) return false;
            }
            return true;
        },
        .Pointer => |info| {
            return switch (info.size) {
                .One, .Many, .C => a == b,
                .Slice => a.ptr == b.ptr and a.len == b.len,
            };
        },
        .Optional => {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return eql(a.?, b.?);
        },
        else => return a == b,
    }
}

test "std.meta.eql" {
    const S = struct {
        a: u32,
        b: f64,
        c: [5]u8,
    };

    const U = union(enum) {
        s: S,
        f: ?f32,
    };

    const s_1 = S{
        .a = 134,
        .b = 123.3,
        .c = "12345".*,
    };

    const s_2 = S{
        .a = 1,
        .b = 123.3,
        .c = "54321".*,
    };

    const s_3 = S{
        .a = 134,
        .b = 123.3,
        .c = "12345".*,
    };

    const u_1 = U{ .f = 24 };
    const u_2 = U{ .s = s_1 };
    const u_3 = U{ .f = 24 };

    testing.expect(eql(s_1, s_3));
    testing.expect(eql(&s_1, &s_1));
    testing.expect(!eql(&s_1, &s_3));
    testing.expect(eql(u_1, u_3));
    testing.expect(!eql(u_1, u_2));

    var a1 = "abcdef".*;
    var a2 = "abcdef".*;
    var a3 = "ghijkl".*;

    testing.expect(eql(a1, a2));
    testing.expect(!eql(a1, a3));
    testing.expect(!eql(a1[0..], a2[0..]));

    const EU = struct {
        fn tst(err: bool) !u8 {
            if (err) return error.Error;
            return @as(u8, 5);
        }
    };

    testing.expect(eql(EU.tst(true), EU.tst(true)));
    testing.expect(eql(EU.tst(false), EU.tst(false)));
    testing.expect(!eql(EU.tst(false), EU.tst(true)));

    var v1 = @splat(4, @as(u32, 1));
    var v2 = @splat(4, @as(u32, 1));
    var v3 = @splat(4, @as(u32, 2));

    testing.expect(eql(v1, v2));
    testing.expect(!eql(v1, v3));
}

test "intToEnum with error return" {
    const E1 = enum {
        A,
    };
    const E2 = enum {
        A,
        B,
    };

    var zero: u8 = 0;
    var one: u16 = 1;
    testing.expect(intToEnum(E1, zero) catch unreachable == E1.A);
    testing.expect(intToEnum(E2, one) catch unreachable == E2.B);
    testing.expectError(error.InvalidEnumTag, intToEnum(E1, one));
}

pub const IntToEnumError = error{InvalidEnumTag};

pub fn intToEnum(comptime Tag: type, tag_int: var) IntToEnumError!Tag {
    inline for (@typeInfo(Tag).Enum.fields) |f| {
        const this_tag_value = @field(Tag, f.name);
        if (tag_int == @enumToInt(this_tag_value)) {
            return this_tag_value;
        }
    }
    return error.InvalidEnumTag;
}

/// Given a type and a name, return the field index according to source order.
/// Returns `null` if the field is not found.
pub fn fieldIndex(comptime T: type, comptime name: []const u8) ?comptime_int {
    inline for (fields(T)) |field, i| {
        if (mem.eql(u8, field.name, name))
            return i;
    }
    return null;
}

/// Given a type, reference all the declarations inside, so that the semantic analyzer sees them.
pub fn refAllDecls(comptime T: type) void {
    if (!builtin.is_test) return;
    inline for (declarations(T)) |decl| {
        _ = decl;
    }
}

/// Returns a slice of pointers to public declarations of a namespace.
pub fn declList(comptime Namespace: type, comptime Decl: type) []const *const Decl {
    const S = struct {
        fn declNameLessThan(lhs: *const Decl, rhs: *const Decl) bool {
            return mem.lessThan(u8, lhs.name, rhs.name);
        }
    };
    comptime {
        const decls = declarations(Namespace);
        var array: [decls.len]*const Decl = undefined;
        for (decls) |decl, i| {
            array[i] = &@field(Namespace, decl.name);
        }
        std.sort.sort(*const Decl, &array, S.declNameLessThan);
        return &array;
    }
}

pub fn IntType(comptime is_signed: bool, comptime bit_count: u16) type {
    return @Type(TypeInfo{
        .Int = .{
            .is_signed = is_signed,
            .bits = bit_count,
        },
    });
}

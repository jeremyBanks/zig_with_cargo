const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;

/// Describes how pointer types should be hashed.
pub const HashStrategy = enum {
    /// Do not follow pointers, only hash their value.
    Shallow,

    /// Follow pointers, hash the pointee content.
    /// Only dereferences one level, ie. it is changed into .Shallow when a
    /// pointer type is encountered.
    Deep,

    /// Follow pointers, hash the pointee content.
    /// Dereferences all pointers encountered.
    /// Assumes no cycle.
    DeepRecursive,
};

/// Helper function to hash a pointer and mutate the strategy if needed.
pub fn hashPointer(hasher: var, key: var, comptime strat: HashStrategy) void {
    const info = @typeInfo(@typeOf(key));

    switch (info.Pointer.size) {
        builtin.TypeInfo.Pointer.Size.One => switch (strat) {
            .Shallow => hash(hasher, @ptrToInt(key), .Shallow),
            .Deep => hash(hasher, key.*, .Shallow),
            .DeepRecursive => hash(hasher, key.*, .DeepRecursive),
        },

        builtin.TypeInfo.Pointer.Size.Slice => switch (strat) {
            .Shallow => {
                hashPointer(hasher, key.ptr, .Shallow);
                hash(hasher, key.len, .Shallow);
            },
            .Deep => hashArray(hasher, key, .Shallow),
            .DeepRecursive => hashArray(hasher, key, .DeepRecursive),
        },

        builtin.TypeInfo.Pointer.Size.Many,
        builtin.TypeInfo.Pointer.Size.C,
        => switch (strat) {
            .Shallow => hash(hasher, @ptrToInt(key), .Shallow),
            else => @compileError(
                \\ unknown-length pointers and C pointers cannot be hashed deeply.
                \\ Consider providing your own hash function.
            ),
        },
    }
}

/// Helper function to hash a set of contiguous objects, from an array or slice.
pub fn hashArray(hasher: var, key: var, comptime strat: HashStrategy) void {
    switch (strat) {
        .Shallow => {
            // TODO detect via a trait when Key has no padding bits to
            // hash it as an array of bytes.
            // Otherwise, hash every element.
            for (key) |element| {
                hash(hasher, element, .Shallow);
            }
        },
        else => {
            for (key) |element| {
                hash(hasher, element, strat);
            }
        },
    }
}

/// Provides generic hashing for any eligible type.
/// Strategy is provided to determine if pointers should be followed or not.
pub fn hash(hasher: var, key: var, comptime strat: HashStrategy) void {
    const Key = @typeOf(key);
    switch (@typeInfo(Key)) {
        .NoReturn,
        .Opaque,
        .Undefined,
        .ArgTuple,
        .Void,
        .Null,
        .BoundFn,
        .ComptimeFloat,
        .ComptimeInt,
        .Type,
        .EnumLiteral,
        .Frame,
        => @compileError("cannot hash this type"),

        // Help the optimizer see that hashing an int is easy by inlining!
        // TODO Check if the situation is better after #561 is resolved.
        .Int => @inlineCall(hasher.update, std.mem.asBytes(&key)),

        .Float => |info| hash(hasher, @bitCast(@IntType(false, info.bits), key), strat),

        .Bool => hash(hasher, @boolToInt(key), strat),
        .Enum => hash(hasher, @enumToInt(key), strat),
        .ErrorSet => hash(hasher, @errorToInt(key), strat),
        .AnyFrame, .Fn => hash(hasher, @ptrToInt(key), strat),

        .Pointer => @inlineCall(hashPointer, hasher, key, strat),

        .Optional => if (key) |k| hash(hasher, k, strat),

        .Array => hashArray(hasher, key, strat),

        .Vector => |info| {
            if (info.child.bit_count % 8 == 0) {
                // If there's no unused bits in the child type, we can just hash
                // this as an array of bytes.
                hasher.update(mem.asBytes(&key));
            } else {
                // Otherwise, hash every element.
                // TODO remove the copy to an array once field access is done.
                const array: [info.len]info.child = key;
                comptime var i = 0;
                inline while (i < info.len) : (i += 1) {
                    hash(hasher, array[i], strat);
                }
            }
        },

        .Struct => |info| {
            // TODO detect via a trait when Key has no padding bits to
            // hash it as an array of bytes.
            // Otherwise, hash every field.
            inline for (info.fields) |field| {
                // We reuse the hash of the previous field as the seed for the
                // next one so that they're dependant.
                hash(hasher, @field(key, field.name), strat);
            }
        },

        .Union => |info| blk: {
            if (info.tag_type) |tag_type| {
                const tag = meta.activeTag(key);
                const s = hash(hasher, tag, strat);
                inline for (info.fields) |field| {
                    const enum_field = field.enum_field.?;
                    if (enum_field.value == @enumToInt(tag)) {
                        hash(hasher, @field(key, enum_field.name), strat);
                        // TODO use a labelled break when it does not crash the compiler. cf #2908
                        // break :blk;
                        return;
                    }
                }
                unreachable;
            } else @compileError("cannot hash untagged union type: " ++ @typeName(Key) ++ ", provide your own hash function");
        },

        .ErrorUnion => blk: {
            const payload = key catch |err| {
                hash(hasher, err, strat);
                break :blk;
            };
            hash(hasher, payload, strat);
        },
    }
}

/// Provides generic hashing for any eligible type.
/// Only hashes `key` itself, pointers are not followed.
/// Slices are rejected to avoid ambiguity on the user's intention.
pub fn autoHash(hasher: var, key: var) void {
    const Key = @typeOf(key);
    if (comptime meta.trait.isSlice(Key)) {
        comptime assert(@hasDecl(std, "StringHashMap")); // detect when the following message needs updated
        const extra_help = if (Key == []const u8)
            " Consider std.StringHashMap for hashing the contents of []const u8."
        else
            "";

        @compileError("std.auto_hash.autoHash does not allow slices (here " ++ @typeName(Key) ++
            ") because the intent is unclear. Consider using std.auto_hash.hash or providing your own hash function instead." ++
            extra_help);
    }

    hash(hasher, key, .Shallow);
}

const testing = std.testing;
const Wyhash = std.hash.Wyhash;

fn testHash(key: var) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hash(&hasher, key, .Shallow);
    return hasher.final();
}

fn testHashShallow(key: var) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hash(&hasher, key, .Shallow);
    return hasher.final();
}

fn testHashDeep(key: var) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hash(&hasher, key, .Deep);
    return hasher.final();
}

fn testHashDeepRecursive(key: var) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hash(&hasher, key, .DeepRecursive);
    return hasher.final();
}

test "hash pointer" {
    const array = [_]u32{ 123, 123, 123 };
    const a = &array[0];
    const b = &array[1];
    const c = &array[2];
    const d = a;

    testing.expect(testHashShallow(a) == testHashShallow(d));
    testing.expect(testHashShallow(a) != testHashShallow(c));
    testing.expect(testHashShallow(a) != testHashShallow(b));

    testing.expect(testHashDeep(a) == testHashDeep(a));
    testing.expect(testHashDeep(a) == testHashDeep(c));
    testing.expect(testHashDeep(a) == testHashDeep(b));

    testing.expect(testHashDeepRecursive(a) == testHashDeepRecursive(a));
    testing.expect(testHashDeepRecursive(a) == testHashDeepRecursive(c));
    testing.expect(testHashDeepRecursive(a) == testHashDeepRecursive(b));
}

test "hash slice shallow" {
    // Allocate one array dynamically so that we're assured it is not merged
    // with the other by the optimization passes.
    const array1 = try std.heap.direct_allocator.create([6]u32);
    defer std.heap.direct_allocator.destroy(array1);
    array1.* = [_]u32{ 1, 2, 3, 4, 5, 6 };
    const array2 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    const a = array1[0..];
    const b = array2[0..];
    const c = array1[0..3];
    testing.expect(testHashShallow(a) == testHashShallow(a));
    testing.expect(testHashShallow(a) != testHashShallow(array1));
    testing.expect(testHashShallow(a) != testHashShallow(b));
    testing.expect(testHashShallow(a) != testHashShallow(c));
}

test "hash slice deep" {
    // Allocate one array dynamically so that we're assured it is not merged
    // with the other by the optimization passes.
    const array1 = try std.heap.direct_allocator.create([6]u32);
    defer std.heap.direct_allocator.destroy(array1);
    array1.* = [_]u32{ 1, 2, 3, 4, 5, 6 };
    const array2 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    const a = array1[0..];
    const b = array2[0..];
    const c = array1[0..3];
    testing.expect(testHashDeep(a) == testHashDeep(a));
    testing.expect(testHashDeep(a) == testHashDeep(array1));
    testing.expect(testHashDeep(a) == testHashDeep(b));
    testing.expect(testHashDeep(a) != testHashDeep(c));
}

test "hash struct deep" {
    const Foo = struct {
        a: u32,
        b: f64,
        c: *bool,

        const Self = @This();

        pub fn init(allocator: *mem.Allocator, a_: u32, b_: f64, c_: bool) !Self {
            const ptr = try allocator.create(bool);
            ptr.* = c_;
            return Self{ .a = a_, .b = b_, .c = ptr };
        }
    };

    const allocator = std.heap.direct_allocator;
    const foo = try Foo.init(allocator, 123, 1.0, true);
    const bar = try Foo.init(allocator, 123, 1.0, true);
    const baz = try Foo.init(allocator, 123, 1.0, false);
    defer allocator.destroy(foo.c);
    defer allocator.destroy(bar.c);
    defer allocator.destroy(baz.c);

    testing.expect(testHashDeep(foo) == testHashDeep(bar));
    testing.expect(testHashDeep(foo) != testHashDeep(baz));
    testing.expect(testHashDeep(bar) != testHashDeep(baz));

    var hasher = Wyhash.init(0);
    const h = testHashDeep(foo);
    autoHash(&hasher, foo.a);
    autoHash(&hasher, foo.b);
    autoHash(&hasher, foo.c.*);
    testing.expectEqual(h, hasher.final());

    const h2 = testHashDeepRecursive(&foo);
    testing.expect(h2 != testHashDeep(&foo));
    testing.expect(h2 == testHashDeep(foo));
}

test "testHash optional" {
    const a: ?u32 = 123;
    const b: ?u32 = null;
    testing.expectEqual(testHash(a), testHash(u32(123)));
    testing.expect(testHash(a) != testHash(b));
    testing.expectEqual(testHash(b), 0);
}

test "testHash array" {
    const a = [_]u32{ 1, 2, 3 };
    const h = testHash(a);
    var hasher = Wyhash.init(0);
    autoHash(&hasher, u32(1));
    autoHash(&hasher, u32(2));
    autoHash(&hasher, u32(3));
    testing.expectEqual(h, hasher.final());
}

test "testHash struct" {
    const Foo = struct {
        a: u32 = 1,
        b: u32 = 2,
        c: u32 = 3,
    };
    const f = Foo{};
    const h = testHash(f);
    var hasher = Wyhash.init(0);
    autoHash(&hasher, u32(1));
    autoHash(&hasher, u32(2));
    autoHash(&hasher, u32(3));
    testing.expectEqual(h, hasher.final());
}

test "testHash union" {
    const Foo = union(enum) {
        A: u32,
        B: f32,
        C: u32,
    };

    const a = Foo{ .A = 18 };
    var b = Foo{ .B = 12.34 };
    const c = Foo{ .C = 18 };
    testing.expect(testHash(a) == testHash(a));
    testing.expect(testHash(a) != testHash(b));
    testing.expect(testHash(a) != testHash(c));

    b = Foo{ .A = 18 };
    testing.expect(testHash(a) == testHash(b));
}

test "testHash vector" {
    // Disabled because of #3317
    if (@import("builtin").arch == .mipsel) return error.SkipZigTest;

    const a: @Vector(4, u32) = [_]u32{ 1, 2, 3, 4 };
    const b: @Vector(4, u32) = [_]u32{ 1, 2, 3, 5 };
    testing.expect(testHash(a) == testHash(a));
    testing.expect(testHash(a) != testHash(b));

    const c: @Vector(4, u31) = [_]u31{ 1, 2, 3, 4 };
    const d: @Vector(4, u31) = [_]u31{ 1, 2, 3, 5 };
    testing.expect(testHash(c) == testHash(c));
    testing.expect(testHash(c) != testHash(d));
}

test "testHash error union" {
    const Errors = error{Test};
    const Foo = struct {
        a: u32 = 1,
        b: u32 = 2,
        c: u32 = 3,
    };
    const f = Foo{};
    const g: Errors!Foo = Errors.Test;
    testing.expect(testHash(f) != testHash(g));
    testing.expect(testHash(f) == testHash(Foo{}));
    testing.expect(testHash(g) == testHash(Errors.Test));
}

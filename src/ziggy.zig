const std = @import("std");

const r = @cImport({
  @cInclude("/mnt/c/Users/_/ziggy/src/rust.h");
});

const Header = struct {
    magic: u32,
    name: []const u8,
};

export fn ziggy() void {
    r.foo();
    printInfoAboutStruct(Header);
}

fn printInfoAboutStruct(comptime T: type) void {
    const info = @typeInfo(T);
    inline for (info.Struct.fields) |field| {
        std.debug.warn(
            "{} has a field called {} with type {}\n",
            @typeName(T),
            field.name,
            @typeName(field.field_type),
        );
    }
}

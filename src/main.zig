const std = @import("std");

const jeb = @import("./jeb.zig");

fn print(x: i64) void {
    std.debug.warn("{}, ", .{x});
}

fn common_main(allocator: *std.mem.Allocator) !void {
    std.debug.warn("\nLet's make a binary tree!\n", .{});

    const tree = try jeb.BinaryTreeSet.create(allocator);
    defer tree.destroy();

    tree.for_each(print);

    std.debug.warn("\nLet's add some values!\n", .{});

    try tree.insert(61);
    try tree.insert(59);
    try tree.insert(935);
    try tree.insert(24621);
    try tree.insert(1581);

    tree.for_each(print);

    std.debug.warn("\nLet's add some more!\n", .{});

    try tree.insert(1);
    try tree.insert(2);
    try tree.insert(3);
    try tree.insert(4);
    try tree.insert(5);

    tree.for_each(print);

    std.debug.warn("\nLet's try adding duplicates!\n", .{});

    try tree.insert(1);
    try tree.insert(1);
    try tree.insert(1);
    try tree.insert(2);
    try tree.insert(5);
    try tree.insert(5);
    try tree.insert(5);

    tree.for_each(print);

    std.debug.warn("\nLet's remove some!\n", .{});

    tree.remove(949994949);

    std.debug.warn("\n\n", .{});
}

test "main" {
    try common_main(std.testing.allocator);
}

export fn rust_main() void {
    common_main(std.heap.c_allocator) catch |err| {
        std.debug.warn("{}", .{err});
        std.process.exit(1);
    };
}

pub fn main() !void {
    try common_main(std.heap.c_allocator);
}

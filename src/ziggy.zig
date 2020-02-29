const std = @import("std");

export fn ziggy() void {
    const stdout = &std.io.getStdOut().outStream().stream;
    stdout.print("Hello, {} from Zig!\n", .{"world"}) catch unreachable;
}

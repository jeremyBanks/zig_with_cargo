const std = @import("../std.zig");
const builtin = @import("builtin");
const Lock = std.event.Lock;
const Loop = std.event.Loop;
const testing = std.testing;

/// ReturnType must be `void` or `E!void`
pub fn Group(comptime ReturnType: type) type {
    return struct {
        frame_stack: Stack,
        alloc_stack: Stack,
        lock: Lock,

        const Self = @This();

        const Error = switch (@typeInfo(ReturnType)) {
            .ErrorUnion => |payload| payload.error_set,
            else => void,
        };
        const Stack = std.atomic.Stack(anyframe->ReturnType);

        pub fn init(loop: *Loop) Self {
            return Self{
                .frame_stack = Stack.init(),
                .alloc_stack = Stack.init(),
                .lock = Lock.init(loop),
            };
        }

        /// Add a frame to the group. Thread-safe.
        pub fn add(self: *Self, handle: anyframe->ReturnType) (error{OutOfMemory}!void) {
            const node = try self.lock.loop.allocator.create(Stack.Node);
            node.* = Stack.Node{
                .next = undefined,
                .data = handle,
            };
            self.alloc_stack.push(node);
        }

        /// Add a node to the group. Thread-safe. Cannot fail.
        /// `node.data` should be the frame handle to add to the group.
        /// The node's memory should be in the function frame of
        /// the handle that is in the node, or somewhere guaranteed to live
        /// at least as long.
        pub fn addNode(self: *Self, node: *Stack.Node) void {
            self.frame_stack.push(node);
        }

        /// Wait for all the calls and promises of the group to complete.
        /// Thread-safe.
        /// Safe to call any number of times.
        pub async fn wait(self: *Self) ReturnType {
            const held = self.lock.acquire();
            defer held.release();

            var result: ReturnType = {};

            while (self.frame_stack.pop()) |node| {
                if (Error == void) {
                    await node.data;
                } else {
                    (await node.data) catch |err| {
                        result = err;
                    };
                }
            }
            while (self.alloc_stack.pop()) |node| {
                const handle = node.data;
                self.lock.loop.allocator.destroy(node);
                if (Error == void) {
                    await handle;
                } else {
                    (await handle) catch |err| {
                        result = err;
                    };
                }
            }
            return result;
        }
    };
}

test "std.event.Group" {
    // https://github.com/ziglang/zig/issues/1908
    if (builtin.single_threaded) return error.SkipZigTest;

    const allocator = std.heap.direct_allocator;

    var loop: Loop = undefined;
    try loop.initMultiThreaded(allocator);
    defer loop.deinit();

    const handle = async testGroup(&loop);

    loop.run();
}

async fn testGroup(loop: *Loop) void {
    var count: usize = 0;
    var group = Group(void).init(loop);
    var sleep_a_little_frame = async sleepALittle(&count);
    group.add(&sleep_a_little_frame) catch @panic("memory");
    var increase_by_ten_frame = async increaseByTen(&count);
    group.add(&increase_by_ten_frame) catch @panic("memory");
    group.wait();
    testing.expect(count == 11);

    var another = Group(anyerror!void).init(loop);
    var something_else_frame = async somethingElse();
    another.add(&something_else_frame) catch @panic("memory");
    var something_that_fails_frame = async doSomethingThatFails();
    another.add(&something_that_fails_frame) catch @panic("memory");
    testing.expectError(error.ItBroke, another.wait());
}

async fn sleepALittle(count: *usize) void {
    std.time.sleep(1 * std.time.millisecond);
    _ = @atomicRmw(usize, count, .Add, 1, .SeqCst);
}

async fn increaseByTen(count: *usize) void {
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = @atomicRmw(usize, count, .Add, 1, .SeqCst);
    }
}

async fn doSomethingThatFails() anyerror!void {}
async fn somethingElse() anyerror!void {
    return error.ItBroke;
}

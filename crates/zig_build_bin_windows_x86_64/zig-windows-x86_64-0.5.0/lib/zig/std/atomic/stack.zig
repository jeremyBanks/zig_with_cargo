const assert = std.debug.assert;
const builtin = @import("builtin");
const AtomicOrder = builtin.AtomicOrder;
const expect = std.testing.expect;

/// Many reader, many writer, non-allocating, thread-safe
/// Uses a spinlock to protect push() and pop()
/// When building in single threaded mode, this is a simple linked list.
pub fn Stack(comptime T: type) type {
    return struct {
        root: ?*Node,
        lock: @typeOf(lock_init),

        const lock_init = if (builtin.single_threaded) {} else u8(0);

        pub const Self = @This();

        pub const Node = struct {
            next: ?*Node,
            data: T,
        };

        pub fn init() Self {
            return Self{
                .root = null,
                .lock = lock_init,
            };
        }

        /// push operation, but only if you are the first item in the stack. if you did not succeed in
        /// being the first item in the stack, returns the other item that was there.
        pub fn pushFirst(self: *Self, node: *Node) ?*Node {
            node.next = null;
            return @cmpxchgStrong(?*Node, &self.root, null, node, AtomicOrder.SeqCst, AtomicOrder.SeqCst);
        }

        pub fn push(self: *Self, node: *Node) void {
            if (builtin.single_threaded) {
                node.next = self.root;
                self.root = node;
            } else {
                while (@atomicRmw(u8, &self.lock, builtin.AtomicRmwOp.Xchg, 1, AtomicOrder.SeqCst) != 0) {}
                defer assert(@atomicRmw(u8, &self.lock, builtin.AtomicRmwOp.Xchg, 0, AtomicOrder.SeqCst) == 1);

                node.next = self.root;
                self.root = node;
            }
        }

        pub fn pop(self: *Self) ?*Node {
            if (builtin.single_threaded) {
                const root = self.root orelse return null;
                self.root = root.next;
                return root;
            } else {
                while (@atomicRmw(u8, &self.lock, builtin.AtomicRmwOp.Xchg, 1, AtomicOrder.SeqCst) != 0) {}
                defer assert(@atomicRmw(u8, &self.lock, builtin.AtomicRmwOp.Xchg, 0, AtomicOrder.SeqCst) == 1);

                const root = self.root orelse return null;
                self.root = root.next;
                return root;
            }
        }

        pub fn isEmpty(self: *Self) bool {
            return @atomicLoad(?*Node, &self.root, AtomicOrder.SeqCst) == null;
        }
    };
}

const std = @import("../std.zig");
const Context = struct {
    allocator: *std.mem.Allocator,
    stack: *Stack(i32),
    put_sum: isize,
    get_sum: isize,
    get_count: usize,
    puts_done: u8, // TODO make this a bool
};
// TODO add lazy evaluated build options and then put puts_per_thread behind
// some option such as: "AggressiveMultithreadedFuzzTest". In the AppVeyor
// CI we would use a less aggressive setting since at 1 core, while we still
// want this test to pass, we need a smaller value since there is so much thrashing
// we would also use a less aggressive setting when running in valgrind
const puts_per_thread = 500;
const put_thread_count = 3;

test "std.atomic.stack" {
    var plenty_of_memory = try std.heap.direct_allocator.alloc(u8, 300 * 1024);
    defer std.heap.direct_allocator.free(plenty_of_memory);

    var fixed_buffer_allocator = std.heap.ThreadSafeFixedBufferAllocator.init(plenty_of_memory);
    var a = &fixed_buffer_allocator.allocator;

    var stack = Stack(i32).init();
    var context = Context{
        .allocator = a,
        .stack = &stack,
        .put_sum = 0,
        .get_sum = 0,
        .puts_done = 0,
        .get_count = 0,
    };

    if (builtin.single_threaded) {
        {
            var i: usize = 0;
            while (i < put_thread_count) : (i += 1) {
                expect(startPuts(&context) == 0);
            }
        }
        context.puts_done = 1;
        {
            var i: usize = 0;
            while (i < put_thread_count) : (i += 1) {
                expect(startGets(&context) == 0);
            }
        }
    } else {
        var putters: [put_thread_count]*std.Thread = undefined;
        for (putters) |*t| {
            t.* = try std.Thread.spawn(&context, startPuts);
        }
        var getters: [put_thread_count]*std.Thread = undefined;
        for (getters) |*t| {
            t.* = try std.Thread.spawn(&context, startGets);
        }

        for (putters) |t|
            t.wait();
        _ = @atomicRmw(u8, &context.puts_done, builtin.AtomicRmwOp.Xchg, 1, AtomicOrder.SeqCst);
        for (getters) |t|
            t.wait();
    }

    if (context.put_sum != context.get_sum) {
        std.debug.panic("failure\nput_sum:{} != get_sum:{}", context.put_sum, context.get_sum);
    }

    if (context.get_count != puts_per_thread * put_thread_count) {
        std.debug.panic(
            "failure\nget_count:{} != puts_per_thread:{} * put_thread_count:{}",
            context.get_count,
            u32(puts_per_thread),
            u32(put_thread_count),
        );
    }
}

fn startPuts(ctx: *Context) u8 {
    var put_count: usize = puts_per_thread;
    var r = std.rand.DefaultPrng.init(0xdeadbeef);
    while (put_count != 0) : (put_count -= 1) {
        std.time.sleep(1); // let the os scheduler be our fuzz
        const x = @bitCast(i32, r.random.scalar(u32));
        const node = ctx.allocator.create(Stack(i32).Node) catch unreachable;
        node.* = Stack(i32).Node{
            .next = undefined,
            .data = x,
        };
        ctx.stack.push(node);
        _ = @atomicRmw(isize, &ctx.put_sum, builtin.AtomicRmwOp.Add, x, AtomicOrder.SeqCst);
    }
    return 0;
}

fn startGets(ctx: *Context) u8 {
    while (true) {
        const last = @atomicLoad(u8, &ctx.puts_done, builtin.AtomicOrder.SeqCst) == 1;

        while (ctx.stack.pop()) |node| {
            std.time.sleep(1); // let the os scheduler be our fuzz
            _ = @atomicRmw(isize, &ctx.get_sum, builtin.AtomicRmwOp.Add, node.data, builtin.AtomicOrder.SeqCst);
            _ = @atomicRmw(usize, &ctx.get_count, builtin.AtomicRmwOp.Add, 1, builtin.AtomicOrder.SeqCst);
        }

        if (last) return 0;
    }
}

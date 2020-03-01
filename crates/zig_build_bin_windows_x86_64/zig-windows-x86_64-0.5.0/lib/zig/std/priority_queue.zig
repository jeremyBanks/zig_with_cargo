const std = @import("std.zig");
const Allocator = std.mem.Allocator;
const debug = std.debug;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

pub fn PriorityQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        len: usize,
        allocator: *Allocator,
        compareFn: fn (a: T, b: T) bool,

        pub fn init(allocator: *Allocator, compareFn: fn (a: T, b: T) bool) Self {
            return Self{
                .items = [_]T{},
                .len = 0,
                .allocator = allocator,
                .compareFn = compareFn,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.items);
        }

        pub fn add(self: *Self, elem: T) !void {
            try ensureCapacity(self, self.len + 1);
            addUnchecked(self, elem);
        }

        fn addUnchecked(self: *Self, elem: T) void {
            self.items[self.len] = elem;
            var child_index = self.len;
            while (child_index > 0) {
                var parent_index = ((child_index - 1) >> 1);
                const child = self.items[child_index];
                const parent = self.items[parent_index];

                if (!self.compareFn(child, parent)) break;

                self.items[parent_index] = child;
                self.items[child_index] = parent;
                child_index = parent_index;
            }
            self.len += 1;
        }

        pub fn addSlice(self: *Self, items: []const T) !void {
            try self.ensureCapacity(self.len + items.len);
            for (items) |e| {
                self.addUnchecked(e);
            }
        }

        pub fn peek(self: *Self) ?T {
            return if (self.len > 0) self.items[0] else null;
        }

        pub fn removeOrNull(self: *Self) ?T {
            return if (self.len > 0) self.remove() else null;
        }

        pub fn remove(self: *Self) T {
            const first = self.items[0];
            const last = self.items[self.len - 1];
            self.items[0] = last;
            self.len -= 1;
            siftDown(self, 0);
            return first;
        }

        pub fn count(self: Self) usize {
            return self.len;
        }

        pub fn capacity(self: Self) usize {
            return self.items.len;
        }

        fn siftDown(self: *Self, start_index: usize) void {
            var index = start_index;
            const half = self.len >> 1;
            while (true) {
                var left_index = (index << 1) + 1;
                var right_index = left_index + 1;
                var left = if (left_index < self.len) self.items[left_index] else null;
                var right = if (right_index < self.len) self.items[right_index] else null;

                var smallest_index = index;
                var smallest = self.items[index];

                if (left) |e| {
                    if (self.compareFn(e, smallest)) {
                        smallest_index = left_index;
                        smallest = e;
                    }
                }

                if (right) |e| {
                    if (self.compareFn(e, smallest)) {
                        smallest_index = right_index;
                        smallest = e;
                    }
                }

                if (smallest_index == index) return;

                self.items[smallest_index] = self.items[index];
                self.items[index] = smallest;
                index = smallest_index;

                if (index >= half) return;
            }
        }

        /// PriorityQueue takes ownership of the passed in slice. The slice must have been
        /// allocated with `allocator`.
        /// Deinitialize with `deinit`.
        pub fn fromOwnedSlice(allocator: *Allocator, compareFn: fn (a: T, b: T) bool, items: []T) Self {
            var queue = Self{
                .items = items,
                .len = items.len,
                .allocator = allocator,
                .compareFn = compareFn,
            };
            const half = (queue.len >> 1) - 1;
            var i: usize = 0;
            while (i <= half) : (i += 1) {
                queue.siftDown(half - i);
            }
            return queue;
        }

        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            var better_capacity = self.capacity();
            if (better_capacity >= new_capacity) return;
            while (true) {
                better_capacity += better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }
            self.items = try self.allocator.realloc(self.items, better_capacity);
        }

        pub fn resize(self: *Self, new_len: usize) !void {
            try self.ensureCapacity(new_len);
            self.len = new_len;
        }

        pub fn shrink(self: *Self, new_len: usize) void {
            // TODO take advantage of the new realloc semantics
            assert(new_len <= self.len);
            self.len = new_len;
        }

        const Iterator = struct {
            queue: *PriorityQueue(T),
            count: usize,

            fn next(it: *Iterator) ?T {
                if (it.count > it.queue.len - 1) return null;
                const out = it.count;
                it.count += 1;
                return it.queue.items[out];
            }

            fn reset(it: *Iterator) void {
                it.count = 0;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return Iterator{
                .queue = self,
                .count = 0,
            };
        }

        fn dump(self: *Self) void {
            warn("{{ ");
            warn("items: ");
            for (self.items) |e, i| {
                if (i >= self.len) break;
                warn("{}, ", e);
            }
            warn("array: ");
            for (self.items) |e, i| {
                warn("{}, ", e);
            }
            warn("len: {} ", self.len);
            warn("capacity: {}", self.capacity());
            warn(" }}\n");
        }
    };
}

fn lessThan(a: u32, b: u32) bool {
    return a < b;
}

fn greaterThan(a: u32, b: u32) bool {
    return a > b;
}

const PQ = PriorityQueue(u32);

test "std.PriorityQueue: add and remove min heap" {
    var queue = PQ.init(debug.global_allocator, lessThan);
    defer queue.deinit();

    try queue.add(54);
    try queue.add(12);
    try queue.add(7);
    try queue.add(23);
    try queue.add(25);
    try queue.add(13);
    expectEqual(u32(7), queue.remove());
    expectEqual(u32(12), queue.remove());
    expectEqual(u32(13), queue.remove());
    expectEqual(u32(23), queue.remove());
    expectEqual(u32(25), queue.remove());
    expectEqual(u32(54), queue.remove());
}

test "std.PriorityQueue: add and remove same min heap" {
    var queue = PQ.init(debug.global_allocator, lessThan);
    defer queue.deinit();

    try queue.add(1);
    try queue.add(1);
    try queue.add(2);
    try queue.add(2);
    try queue.add(1);
    try queue.add(1);
    expectEqual(u32(1), queue.remove());
    expectEqual(u32(1), queue.remove());
    expectEqual(u32(1), queue.remove());
    expectEqual(u32(1), queue.remove());
    expectEqual(u32(2), queue.remove());
    expectEqual(u32(2), queue.remove());
}

test "std.PriorityQueue: removeOrNull on empty" {
    var queue = PQ.init(debug.global_allocator, lessThan);
    defer queue.deinit();

    expect(queue.removeOrNull() == null);
}

test "std.PriorityQueue: edge case 3 elements" {
    var queue = PQ.init(debug.global_allocator, lessThan);
    defer queue.deinit();

    try queue.add(9);
    try queue.add(3);
    try queue.add(2);
    expectEqual(u32(2), queue.remove());
    expectEqual(u32(3), queue.remove());
    expectEqual(u32(9), queue.remove());
}

test "std.PriorityQueue: peek" {
    var queue = PQ.init(debug.global_allocator, lessThan);
    defer queue.deinit();

    expect(queue.peek() == null);
    try queue.add(9);
    try queue.add(3);
    try queue.add(2);
    expectEqual(u32(2), queue.peek().?);
    expectEqual(u32(2), queue.peek().?);
}

test "std.PriorityQueue: sift up with odd indices" {
    var queue = PQ.init(debug.global_allocator, lessThan);
    defer queue.deinit();
    const items = [_]u32{ 15, 7, 21, 14, 13, 22, 12, 6, 7, 25, 5, 24, 11, 16, 15, 24, 2, 1 };
    for (items) |e| {
        try queue.add(e);
    }

    const sorted_items = [_]u32{ 1, 2, 5, 6, 7, 7, 11, 12, 13, 14, 15, 15, 16, 21, 22, 24, 24, 25 };
    for (sorted_items) |e| {
        expectEqual(e, queue.remove());
    }
}

test "std.PriorityQueue: addSlice" {
    var queue = PQ.init(debug.global_allocator, lessThan);
    defer queue.deinit();
    const items = [_]u32{ 15, 7, 21, 14, 13, 22, 12, 6, 7, 25, 5, 24, 11, 16, 15, 24, 2, 1 };
    try queue.addSlice(items[0..]);

    const sorted_items = [_]u32{ 1, 2, 5, 6, 7, 7, 11, 12, 13, 14, 15, 15, 16, 21, 22, 24, 24, 25 };
    for (sorted_items) |e| {
        expectEqual(e, queue.remove());
    }
}

test "std.PriorityQueue: fromOwnedSlice" {
    const items = [_]u32{ 15, 7, 21, 14, 13, 22, 12, 6, 7, 25, 5, 24, 11, 16, 15, 24, 2, 1 };
    const heap_items = try std.mem.dupe(debug.global_allocator, u32, items[0..]);
    var queue = PQ.fromOwnedSlice(debug.global_allocator, lessThan, heap_items[0..]);
    defer queue.deinit();

    const sorted_items = [_]u32{ 1, 2, 5, 6, 7, 7, 11, 12, 13, 14, 15, 15, 16, 21, 22, 24, 24, 25 };
    for (sorted_items) |e| {
        expectEqual(e, queue.remove());
    }
}

test "std.PriorityQueue: add and remove max heap" {
    var queue = PQ.init(debug.global_allocator, greaterThan);
    defer queue.deinit();

    try queue.add(54);
    try queue.add(12);
    try queue.add(7);
    try queue.add(23);
    try queue.add(25);
    try queue.add(13);
    expectEqual(u32(54), queue.remove());
    expectEqual(u32(25), queue.remove());
    expectEqual(u32(23), queue.remove());
    expectEqual(u32(13), queue.remove());
    expectEqual(u32(12), queue.remove());
    expectEqual(u32(7), queue.remove());
}

test "std.PriorityQueue: add and remove same max heap" {
    var queue = PQ.init(debug.global_allocator, greaterThan);
    defer queue.deinit();

    try queue.add(1);
    try queue.add(1);
    try queue.add(2);
    try queue.add(2);
    try queue.add(1);
    try queue.add(1);
    expectEqual(u32(2), queue.remove());
    expectEqual(u32(2), queue.remove());
    expectEqual(u32(1), queue.remove());
    expectEqual(u32(1), queue.remove());
    expectEqual(u32(1), queue.remove());
    expectEqual(u32(1), queue.remove());
}

test "std.PriorityQueue: iterator" {
    var queue = PQ.init(debug.global_allocator, lessThan);
    var map = std.AutoHashMap(u32, void).init(debug.global_allocator);
    defer {
        queue.deinit();
        map.deinit();
    }

    const items = [_]u32{ 54, 12, 7, 23, 25, 13 };
    for (items) |e| {
        _ = try queue.add(e);
        _ = try map.put(e, {});
    }

    var it = queue.iterator();
    while (it.next()) |e| {
        _ = map.remove(e);
    }

    expectEqual(usize(0), map.count());
}

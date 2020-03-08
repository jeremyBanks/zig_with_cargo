const std = @import("std");

const BinaryTreeSet = struct {
    allocator: *std.mem.Allocator,
    root: ?*BinaryTreeSetNode,

    fn create(allocator: *std.mem.Allocator) !*BinaryTreeSet {
        const tree = try allocator.create(BinaryTreeSet);
        tree.* = BinaryTreeSet{
            .allocator = allocator,
            .root = null,
        };
        return tree;
    }

    fn destroy(self: *BinaryTreeSet) void {
        self.clear();
        self.allocator.destroy(self);
    }

    fn clear(self: *BinaryTreeSet) void {
        if (self.root) |root| {
            self.destroy_node(root);
            self.root = null;
        }
    }

    fn destroy_node(self: *BinaryTreeSet, node: *BinaryTreeSetNode) void {
        if (node.lesserChild) |lesserChild| {
            self.destroy_node(lesserChild);
        }

        if (node.greaterChild) |greaterChild| {
            self.destroy_node(greaterChild);
        }

        self.allocator.destroy(self);
    }

    fn insert(self: *BinaryTreeSet, value: i64) !void {
        if (self.root) |root| {
            var parent = root;
            while (true) {
                if (value == parent.value) {
                    // already in set, no-op
                    return;
                } else if (value < parent.value) {
                    if (parent.lesserChild) |lesserChild| {
                        parent = lesserChild;
                    } else {
                        parent.lesserChild = try BinaryTreeSetNode.create(self.allocator, value);
                        return;
                    }
                } else {
                    if (parent.greaterChild) |greaterChild| {
                        parent = greaterChild;
                    } else {
                        parent.greaterChild = try BinaryTreeSetNode.create(self.allocator, value);
                        return;
                    }
                }
            }
        } else {
            self.root = try BinaryTreeSetNode.create(self.allocator, value);
        }
    }

    fn for_each(self: *BinaryTreeSet, f: fn (value: i64) void) void {
        if (self.root) |root| {
            root.for_each(f);
        }
    }
};

const BinaryTreeSetNode = struct {
    value: i64,
    lesserChild: ?*BinaryTreeSetNode,
    greaterChild: ?*BinaryTreeSetNode,

    fn create(allocator: *std.mem.Allocator, value: i64) !*BinaryTreeSetNode {
        const node = try allocator.create(BinaryTreeSetNode);
        node.* = BinaryTreeSetNode{
            .value = value,
            .lesserChild = null,
            .greaterChild = null,
        };
        return node;
    }

    fn for_each(self: *BinaryTreeSetNode, f: fn (value: i64) void) void {
        if (self.lesserChild) |lesserChild| {
            lesserChild.for_each(f);
        }

        f(self.value);

        if (self.greaterChild) |greaterChild| {
            greaterChild.for_each(f);
        }
    }
};

fn main() !void {
    std.debug.warn("Let's make a binary tree.\n", .{});

    const tree = try BinaryTreeSet.create(std.heap.c_allocator);
    defer tree.destroy();

    try tree.insert(12);
    try tree.insert(3);
    try tree.insert(61);
    try tree.insert(59);
    try tree.insert(2);
    try tree.insert(5);
    try tree.insert(5);

    std.debug.warn("We did it! {}\n", .{tree});

    tree.for_each(print);
}

test "something" {
    std.testing.expect(true);

    const tree = try BinaryTreeSet.create(std.testing.allocator);
    defer tree.destroy();

    try tree.insert(12);
    try tree.insert(3);
    try tree.insert(61);
    try tree.insert(59);
    try tree.insert(2);
    try tree.insert(5);
    try tree.insert(5);
    try tree.insert(5);

    tree.for_each(print);

    std.debug.warn("We did it! {}\n", .{tree});
}

fn print(x: i64) void {
    std.debug.warn("- {}\n", .{x});
}

export fn ziggy() void {
    main() catch |err| {
        std.debug.warn("{}", .{err});
        std.process.exit(1);
    };
}

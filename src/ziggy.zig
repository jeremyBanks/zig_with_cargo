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

    fn insert(self: *BinaryTreeSet, value: i64) !void {
        const node = try BinaryTreeSetNode.create(self.allocator, value);
        // errdefer self.allocator.free(&node);

        if (self.root) |root| {
            var parent = root;
            while (true) {
                if (value == parent.value) {
                    // already in set, no-op
                    // self.allocator.free(node);
                    return;
                } else if (value < parent.value) {
                    if (parent.lesserChild) |lesserChild| {
                        parent = lesserChild;
                    } else {
                        parent.lesserChild = node;
                        return;
                    }
                } else {
                    if (parent.greaterChild) |greaterChild| {
                        parent = greaterChild;
                    } else {
                        parent.greaterChild = node;
                        return;
                    }
                }
            }
        } else {
            self.root = node;
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
};

fn main() !void {
    std.debug.warn("Let's make a binary tree.\n");

    const tree = try BinaryTreeSet.create(std.heap.c_allocator);

    try tree.insert(12);
    try tree.insert(3);
    try tree.insert(61);
    try tree.insert(59);
    try tree.insert(2);
    try tree.insert(5);

    std.debug.warn("We did it!\n");
}

export fn ziggy() void {
    main() catch std.process.exit(1);
}

const std = @import("std");

pub const BinaryTreeSet = struct {
    allocator: *std.mem.Allocator,
    root: ?*BinaryTreeSetNode,

    pub fn create(allocator: *std.mem.Allocator) !*BinaryTreeSet {
        const tree = try allocator.create(BinaryTreeSet);
        tree.* = BinaryTreeSet{
            .allocator = allocator,
            .root = null,
        };
        return tree;
    }

    pub fn destroy(self: *BinaryTreeSet) void {
        self.clear();
        self.allocator.destroy(self);
    }

    pub fn clear(self: *BinaryTreeSet) void {
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

    pub fn insert(self: *BinaryTreeSet, value: i64) !void {
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

    pub fn remove(self: *BinaryTreeSet, value: i64) void {
        if (self.root) |root| {
            var parent = root;
            while (true) {
                if (value == parent.value) {
                    @panic("found value, now what do I do!?");
                } else if (value < parent.value) {
                    if (parent.lesserChild) |lesserChild| {
                        parent = lesserChild;
                    } else {
                        // not found
                        return;
                    }
                } else {
                    if (parent.greaterChild) |greaterChild| {
                        parent = greaterChild;
                    } else {
                        // not found
                        return;
                    }
                }
            }
        }
    }

    pub fn for_each(self: *BinaryTreeSet, f: fn (value: i64) void) void {
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

const std = @import("std.zig");
const StringHashMap = std.StringHashMap;
const mem = @import("mem.zig");
const Allocator = mem.Allocator;
const testing = std.testing;

pub const BufSet = struct {
    hash_map: BufSetHashMap,

    const BufSetHashMap = StringHashMap(void);

    pub fn init(a: *Allocator) BufSet {
        var self = BufSet{ .hash_map = BufSetHashMap.init(a) };
        return self;
    }

    pub fn deinit(self: *const BufSet) void {
        var it = self.hash_map.iterator();
        while (true) {
            const entry = it.next() orelse break;
            self.free(entry.key);
        }

        self.hash_map.deinit();
    }

    pub fn put(self: *BufSet, key: []const u8) !void {
        if (self.hash_map.get(key) == null) {
            const key_copy = try self.copy(key);
            errdefer self.free(key_copy);
            _ = try self.hash_map.put(key_copy, {});
        }
    }

    pub fn exists(self: BufSet, key: []const u8) bool {
        return self.hash_map.get(key) != null;
    }

    pub fn delete(self: *BufSet, key: []const u8) void {
        const entry = self.hash_map.remove(key) orelse return;
        self.free(entry.key);
    }

    pub fn count(self: *const BufSet) usize {
        return self.hash_map.count();
    }

    pub fn iterator(self: *const BufSet) BufSetHashMap.Iterator {
        return self.hash_map.iterator();
    }

    pub fn allocator(self: *const BufSet) *Allocator {
        return self.hash_map.allocator;
    }

    fn free(self: *const BufSet, value: []const u8) void {
        self.hash_map.allocator.free(value);
    }

    fn copy(self: *const BufSet, value: []const u8) ![]const u8 {
        const result = try self.hash_map.allocator.alloc(u8, value.len);
        mem.copy(u8, result, value);
        return result;
    }
};

test "BufSet" {
    var bufset = BufSet.init(std.heap.direct_allocator);
    defer bufset.deinit();

    try bufset.put("x");
    testing.expect(bufset.count() == 1);
    bufset.delete("x");
    testing.expect(bufset.count() == 0);

    try bufset.put("x");
    try bufset.put("y");
    try bufset.put("z");
}

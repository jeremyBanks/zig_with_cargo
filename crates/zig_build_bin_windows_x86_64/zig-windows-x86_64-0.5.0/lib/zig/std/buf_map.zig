const std = @import("std.zig");
const StringHashMap = std.StringHashMap;
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;

/// BufMap copies keys and values before they go into the map, and
/// frees them when they get removed.
pub const BufMap = struct {
    hash_map: BufMapHashMap,

    const BufMapHashMap = StringHashMap([]const u8);

    pub fn init(allocator: *Allocator) BufMap {
        var self = BufMap{ .hash_map = BufMapHashMap.init(allocator) };
        return self;
    }

    pub fn deinit(self: *BufMap) void {
        var it = self.hash_map.iterator();
        while (true) {
            const entry = it.next() orelse break;
            self.free(entry.key);
            self.free(entry.value);
        }

        self.hash_map.deinit();
    }

    /// Same as `set` but the key and value become owned by the BufMap rather
    /// than being copied.
    /// If `setMove` fails, the ownership of key and value does not transfer.
    pub fn setMove(self: *BufMap, key: []u8, value: []u8) !void {
        const get_or_put = try self.hash_map.getOrPut(key);
        if (get_or_put.found_existing) {
            self.free(get_or_put.kv.key);
            get_or_put.kv.key = key;
        }
        get_or_put.kv.value = value;
    }

    /// `key` and `value` are copied into the BufMap.
    pub fn set(self: *BufMap, key: []const u8, value: []const u8) !void {
        const value_copy = try self.copy(value);
        errdefer self.free(value_copy);
        // Avoid copying key if it already exists
        const get_or_put = try self.hash_map.getOrPut(key);
        if (!get_or_put.found_existing) {
            get_or_put.kv.key = self.copy(key) catch |err| {
                _ = self.hash_map.remove(key);
                return err;
            };
        }
        get_or_put.kv.value = value_copy;
    }

    pub fn get(self: BufMap, key: []const u8) ?[]const u8 {
        const entry = self.hash_map.get(key) orelse return null;
        return entry.value;
    }

    pub fn delete(self: *BufMap, key: []const u8) void {
        const entry = self.hash_map.remove(key) orelse return;
        self.free(entry.key);
        self.free(entry.value);
    }

    pub fn count(self: BufMap) usize {
        return self.hash_map.count();
    }

    pub fn iterator(self: *const BufMap) BufMapHashMap.Iterator {
        return self.hash_map.iterator();
    }

    fn free(self: BufMap, value: []const u8) void {
        self.hash_map.allocator.free(value);
    }

    fn copy(self: BufMap, value: []const u8) ![]u8 {
        return mem.dupe(self.hash_map.allocator, u8, value);
    }
};

test "BufMap" {
    var bufmap = BufMap.init(std.heap.direct_allocator);
    defer bufmap.deinit();

    try bufmap.set("x", "1");
    testing.expect(mem.eql(u8, bufmap.get("x").?, "1"));
    testing.expect(1 == bufmap.count());

    try bufmap.set("x", "2");
    testing.expect(mem.eql(u8, bufmap.get("x").?, "2"));
    testing.expect(1 == bufmap.count());

    try bufmap.set("x", "3");
    testing.expect(mem.eql(u8, bufmap.get("x").?, "3"));
    testing.expect(1 == bufmap.count());

    bufmap.delete("x");
    testing.expect(0 == bufmap.count());
}

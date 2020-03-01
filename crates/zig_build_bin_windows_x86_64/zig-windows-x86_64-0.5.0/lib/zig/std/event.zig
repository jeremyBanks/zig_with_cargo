pub const Channel = @import("event/channel.zig").Channel;
pub const Future = @import("event/future.zig").Future;
pub const Group = @import("event/group.zig").Group;
pub const Lock = @import("event/lock.zig").Lock;
pub const Locked = @import("event/locked.zig").Locked;
pub const RwLock = @import("event/rwlock.zig").RwLock;
pub const RwLocked = @import("event/rwlocked.zig").RwLocked;
pub const Loop = @import("event/loop.zig").Loop;
pub const fs = @import("event/fs.zig");
pub const net = @import("event/net.zig");

test "import event tests" {
    _ = @import("event/channel.zig");
    _ = @import("event/fs.zig");
    _ = @import("event/future.zig");
    _ = @import("event/group.zig");
    _ = @import("event/lock.zig");
    _ = @import("event/locked.zig");
    _ = @import("event/rwlock.zig");
    _ = @import("event/rwlocked.zig");
    _ = @import("event/loop.zig");
    _ = @import("event/net.zig");
}

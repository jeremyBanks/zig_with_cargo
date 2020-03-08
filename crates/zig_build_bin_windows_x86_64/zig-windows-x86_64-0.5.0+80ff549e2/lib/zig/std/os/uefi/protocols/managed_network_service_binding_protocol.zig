const uefi = @import("std").os.uefi;
const Handle = uefi.Handle;
const Guid = uefi.Guid;

pub const ManagedNetworkServiceBindingProtocol = extern struct {
    _create_child: extern fn (*const ManagedNetworkServiceBindingProtocol, *?Handle) usize,
    _destroy_child: extern fn (*const ManagedNetworkServiceBindingProtocol, Handle) usize,

    pub fn createChild(self: *const ManagedNetworkServiceBindingProtocol, handle: *?Handle) usize {
        return self._create_child(self, handle);
    }

    pub fn destroyChild(self: *const ManagedNetworkServiceBindingProtocol, handle: Handle) usize {
        return self._destroy_child(self, handle);
    }

    pub const guid align(8) = Guid{
        .time_low = 0xf36ff770,
        .time_mid = 0xa7e1,
        .time_high_and_version = 0x42cf,
        .clock_seq_high_and_reserved = 0x9e,
        .clock_seq_low = 0xd2,
        .node = [_]u8{ 0x56, 0xf0, 0xf2, 0x71, 0xf4, 0x4c },
    };
};

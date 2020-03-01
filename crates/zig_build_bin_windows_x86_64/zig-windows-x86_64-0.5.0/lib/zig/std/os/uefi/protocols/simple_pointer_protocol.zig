const uefi = @import("std").os.uefi;
const Event = uefi.Event;
const Guid = uefi.Guid;

/// UEFI Specification, Version 2.8, 12.5
pub const SimplePointerProtocol = struct {
    _reset: extern fn (*const SimplePointerProtocol, bool) usize,
    _get_state: extern fn (*const SimplePointerProtocol, *SimplePointerState) usize,
    wait_for_input: Event,
    mode: *SimplePointerMode,

    pub fn reset(self: *const SimplePointerProtocol, verify: bool) usize {
        return self._reset(self, verify);
    }

    pub fn getState(self: *const SimplePointerProtocol, state: *SimplePointerState) usize {
        return self._get_state(self, state);
    }

    pub const guid align(8) = Guid{
        .time_low = 0x31878c87,
        .time_mid = 0x0b75,
        .time_high_and_version = 0x11d5,
        .clock_seq_high_and_reserved = 0x9a,
        .clock_seq_low = 0x4f,
        .node = [_]u8{ 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d },
    };
};

pub const SimplePointerMode = struct {
    resolution_x: u64,
    resolution_y: u64,
    resolution_z: u64,
    left_button: bool,
    right_button: bool,
};

pub const SimplePointerState = struct {
    relative_movement_x: i32 = undefined,
    relative_movement_y: i32 = undefined,
    relative_movement_z: i32 = undefined,
    left_button: bool = undefined,
    right_button: bool = undefined,
};

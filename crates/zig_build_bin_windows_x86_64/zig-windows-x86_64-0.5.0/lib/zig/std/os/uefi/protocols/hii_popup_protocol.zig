const uefi = @import("std").os.uefi;
const Guid = uefi.Guid;
const hii = uefi.protocols.hii;

pub const HIIPopupProtocol = extern struct {
    revision: u64,
    _create_popup: extern fn (*const HIIPopupProtocol, HIIPopupStyle, HIIPopupType, hii.HIIHandle, u16, ?*HIIPopupSelection) usize,

    pub fn createPopup(self: *const HIIPopupProtocol, style: HIIPopupStyle, popup_type: HIIPopupType, handle: hii.HIIHandle, msg: u16, user_selection: ?*HIIPopupSelection) usize {
        return self._create_popup(self, style, popup_type, handle, msg, user_selection);
    }

    pub const guid align(8) = Guid{
        .time_low = 0x4311edc0,
        .time_mid = 0x6054,
        .time_high_and_version = 0x46d4,
        .clock_seq_high_and_reserved = 0x9e,
        .clock_seq_low = 0x40,
        .node = [_]u8{ 0x89, 0x3e, 0xa9, 0x52, 0xfc, 0xcc },
    };
};

pub const HIIPopupStyle = extern enum(u32) {
    Info,
    Warning,
    Error,
};

pub const HIIPopupType = extern enum(u32) {
    Ok,
    Cancel,
    YesNo,
    YesNoCancel,
};

pub const HIIPopupSelection = extern enum(u32) {
    Ok,
    Cancel,
    Yes,
    No,
};

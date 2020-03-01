const uefi = @import("std").os.uefi;
const Guid = uefi.Guid;

/// UEFI Specification, Version 2.8, 12.9
pub const GraphicsOutputProtocol = extern struct {
    _query_mode: extern fn (*const GraphicsOutputProtocol, u32, *usize, **GraphicsOutputModeInformation) usize,
    _set_mode: extern fn (*const GraphicsOutputProtocol, u32) usize,
    _blt: extern fn (*const GraphicsOutputProtocol, ?[*]GraphicsOutputBltPixel, GraphicsOutputBltOperation, usize, usize, usize, usize, usize, usize, usize) usize,
    mode: *GraphicsOutputProtocolMode,

    pub fn queryMode(self: *const GraphicsOutputProtocol, mode: u32, size_of_info: *usize, info: **GraphicsOutputModeInformation) usize {
        return self._query_mode(self, mode, size_of_info, info);
    }

    pub fn setMode(self: *const GraphicsOutputProtocol, mode: u32) usize {
        return self._set_mode(self, mode);
    }

    pub fn blt(self: *const GraphicsOutputProtocol, blt_buffer: ?[*]GraphicsOutputBltPixel, blt_operation: GraphicsOutputBltOperation, source_x: usize, source_y: usize, destination_x: usize, destination_y: usize, width: usize, height: usize, delta: usize) usize {
        return self._blt(self, blt_buffer, blt_operation, source_x, source_y, destination_x, destination_y, width, height, delta);
    }

    pub const guid align(8) = Guid{
        .time_low = 0x9042a9de,
        .time_mid = 0x23dc,
        .time_high_and_version = 0x4a38,
        .clock_seq_high_and_reserved = 0x96,
        .clock_seq_low = 0xfb,
        .node = [_]u8{ 0x7a, 0xde, 0xd0, 0x80, 0x51, 0x6a },
    };
};

pub const GraphicsOutputProtocolMode = extern struct {
    max_mode: u32,
    mode: u32,
    info: *GraphicsOutputModeInformation,
    size_of_info: usize,
    frame_buffer_base: u64,
    frame_buffer_size: usize,
};

pub const GraphicsOutputModeInformation = extern struct {
    version: u32 = undefined,
    horizontal_resolution: u32 = undefined,
    vertical_resolution: u32 = undefined,
    pixel_format: GraphicsPixelFormat = undefined,
    pixel_information: PixelBitmask = undefined,
    pixels_per_scan_line: u32 = undefined,
};

pub const GraphicsPixelFormat = extern enum(u32) {
    PixelRedGreenBlueReserved8BitPerColor,
    PixelBlueGreenRedReserved8BitPerColor,
    PixelBitMask,
    PixelBltOnly,
    PixelFormatMax,
};

pub const PixelBitmask = extern struct {
    red_mask: u32,
    green_mask: u32,
    blue_mask: u32,
    reserved_mask: u32,
};

pub const GraphicsOutputBltPixel = extern struct {
    blue: u8,
    green: u8,
    red: u8,
    reserved: u8 = undefined,
};

pub const GraphicsOutputBltOperation = extern enum(u32) {
    BltVideoFill,
    BltVideoToBltBuffer,
    BltBufferToVideo,
    BltVideoToVideo,
    GraphicsOutputBltOperationMax,
};

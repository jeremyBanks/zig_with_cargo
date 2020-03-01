const std = @import("../std.zig");
const builtin = @import("builtin");
const root = @import("root");
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;
const Buffer = std.Buffer;

pub const default_stack_size = 1 * 1024 * 1024;
pub const stack_size: usize = if (@hasDecl(root, "stack_size_std_io_InStream"))
    root.stack_size_std_io_InStream
else
    default_stack_size;
pub const stack_align = 16;

pub fn InStream(comptime ReadError: type) type {
    return struct {
        const Self = @This();
        pub const Error = ReadError;
        pub const ReadFn = if (std.io.is_async)
            async fn (self: *Self, buffer: []u8) Error!usize
        else
            fn (self: *Self, buffer: []u8) Error!usize;

        /// Returns the number of bytes read. It may be less than buffer.len.
        /// If the number of bytes read is 0, it means end of stream.
        /// End of stream is not an error condition.
        readFn: ReadFn,

        /// Returns the number of bytes read. It may be less than buffer.len.
        /// If the number of bytes read is 0, it means end of stream.
        /// End of stream is not an error condition.
        pub fn read(self: *Self, buffer: []u8) Error!usize {
            if (std.io.is_async) {
                // Let's not be writing 0xaa in safe modes for upwards of 4 MiB for every stream read.
                @setRuntimeSafety(false);
                var stack_frame: [stack_size]u8 align(stack_align) = undefined;
                return await @asyncCall(&stack_frame, {}, self.readFn, self, buffer);
            } else {
                return self.readFn(self, buffer);
            }
        }

        /// Returns the number of bytes read. If the number read is smaller than buf.len, it
        /// means the stream reached the end. Reaching the end of a stream is not an error
        /// condition.
        pub fn readFull(self: *Self, buffer: []u8) Error!usize {
            var index: usize = 0;
            while (index != buffer.len) {
                const amt = try self.read(buffer[index..]);
                if (amt == 0) return index;
                index += amt;
            }
            return index;
        }

        /// Returns the number of bytes read. If the number read would be smaller than buf.len,
        /// error.EndOfStream is returned instead.
        pub fn readNoEof(self: *Self, buf: []u8) !void {
            const amt_read = try self.readFull(buf);
            if (amt_read < buf.len) return error.EndOfStream;
        }

        /// Replaces `buffer` contents by reading from the stream until it is finished.
        /// If `buffer.len()` would exceed `max_size`, `error.StreamTooLong` is returned and
        /// the contents read from the stream are lost.
        pub fn readAllBuffer(self: *Self, buffer: *Buffer, max_size: usize) !void {
            try buffer.resize(0);

            var actual_buf_len: usize = 0;
            while (true) {
                const dest_slice = buffer.toSlice()[actual_buf_len..];
                const bytes_read = try self.readFull(dest_slice);
                actual_buf_len += bytes_read;

                if (bytes_read != dest_slice.len) {
                    buffer.shrink(actual_buf_len);
                    return;
                }

                const new_buf_size = math.min(max_size, actual_buf_len + mem.page_size);
                if (new_buf_size == actual_buf_len) return error.StreamTooLong;
                try buffer.resize(new_buf_size);
            }
        }

        /// Allocates enough memory to hold all the contents of the stream. If the allocated
        /// memory would be greater than `max_size`, returns `error.StreamTooLong`.
        /// Caller owns returned memory.
        /// If this function returns an error, the contents from the stream read so far are lost.
        pub fn readAllAlloc(self: *Self, allocator: *mem.Allocator, max_size: usize) ![]u8 {
            var buf = Buffer.initNull(allocator);
            defer buf.deinit();

            try self.readAllBuffer(&buf, max_size);
            return buf.toOwnedSlice();
        }

        /// Replaces `buffer` contents by reading from the stream until `delimiter` is found.
        /// Does not include the delimiter in the result.
        /// If `buffer.len()` would exceed `max_size`, `error.StreamTooLong` is returned and the contents
        /// read from the stream so far are lost.
        pub fn readUntilDelimiterBuffer(self: *Self, buffer: *Buffer, delimiter: u8, max_size: usize) !void {
            try buffer.resize(0);

            while (true) {
                var byte: u8 = try self.readByte();

                if (byte == delimiter) {
                    return;
                }

                if (buffer.len() == max_size) {
                    return error.StreamTooLong;
                }

                try buffer.appendByte(byte);
            }
        }

        /// Allocates enough memory to read until `delimiter`. If the allocated
        /// memory would be greater than `max_size`, returns `error.StreamTooLong`.
        /// Caller owns returned memory.
        /// If this function returns an error, the contents from the stream read so far are lost.
        pub fn readUntilDelimiterAlloc(self: *Self, allocator: *mem.Allocator, delimiter: u8, max_size: usize) ![]u8 {
            var buf = Buffer.initNull(allocator);
            defer buf.deinit();

            try self.readUntilDelimiterBuffer(&buf, delimiter, max_size);
            return buf.toOwnedSlice();
        }

        /// Reads 1 byte from the stream or returns `error.EndOfStream`.
        pub fn readByte(self: *Self) !u8 {
            var result: [1]u8 = undefined;
            try self.readNoEof(result[0..]);
            return result[0];
        }

        /// Same as `readByte` except the returned byte is signed.
        pub fn readByteSigned(self: *Self) !i8 {
            return @bitCast(i8, try self.readByte());
        }

        /// Reads a native-endian integer
        pub fn readIntNative(self: *Self, comptime T: type) !T {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            try self.readNoEof(bytes[0..]);
            return mem.readIntNative(T, &bytes);
        }

        /// Reads a foreign-endian integer
        pub fn readIntForeign(self: *Self, comptime T: type) !T {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            try self.readNoEof(bytes[0..]);
            return mem.readIntForeign(T, &bytes);
        }

        pub fn readIntLittle(self: *Self, comptime T: type) !T {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            try self.readNoEof(bytes[0..]);
            return mem.readIntLittle(T, &bytes);
        }

        pub fn readIntBig(self: *Self, comptime T: type) !T {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            try self.readNoEof(bytes[0..]);
            return mem.readIntBig(T, &bytes);
        }

        pub fn readInt(self: *Self, comptime T: type, endian: builtin.Endian) !T {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            try self.readNoEof(bytes[0..]);
            return mem.readInt(T, &bytes, endian);
        }

        pub fn readVarInt(self: *Self, comptime ReturnType: type, endian: builtin.Endian, size: usize) !ReturnType {
            assert(size <= @sizeOf(ReturnType));
            var bytes_buf: [@sizeOf(ReturnType)]u8 = undefined;
            const bytes = bytes_buf[0..size];
            try self.readNoEof(bytes);
            return mem.readVarInt(ReturnType, bytes, endian);
        }

        pub fn skipBytes(self: *Self, num_bytes: u64) !void {
            var i: u64 = 0;
            while (i < num_bytes) : (i += 1) {
                _ = try self.readByte();
            }
        }

        pub fn readStruct(self: *Self, comptime T: type) !T {
            // Only extern and packed structs have defined in-memory layout.
            comptime assert(@typeInfo(T).Struct.layout != builtin.TypeInfo.ContainerLayout.Auto);
            var res: [1]T = undefined;
            try self.readNoEof(@sliceToBytes(res[0..]));
            return res[0];
        }
    };
}

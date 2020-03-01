const std = @import("std.zig");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const mem = std.mem;
const os = std.os;
const builtin = @import("builtin");
const c = std.c;
const maxInt = std.math.maxInt;

pub const LoggingAllocator = @import("heap/logging_allocator.zig").LoggingAllocator;

const Allocator = mem.Allocator;

pub const c_allocator = &c_allocator_state;
var c_allocator_state = Allocator{
    .reallocFn = cRealloc,
    .shrinkFn = cShrink,
};

fn cRealloc(self: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
    assert(new_align <= @alignOf(c_longdouble));
    const old_ptr = if (old_mem.len == 0) null else @ptrCast(*c_void, old_mem.ptr);
    const buf = c.realloc(old_ptr, new_size) orelse return error.OutOfMemory;
    return @ptrCast([*]u8, buf)[0..new_size];
}

fn cShrink(self: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
    const old_ptr = @ptrCast(*c_void, old_mem.ptr);
    const buf = c.realloc(old_ptr, new_size) orelse return old_mem[0..new_size];
    return @ptrCast([*]u8, buf)[0..new_size];
}

/// This allocator makes a syscall directly for every allocation and free.
/// Thread-safe and lock-free.
pub const direct_allocator = &direct_allocator_state;
var direct_allocator_state = Allocator{
    .reallocFn = DirectAllocator.realloc,
    .shrinkFn = DirectAllocator.shrink,
};

const DirectAllocator = struct {
    fn alloc(allocator: *Allocator, n: usize, alignment: u29) error{OutOfMemory}![]u8 {
        if (n == 0)
            return (([*]u8)(undefined))[0..0];

        if (os.windows.is_the_target) {
            const w = os.windows;

            // Although officially it's at least aligned to page boundary,
            // Windows is known to reserve pages on a 64K boundary. It's
            // even more likely that the requested alignment is <= 64K than
            // 4K, so we're just allocating blindly and hoping for the best.
            // see https://devblogs.microsoft.com/oldnewthing/?p=42223
            const addr = w.VirtualAlloc(
                null,
                n,
                w.MEM_COMMIT | w.MEM_RESERVE,
                w.PAGE_READWRITE,
            ) catch return error.OutOfMemory;

            // If the allocation is sufficiently aligned, use it.
            if (@ptrToInt(addr) & (alignment - 1) == 0) {
                return @ptrCast([*]u8, addr)[0..n];
            }

            // If it wasn't, actually do an explicitely aligned allocation.
            w.VirtualFree(addr, 0, w.MEM_RELEASE);
            const alloc_size = n + alignment;

            const final_addr = while (true) {
                // Reserve a range of memory large enough to find a sufficiently
                // aligned address.
                const reserved_addr = w.VirtualAlloc(
                    null,
                    alloc_size,
                    w.MEM_RESERVE,
                    w.PAGE_NOACCESS,
                ) catch return error.OutOfMemory;
                const aligned_addr = mem.alignForward(@ptrToInt(reserved_addr), alignment);

                // Release the reserved pages (not actually used).
                w.VirtualFree(reserved_addr, 0, w.MEM_RELEASE);

                // At this point, it is possible that another thread has
                // obtained some memory space that will cause the next
                // VirtualAlloc call to fail. To handle this, we will retry
                // until it succeeds.
                const ptr = w.VirtualAlloc(
                    @intToPtr(*c_void, aligned_addr),
                    n,
                    w.MEM_COMMIT | w.MEM_RESERVE,
                    w.PAGE_READWRITE,
                ) catch continue;

                return @ptrCast([*]u8, ptr)[0..n];
            };

            return @ptrCast([*]u8, final_addr)[0..n];
        }

        const alloc_size = if (alignment <= mem.page_size) n else n + alignment;
        const slice = os.mmap(
            null,
            mem.alignForward(alloc_size, mem.page_size),
            os.PROT_READ | os.PROT_WRITE,
            os.MAP_PRIVATE | os.MAP_ANONYMOUS,
            -1,
            0,
        ) catch return error.OutOfMemory;
        if (alloc_size == n) return slice[0..n];

        const aligned_addr = mem.alignForward(@ptrToInt(slice.ptr), alignment);

        // Unmap the extra bytes that were only requested in order to guarantee
        // that the range of memory we were provided had a proper alignment in
        // it somewhere. The extra bytes could be at the beginning, or end, or both.
        const unused_start_len = aligned_addr - @ptrToInt(slice.ptr);
        if (unused_start_len != 0) {
            os.munmap(slice[0..unused_start_len]);
        }
        const aligned_end_addr = mem.alignForward(aligned_addr + n, mem.page_size);
        const unused_end_len = @ptrToInt(slice.ptr) + slice.len - aligned_end_addr;
        if (unused_end_len != 0) {
            os.munmap(@intToPtr([*]align(mem.page_size) u8, aligned_end_addr)[0..unused_end_len]);
        }

        return @intToPtr([*]u8, aligned_addr)[0..n];
    }

    fn shrink(allocator: *Allocator, old_mem_unaligned: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
        const old_mem = @alignCast(mem.page_size, old_mem_unaligned);
        if (os.windows.is_the_target) {
            const w = os.windows;
            if (new_size == 0) {
                // From the docs:
                // "If the dwFreeType parameter is MEM_RELEASE, this parameter
                // must be 0 (zero). The function frees the entire region that
                // is reserved in the initial allocation call to VirtualAlloc."
                // So we can only use MEM_RELEASE when actually releasing the
                // whole allocation.
                w.VirtualFree(old_mem.ptr, 0, w.MEM_RELEASE);
            } else {
                const base_addr = @ptrToInt(old_mem.ptr);
                const old_addr_end = base_addr + old_mem.len;
                const new_addr_end = base_addr + new_size;
                const new_addr_end_rounded = mem.alignForward(new_addr_end, mem.page_size);
                if (old_addr_end > new_addr_end_rounded) {
                    // For shrinking that is not releasing, we will only
                    // decommit the pages not needed anymore.
                    w.VirtualFree(
                        @intToPtr(*c_void, new_addr_end_rounded),
                        old_addr_end - new_addr_end_rounded,
                        w.MEM_DECOMMIT,
                    );
                }
            }
            return old_mem[0..new_size];
        }
        const base_addr = @ptrToInt(old_mem.ptr);
        const old_addr_end = base_addr + old_mem.len;
        const new_addr_end = base_addr + new_size;
        const new_addr_end_rounded = mem.alignForward(new_addr_end, mem.page_size);
        if (old_addr_end > new_addr_end_rounded) {
            const ptr = @intToPtr([*]align(mem.page_size) u8, new_addr_end_rounded);
            os.munmap(ptr[0 .. old_addr_end - new_addr_end_rounded]);
        }
        return old_mem[0..new_size];
    }

    fn realloc(allocator: *Allocator, old_mem_unaligned: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
        const old_mem = @alignCast(mem.page_size, old_mem_unaligned);
        if (os.windows.is_the_target) {
            if (old_mem.len == 0) {
                return alloc(allocator, new_size, new_align);
            }

            if (new_size <= old_mem.len and new_align <= old_align) {
                return shrink(allocator, old_mem, old_align, new_size, new_align);
            }

            const w = os.windows;
            const base_addr = @ptrToInt(old_mem.ptr);

            if (new_align > old_align and base_addr & (new_align - 1) != 0) {
                // Current allocation doesn't satisfy the new alignment.
                // For now we'll do a new one no matter what, but maybe
                // there is something smarter to do instead.
                const result = try alloc(allocator, new_size, new_align);
                assert(old_mem.len != 0);
                @memcpy(result.ptr, old_mem.ptr, std.math.min(old_mem.len, result.len));
                w.VirtualFree(old_mem.ptr, 0, w.MEM_RELEASE);

                return result;
            }

            const old_addr_end = base_addr + old_mem.len;
            const old_addr_end_rounded = mem.alignForward(old_addr_end, mem.page_size);
            const new_addr_end = base_addr + new_size;
            const new_addr_end_rounded = mem.alignForward(new_addr_end, mem.page_size);
            if (new_addr_end_rounded == old_addr_end_rounded) {
                // The reallocation fits in the already allocated pages.
                return @ptrCast([*]u8, old_mem.ptr)[0..new_size];
            }
            assert(new_addr_end_rounded > old_addr_end_rounded);

            // We need to commit new pages.
            const additional_size = new_addr_end - old_addr_end_rounded;
            const realloc_addr = w.kernel32.VirtualAlloc(
                @intToPtr(*c_void, old_addr_end_rounded),
                additional_size,
                w.MEM_COMMIT | w.MEM_RESERVE,
                w.PAGE_READWRITE,
            ) orelse {
                // Committing new pages at the end of the existing allocation
                // failed, we need to try a new one.
                const new_alloc_mem = try alloc(allocator, new_size, new_align);
                @memcpy(new_alloc_mem.ptr, old_mem.ptr, old_mem.len);
                w.VirtualFree(old_mem.ptr, 0, w.MEM_RELEASE);

                return new_alloc_mem;
            };

            assert(@ptrToInt(realloc_addr) == old_addr_end_rounded);
            return @ptrCast([*]u8, old_mem.ptr)[0..new_size];
        }
        if (new_size <= old_mem.len and new_align <= old_align) {
            return shrink(allocator, old_mem, old_align, new_size, new_align);
        }
        const result = try alloc(allocator, new_size, new_align);
        if (old_mem.len != 0) {
            @memcpy(result.ptr, old_mem.ptr, std.math.min(old_mem.len, result.len));
            os.munmap(old_mem);
        }
        return result;
    }
};

pub const HeapAllocator = switch (builtin.os) {
    .windows => struct {
        allocator: Allocator,
        heap_handle: ?HeapHandle,

        const HeapHandle = os.windows.HANDLE;

        pub fn init() HeapAllocator {
            return HeapAllocator{
                .allocator = Allocator{
                    .reallocFn = realloc,
                    .shrinkFn = shrink,
                },
                .heap_handle = null,
            };
        }

        pub fn deinit(self: *HeapAllocator) void {
            if (self.heap_handle) |heap_handle| {
                os.windows.HeapDestroy(heap_handle);
            }
        }

        fn alloc(allocator: *Allocator, n: usize, alignment: u29) error{OutOfMemory}![]u8 {
            const self = @fieldParentPtr(HeapAllocator, "allocator", allocator);
            if (n == 0)
                return (([*]u8)(undefined))[0..0];

            const amt = n + alignment + @sizeOf(usize);
            const optional_heap_handle = @atomicLoad(?HeapHandle, &self.heap_handle, builtin.AtomicOrder.SeqCst);
            const heap_handle = optional_heap_handle orelse blk: {
                const options = if (builtin.single_threaded) os.windows.HEAP_NO_SERIALIZE else 0;
                const hh = os.windows.kernel32.HeapCreate(options, amt, 0) orelse return error.OutOfMemory;
                const other_hh = @cmpxchgStrong(?HeapHandle, &self.heap_handle, null, hh, builtin.AtomicOrder.SeqCst, builtin.AtomicOrder.SeqCst) orelse break :blk hh;
                os.windows.HeapDestroy(hh);
                break :blk other_hh.?; // can't be null because of the cmpxchg
            };
            const ptr = os.windows.kernel32.HeapAlloc(heap_handle, 0, amt) orelse return error.OutOfMemory;
            const root_addr = @ptrToInt(ptr);
            const adjusted_addr = mem.alignForward(root_addr, alignment);
            const record_addr = adjusted_addr + n;
            @intToPtr(*align(1) usize, record_addr).* = root_addr;
            return @intToPtr([*]u8, adjusted_addr)[0..n];
        }

        fn shrink(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
            return realloc(allocator, old_mem, old_align, new_size, new_align) catch {
                const old_adjusted_addr = @ptrToInt(old_mem.ptr);
                const old_record_addr = old_adjusted_addr + old_mem.len;
                const root_addr = @intToPtr(*align(1) usize, old_record_addr).*;
                const old_ptr = @intToPtr(*c_void, root_addr);
                const new_record_addr = old_record_addr - new_size + old_mem.len;
                @intToPtr(*align(1) usize, new_record_addr).* = root_addr;
                return old_mem[0..new_size];
            };
        }

        fn realloc(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
            if (old_mem.len == 0) return alloc(allocator, new_size, new_align);

            const self = @fieldParentPtr(HeapAllocator, "allocator", allocator);
            const old_adjusted_addr = @ptrToInt(old_mem.ptr);
            const old_record_addr = old_adjusted_addr + old_mem.len;
            const root_addr = @intToPtr(*align(1) usize, old_record_addr).*;
            const old_ptr = @intToPtr(*c_void, root_addr);

            if (new_size == 0) {
                os.windows.HeapFree(self.heap_handle.?, 0, old_ptr);
                return old_mem[0..0];
            }

            const amt = new_size + new_align + @sizeOf(usize);
            const new_ptr = os.windows.kernel32.HeapReAlloc(
                self.heap_handle.?,
                0,
                old_ptr,
                amt,
            ) orelse return error.OutOfMemory;
            const offset = old_adjusted_addr - root_addr;
            const new_root_addr = @ptrToInt(new_ptr);
            var new_adjusted_addr = new_root_addr + offset;
            const offset_is_valid = new_adjusted_addr + new_size + @sizeOf(usize) <= new_root_addr + amt;
            const offset_is_aligned = new_adjusted_addr % new_align == 0;
            if (!offset_is_valid or !offset_is_aligned) {
                // If HeapReAlloc didn't happen to move the memory to the new alignment,
                // or the memory starting at the old offset would be outside of the new allocation,
                // then we need to copy the memory to a valid aligned address and use that
                const new_aligned_addr = mem.alignForward(new_root_addr, new_align);
                @memcpy(@intToPtr([*]u8, new_aligned_addr), @intToPtr([*]u8, new_adjusted_addr), std.math.min(old_mem.len, new_size));
                new_adjusted_addr = new_aligned_addr;
            }
            const new_record_addr = new_adjusted_addr + new_size;
            @intToPtr(*align(1) usize, new_record_addr).* = new_root_addr;
            return @intToPtr([*]u8, new_adjusted_addr)[0..new_size];
        }
    },
    else => @compileError("Unsupported OS"),
};

/// This allocator takes an existing allocator, wraps it, and provides an interface
/// where you can allocate without freeing, and then free it all together.
pub const ArenaAllocator = struct {
    pub allocator: Allocator,

    child_allocator: *Allocator,
    buffer_list: std.SinglyLinkedList([]u8),
    end_index: usize,

    const BufNode = std.SinglyLinkedList([]u8).Node;

    pub fn init(child_allocator: *Allocator) ArenaAllocator {
        return ArenaAllocator{
            .allocator = Allocator{
                .reallocFn = realloc,
                .shrinkFn = shrink,
            },
            .child_allocator = child_allocator,
            .buffer_list = std.SinglyLinkedList([]u8).init(),
            .end_index = 0,
        };
    }

    pub fn deinit(self: *ArenaAllocator) void {
        var it = self.buffer_list.first;
        while (it) |node| {
            // this has to occur before the free because the free frees node
            const next_it = node.next;
            self.child_allocator.free(node.data);
            it = next_it;
        }
    }

    fn createNode(self: *ArenaAllocator, prev_len: usize, minimum_size: usize) !*BufNode {
        const actual_min_size = minimum_size + @sizeOf(BufNode);
        var len = prev_len;
        while (true) {
            len += len / 2;
            len += mem.page_size - @rem(len, mem.page_size);
            if (len >= actual_min_size) break;
        }
        const buf = try self.child_allocator.alignedAlloc(u8, @alignOf(BufNode), len);
        const buf_node_slice = @bytesToSlice(BufNode, buf[0..@sizeOf(BufNode)]);
        const buf_node = &buf_node_slice[0];
        buf_node.* = BufNode{
            .data = buf,
            .next = null,
        };
        self.buffer_list.prepend(buf_node);
        self.end_index = 0;
        return buf_node;
    }

    fn alloc(allocator: *Allocator, n: usize, alignment: u29) ![]u8 {
        const self = @fieldParentPtr(ArenaAllocator, "allocator", allocator);

        var cur_node = if (self.buffer_list.first) |first_node| first_node else try self.createNode(0, n + alignment);
        while (true) {
            const cur_buf = cur_node.data[@sizeOf(BufNode)..];
            const addr = @ptrToInt(cur_buf.ptr) + self.end_index;
            const adjusted_addr = mem.alignForward(addr, alignment);
            const adjusted_index = self.end_index + (adjusted_addr - addr);
            const new_end_index = adjusted_index + n;
            if (new_end_index > cur_buf.len) {
                cur_node = try self.createNode(cur_buf.len, n + alignment);
                continue;
            }
            const result = cur_buf[adjusted_index..new_end_index];
            self.end_index = new_end_index;
            return result;
        }
    }

    fn realloc(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
        if (new_size <= old_mem.len and new_align <= new_size) {
            // We can't do anything with the memory, so tell the client to keep it.
            return error.OutOfMemory;
        } else {
            const result = try alloc(allocator, new_size, new_align);
            @memcpy(result.ptr, old_mem.ptr, std.math.min(old_mem.len, result.len));
            return result;
        }
    }

    fn shrink(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
        return old_mem[0..new_size];
    }
};

pub const FixedBufferAllocator = struct {
    allocator: Allocator,
    end_index: usize,
    buffer: []u8,

    pub fn init(buffer: []u8) FixedBufferAllocator {
        return FixedBufferAllocator{
            .allocator = Allocator{
                .reallocFn = realloc,
                .shrinkFn = shrink,
            },
            .buffer = buffer,
            .end_index = 0,
        };
    }

    fn alloc(allocator: *Allocator, n: usize, alignment: u29) ![]u8 {
        const self = @fieldParentPtr(FixedBufferAllocator, "allocator", allocator);
        const addr = @ptrToInt(self.buffer.ptr) + self.end_index;
        const adjusted_addr = mem.alignForward(addr, alignment);
        const adjusted_index = self.end_index + (adjusted_addr - addr);
        const new_end_index = adjusted_index + n;
        if (new_end_index > self.buffer.len) {
            return error.OutOfMemory;
        }
        const result = self.buffer[adjusted_index..new_end_index];
        self.end_index = new_end_index;

        return result;
    }

    fn realloc(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
        const self = @fieldParentPtr(FixedBufferAllocator, "allocator", allocator);
        assert(old_mem.len <= self.end_index);
        if (old_mem.ptr == self.buffer.ptr + self.end_index - old_mem.len and
            mem.alignForward(@ptrToInt(old_mem.ptr), new_align) == @ptrToInt(old_mem.ptr))
        {
            const start_index = self.end_index - old_mem.len;
            const new_end_index = start_index + new_size;
            if (new_end_index > self.buffer.len) return error.OutOfMemory;
            const result = self.buffer[start_index..new_end_index];
            self.end_index = new_end_index;
            return result;
        } else if (new_size <= old_mem.len and new_align <= old_align) {
            // We can't do anything with the memory, so tell the client to keep it.
            return error.OutOfMemory;
        } else {
            const result = try alloc(allocator, new_size, new_align);
            @memcpy(result.ptr, old_mem.ptr, std.math.min(old_mem.len, result.len));
            return result;
        }
    }

    fn shrink(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
        return old_mem[0..new_size];
    }

    pub fn reset(self: *FixedBufferAllocator) void {
        self.end_index = 0;
    }
};

// FIXME: Exposed LLVM intrinsics is a bug
// See: https://github.com/ziglang/zig/issues/2291
extern fn @"llvm.wasm.memory.size.i32"(u32) u32;
extern fn @"llvm.wasm.memory.grow.i32"(u32, u32) i32;

pub const wasm_allocator = &wasm_allocator_state.allocator;
var wasm_allocator_state = WasmAllocator{
    .allocator = Allocator{
        .reallocFn = WasmAllocator.realloc,
        .shrinkFn = WasmAllocator.shrink,
    },
    .start_ptr = undefined,
    .num_pages = 0,
    .end_index = 0,
};

const WasmAllocator = struct {
    allocator: Allocator,
    start_ptr: [*]u8,
    num_pages: usize,
    end_index: usize,

    comptime {
        if (builtin.arch != .wasm32) {
            @compileError("WasmAllocator is only available for wasm32 arch");
        }
    }

    fn alloc(allocator: *Allocator, size: usize, alignment: u29) ![]u8 {
        const self = @fieldParentPtr(WasmAllocator, "allocator", allocator);

        const addr = @ptrToInt(self.start_ptr) + self.end_index;
        const adjusted_addr = mem.alignForward(addr, alignment);
        const adjusted_index = self.end_index + (adjusted_addr - addr);
        const new_end_index = adjusted_index + size;

        if (new_end_index > self.num_pages * mem.page_size) {
            const required_memory = new_end_index - (self.num_pages * mem.page_size);

            var num_pages: usize = required_memory / mem.page_size;
            if (required_memory % mem.page_size != 0) {
                num_pages += 1;
            }

            const prev_page = @"llvm.wasm.memory.grow.i32"(0, @intCast(u32, num_pages));
            if (prev_page == -1) {
                return error.OutOfMemory;
            }

            self.num_pages += num_pages;
        }

        const result = self.start_ptr[adjusted_index..new_end_index];
        self.end_index = new_end_index;

        return result;
    }

    // Check if memory is the last "item" and is aligned correctly
    fn is_last_item(allocator: *Allocator, memory: []u8, alignment: u29) bool {
        const self = @fieldParentPtr(WasmAllocator, "allocator", allocator);
        return memory.ptr == self.start_ptr + self.end_index - memory.len and mem.alignForward(@ptrToInt(memory.ptr), alignment) == @ptrToInt(memory.ptr);
    }

    fn realloc(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
        const self = @fieldParentPtr(WasmAllocator, "allocator", allocator);

        // Initialize start_ptr at the first realloc
        if (self.num_pages == 0) {
            self.start_ptr = @intToPtr([*]u8, @intCast(usize, @"llvm.wasm.memory.size.i32"(0)) * mem.page_size);
        }

        if (is_last_item(allocator, old_mem, new_align)) {
            const start_index = self.end_index - old_mem.len;
            const new_end_index = start_index + new_size;

            if (new_end_index > self.num_pages * mem.page_size) {
                _ = try alloc(allocator, new_end_index - self.end_index, new_align);
            }
            const result = self.start_ptr[start_index..new_end_index];

            self.end_index = new_end_index;
            return result;
        } else if (new_size <= old_mem.len and new_align <= old_align) {
            return error.OutOfMemory;
        } else {
            const result = try alloc(allocator, new_size, new_align);
            mem.copy(u8, result, old_mem);
            return result;
        }
    }

    fn shrink(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
        return old_mem[0..new_size];
    }
};

pub const ThreadSafeFixedBufferAllocator = blk: {
    if (builtin.single_threaded) {
        break :blk FixedBufferAllocator;
    } else {
        // lock free
        break :blk struct {
            allocator: Allocator,
            end_index: usize,
            buffer: []u8,

            pub fn init(buffer: []u8) ThreadSafeFixedBufferAllocator {
                return ThreadSafeFixedBufferAllocator{
                    .allocator = Allocator{
                        .reallocFn = realloc,
                        .shrinkFn = shrink,
                    },
                    .buffer = buffer,
                    .end_index = 0,
                };
            }

            fn alloc(allocator: *Allocator, n: usize, alignment: u29) ![]u8 {
                const self = @fieldParentPtr(ThreadSafeFixedBufferAllocator, "allocator", allocator);
                var end_index = @atomicLoad(usize, &self.end_index, builtin.AtomicOrder.SeqCst);
                while (true) {
                    const addr = @ptrToInt(self.buffer.ptr) + end_index;
                    const adjusted_addr = mem.alignForward(addr, alignment);
                    const adjusted_index = end_index + (adjusted_addr - addr);
                    const new_end_index = adjusted_index + n;
                    if (new_end_index > self.buffer.len) {
                        return error.OutOfMemory;
                    }
                    end_index = @cmpxchgWeak(usize, &self.end_index, end_index, new_end_index, builtin.AtomicOrder.SeqCst, builtin.AtomicOrder.SeqCst) orelse return self.buffer[adjusted_index..new_end_index];
                }
            }

            fn realloc(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
                if (new_size <= old_mem.len and new_align <= old_align) {
                    // We can't do anything useful with the memory, tell the client to keep it.
                    return error.OutOfMemory;
                } else {
                    const result = try alloc(allocator, new_size, new_align);
                    @memcpy(result.ptr, old_mem.ptr, std.math.min(old_mem.len, result.len));
                    return result;
                }
            }

            fn shrink(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
                return old_mem[0..new_size];
            }
        };
    }
};

pub fn stackFallback(comptime size: usize, fallback_allocator: *Allocator) StackFallbackAllocator(size) {
    return StackFallbackAllocator(size){
        .buffer = undefined,
        .fallback_allocator = fallback_allocator,
        .fixed_buffer_allocator = undefined,
        .allocator = Allocator{
            .reallocFn = StackFallbackAllocator(size).realloc,
            .shrinkFn = StackFallbackAllocator(size).shrink,
        },
    };
}

pub fn StackFallbackAllocator(comptime size: usize) type {
    return struct {
        const Self = @This();

        buffer: [size]u8,
        allocator: Allocator,
        fallback_allocator: *Allocator,
        fixed_buffer_allocator: FixedBufferAllocator,

        pub fn get(self: *Self) *Allocator {
            self.fixed_buffer_allocator = FixedBufferAllocator.init(self.buffer[0..]);
            return &self.allocator;
        }

        fn realloc(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
            const self = @fieldParentPtr(Self, "allocator", allocator);
            const in_buffer = @ptrToInt(old_mem.ptr) >= @ptrToInt(&self.buffer) and
                @ptrToInt(old_mem.ptr) < @ptrToInt(&self.buffer) + self.buffer.len;
            if (in_buffer) {
                return FixedBufferAllocator.realloc(
                    &self.fixed_buffer_allocator.allocator,
                    old_mem,
                    old_align,
                    new_size,
                    new_align,
                ) catch {
                    const result = try self.fallback_allocator.reallocFn(
                        self.fallback_allocator,
                        ([*]u8)(undefined)[0..0],
                        undefined,
                        new_size,
                        new_align,
                    );
                    mem.copy(u8, result, old_mem);
                    return result;
                };
            }
            return self.fallback_allocator.reallocFn(
                self.fallback_allocator,
                old_mem,
                old_align,
                new_size,
                new_align,
            );
        }

        fn shrink(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
            const self = @fieldParentPtr(Self, "allocator", allocator);
            const in_buffer = @ptrToInt(old_mem.ptr) >= @ptrToInt(&self.buffer) and
                @ptrToInt(old_mem.ptr) < @ptrToInt(&self.buffer) + self.buffer.len;
            if (in_buffer) {
                return FixedBufferAllocator.shrink(
                    &self.fixed_buffer_allocator.allocator,
                    old_mem,
                    old_align,
                    new_size,
                    new_align,
                );
            }
            return self.fallback_allocator.shrinkFn(
                self.fallback_allocator,
                old_mem,
                old_align,
                new_size,
                new_align,
            );
        }
    };
}

test "c_allocator" {
    if (builtin.link_libc) {
        var slice = try c_allocator.alloc(u8, 50);
        defer c_allocator.free(slice);
        slice = try c_allocator.realloc(slice, 100);
    }
}

test "DirectAllocator" {
    const allocator = direct_allocator;
    try testAllocator(allocator);
    try testAllocatorAligned(allocator, 16);
    try testAllocatorLargeAlignment(allocator);
    try testAllocatorAlignedShrink(allocator);

    if (builtin.os == .windows) {
        // Trying really large alignment. As mentionned in the implementation,
        // VirtualAlloc returns 64K aligned addresses. We want to make sure
        // DirectAllocator works beyond that, as it's not tested by
        // `testAllocatorLargeAlignment`.
        const slice = try allocator.alignedAlloc(u8, 1 << 20, 128);
        slice[0] = 0x12;
        slice[127] = 0x34;
        allocator.free(slice);
    }
}

test "HeapAllocator" {
    if (builtin.os == .windows) {
        var heap_allocator = HeapAllocator.init();
        defer heap_allocator.deinit();

        const allocator = &heap_allocator.allocator;
        try testAllocator(allocator);
        try testAllocatorAligned(allocator, 16);
        try testAllocatorLargeAlignment(allocator);
        try testAllocatorAlignedShrink(allocator);
    }
}

test "ArenaAllocator" {
    var arena_allocator = ArenaAllocator.init(direct_allocator);
    defer arena_allocator.deinit();

    try testAllocator(&arena_allocator.allocator);
    try testAllocatorAligned(&arena_allocator.allocator, 16);
    try testAllocatorLargeAlignment(&arena_allocator.allocator);
    try testAllocatorAlignedShrink(&arena_allocator.allocator);
}

var test_fixed_buffer_allocator_memory: [80000 * @sizeOf(u64)]u8 = undefined;
test "FixedBufferAllocator" {
    var fixed_buffer_allocator = FixedBufferAllocator.init(test_fixed_buffer_allocator_memory[0..]);

    try testAllocator(&fixed_buffer_allocator.allocator);
    try testAllocatorAligned(&fixed_buffer_allocator.allocator, 16);
    try testAllocatorLargeAlignment(&fixed_buffer_allocator.allocator);
    try testAllocatorAlignedShrink(&fixed_buffer_allocator.allocator);
}

test "FixedBufferAllocator.reset" {
    var buf: [8]u8 align(@alignOf(u64)) = undefined;
    var fba = FixedBufferAllocator.init(buf[0..]);

    const X = 0xeeeeeeeeeeeeeeee;
    const Y = 0xffffffffffffffff;

    var x = try fba.allocator.create(u64);
    x.* = X;
    testing.expectError(error.OutOfMemory, fba.allocator.create(u64));

    fba.reset();
    var y = try fba.allocator.create(u64);
    y.* = Y;

    // we expect Y to have overwritten X.
    testing.expect(x.* == y.*);
    testing.expect(y.* == Y);
}

test "FixedBufferAllocator Reuse memory on realloc" {
    var small_fixed_buffer: [10]u8 = undefined;
    // check if we re-use the memory
    {
        var fixed_buffer_allocator = FixedBufferAllocator.init(small_fixed_buffer[0..]);

        var slice0 = try fixed_buffer_allocator.allocator.alloc(u8, 5);
        testing.expect(slice0.len == 5);
        var slice1 = try fixed_buffer_allocator.allocator.realloc(slice0, 10);
        testing.expect(slice1.ptr == slice0.ptr);
        testing.expect(slice1.len == 10);
        testing.expectError(error.OutOfMemory, fixed_buffer_allocator.allocator.realloc(slice1, 11));
    }
    // check that we don't re-use the memory if it's not the most recent block
    {
        var fixed_buffer_allocator = FixedBufferAllocator.init(small_fixed_buffer[0..]);

        var slice0 = try fixed_buffer_allocator.allocator.alloc(u8, 2);
        slice0[0] = 1;
        slice0[1] = 2;
        var slice1 = try fixed_buffer_allocator.allocator.alloc(u8, 2);
        var slice2 = try fixed_buffer_allocator.allocator.realloc(slice0, 4);
        testing.expect(slice0.ptr != slice2.ptr);
        testing.expect(slice1.ptr != slice2.ptr);
        testing.expect(slice2[0] == 1);
        testing.expect(slice2[1] == 2);
    }
}

test "ThreadSafeFixedBufferAllocator" {
    var fixed_buffer_allocator = ThreadSafeFixedBufferAllocator.init(test_fixed_buffer_allocator_memory[0..]);

    try testAllocator(&fixed_buffer_allocator.allocator);
    try testAllocatorAligned(&fixed_buffer_allocator.allocator, 16);
    try testAllocatorLargeAlignment(&fixed_buffer_allocator.allocator);
    try testAllocatorAlignedShrink(&fixed_buffer_allocator.allocator);
}

fn testAllocator(allocator: *mem.Allocator) !void {
    var slice = try allocator.alloc(*i32, 100);
    testing.expect(slice.len == 100);
    for (slice) |*item, i| {
        item.* = try allocator.create(i32);
        item.*.* = @intCast(i32, i);
    }

    slice = try allocator.realloc(slice, 20000);
    testing.expect(slice.len == 20000);

    for (slice[0..100]) |item, i| {
        testing.expect(item.* == @intCast(i32, i));
        allocator.destroy(item);
    }

    slice = allocator.shrink(slice, 50);
    testing.expect(slice.len == 50);
    slice = allocator.shrink(slice, 25);
    testing.expect(slice.len == 25);
    slice = allocator.shrink(slice, 0);
    testing.expect(slice.len == 0);
    slice = try allocator.realloc(slice, 10);
    testing.expect(slice.len == 10);

    allocator.free(slice);
}

fn testAllocatorAligned(allocator: *mem.Allocator, comptime alignment: u29) !void {
    // initial
    var slice = try allocator.alignedAlloc(u8, alignment, 10);
    testing.expect(slice.len == 10);
    // grow
    slice = try allocator.realloc(slice, 100);
    testing.expect(slice.len == 100);
    // shrink
    slice = allocator.shrink(slice, 10);
    testing.expect(slice.len == 10);
    // go to zero
    slice = allocator.shrink(slice, 0);
    testing.expect(slice.len == 0);
    // realloc from zero
    slice = try allocator.realloc(slice, 100);
    testing.expect(slice.len == 100);
    // shrink with shrink
    slice = allocator.shrink(slice, 10);
    testing.expect(slice.len == 10);
    // shrink to zero
    slice = allocator.shrink(slice, 0);
    testing.expect(slice.len == 0);
}

fn testAllocatorLargeAlignment(allocator: *mem.Allocator) mem.Allocator.Error!void {
    //Maybe a platform's page_size is actually the same as or
    //  very near usize?
    if (mem.page_size << 2 > maxInt(usize)) return;

    const USizeShift = @IntType(false, std.math.log2(usize.bit_count));
    const large_align = u29(mem.page_size << 2);

    var align_mask: usize = undefined;
    _ = @shlWithOverflow(usize, ~usize(0), USizeShift(@ctz(u29, large_align)), &align_mask);

    var slice = try allocator.alignedAlloc(u8, large_align, 500);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    slice = allocator.shrink(slice, 100);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    slice = try allocator.realloc(slice, 5000);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    slice = allocator.shrink(slice, 10);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    slice = try allocator.realloc(slice, 20000);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    allocator.free(slice);
}

fn testAllocatorAlignedShrink(allocator: *mem.Allocator) mem.Allocator.Error!void {
    var debug_buffer: [1000]u8 = undefined;
    const debug_allocator = &FixedBufferAllocator.init(&debug_buffer).allocator;

    const alloc_size = mem.page_size * 2 + 50;
    var slice = try allocator.alignedAlloc(u8, 16, alloc_size);
    defer allocator.free(slice);

    var stuff_to_free = std.ArrayList([]align(16) u8).init(debug_allocator);
    // On Windows, VirtualAlloc returns addresses aligned to a 64K boundary,
    // which is 16 pages, hence the 32. This test may require to increase
    // the size of the allocations feeding the `allocator` parameter if they
    // fail, because of this high over-alignment we want to have.
    while (@ptrToInt(slice.ptr) == mem.alignForward(@ptrToInt(slice.ptr), mem.page_size * 32)) {
        try stuff_to_free.append(slice);
        slice = try allocator.alignedAlloc(u8, 16, alloc_size);
    }
    while (stuff_to_free.popOrNull()) |item| {
        allocator.free(item);
    }
    slice[0] = 0x12;
    slice[60] = 0x34;

    // realloc to a smaller size but with a larger alignment
    slice = try allocator.alignedRealloc(slice, mem.page_size * 32, alloc_size / 2);
    testing.expect(slice[0] == 0x12);
    testing.expect(slice[60] == 0x34);
}

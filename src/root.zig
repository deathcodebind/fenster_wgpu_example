//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const fenster = @import("c.zig");

pub const Fenster = struct {
    fenster: fenster.fenster,
};

pub fn new(comptime w: i32, comptime h: i32, title: [:0]const u8) type {
    const buf: [w * h]u32 = undefined;
    const f = .{
        .width = w,
        .height = h,
        .title = title,
        .buf = buf,
    };
    fenster.fenster_open(&f);
    return struct {
        const Self = @This();
        pub fn close(self: *Self) void {
            _ = self;
            fenster.fenster_close(&f);
        }
    };
}

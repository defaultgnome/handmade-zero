//! we use, as casey says, a "Game as a Service to the OS" architecture style.
//! this means that here we start the platform code, and each platform will call the game API in certain entry points.
//! The Platform calls the Game, not the other way around.

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform/platform.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    try platform.run();
}

// ================
// === GAME API ===
// ================

// TODO: probably we want to keep here only the handful public Game API the platform will use
// and move all the internal logic to a separate 'game' module.

pub const OffscreenBuffer = struct {
    bits: ?*anyopaque = null,
    width: i32,
    height: i32,
    pitch: usize,
};

/// x_offset, y_offset are used for green/blue offset -- Toy example, will be removed
pub fn updateAndRender(buffer: *OffscreenBuffer, x_offset: i32, y_offset: i32) void {
    renderWeirdGradient(buffer, x_offset, y_offset);
}

fn renderWeirdGradient(buffer: *OffscreenBuffer, x_offset: i32, y_offset: i32) void {
    const h = @as(usize, @intCast(buffer.height));
    const w = @as(usize, @intCast(buffer.width));
    var row: [*]u8 = @ptrCast(buffer.bits);
    for (0..h) |y| {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        for (0..w) |x| {
            const blue: u8 = @truncate(@abs(@as(i32, @intCast(x)) + x_offset));
            const green: u16 = @truncate(@abs(@as(i32, @intCast(y)) + y_offset));
            pixel[0] = (green << 8) | blue;
            pixel += 1;
        }
        row += buffer.pitch;
    }
}

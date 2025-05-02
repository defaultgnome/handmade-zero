//! we use, as casey says, a "Game as a Service to the OS" architecture style.
//! this means that here we start the platform code, and each platform will call the game API in certain entry points.
//! The Platform calls the Game, not the other way around.

const std = @import("std");
const platform = @import("platform/platform.zig");

const OffscreenBuffer = platform.OffscreenBuffer;
const SoundBuffer = platform.SoundBuffer;

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

/// x_offset, y_offset are used for green/blue offset -- Toy example, will be removed
pub fn updateAndRender(buffer: *OffscreenBuffer, sound_buffer: *SoundBuffer, x_offset: i32, y_offset: i32, tone_hz: u32) void {
    outputSound(sound_buffer, tone_hz);
    renderWeirdGradient(buffer, x_offset, y_offset);
}

// ---- Internal API ----
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

var t_sine: f32 = 0;
fn outputSound(sound_buffer: *SoundBuffer, tone_hz: u32) void {
    const tone_volume = 0.1 * 32_768;
    const wave_period = sound_buffer.sample_rate / tone_hz;

    var sample_out: [*]i16 = sound_buffer.samples;

    for (0..sound_buffer.sample_count) |_| {
        const sine_value: f32 = @sin(t_sine);
        const sample_value: i16 = @intFromFloat(sine_value * tone_volume);
        sample_out[0] = sample_value;
        sample_out[1] = sample_value;
        sample_out += 2;

        t_sine += (std.math.tau * 1) / @as(f32, @floatFromInt(wave_period));
    }
}

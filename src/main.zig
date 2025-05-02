//! see platform/platform.zig for more details

const std = @import("std");
const platform = @import("platform/platform.zig");

const OffscreenBuffer = platform.OffscreenBuffer;
const SoundBuffer = platform.SoundBuffer;

pub const std_options: std.Options = .{
    .log_level = .info,
    // TODO(ariel): move this part of the enigne to platform/engine, and merge here
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .engine, .level = .info },
    },
};

pub fn main() !void {
    try platform.run();
}

// ================
// === GAME API ===
// ================

// TODO: probably we want to keep here only the handful public Game API the platform will use
// and move all the internal logic to a separate 'game' module.

///  variables for Toy example, will be removed
var global_blue_offset: i32 = 0;
var global_green_offset: i32 = 0;
var global_tone_hz: i32 = 256;

pub fn updateAndRender(input: *platform.Input, buffer: *OffscreenBuffer, sound_buffer: *SoundBuffer) void {
    var input0 = &input.controllers[0];
    if (input0.is_analog) {
        // TODO(casey): will need to move everything to floats
        global_blue_offset += @intFromFloat(4 * input0.end_x);
        global_tone_hz = 256 + @as(i32, @intFromFloat(128 * input0.end_y));
    } else {}

    if (input0.getButton(.down).ended_down) {
        global_green_offset += 1;
    }

    outputSound(sound_buffer, global_tone_hz);
    renderWeirdGradient(buffer, global_blue_offset, global_green_offset);
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
fn outputSound(sound_buffer: *SoundBuffer, tone_hz: i32) void {
    const tone_volume = 0.1 * 32_768;
    const wave_period: f32 = @as(f32, @floatFromInt(sound_buffer.sample_rate)) / @as(f32, @floatFromInt(tone_hz));

    var sample_out: [*]i16 = sound_buffer.samples;

    for (0..sound_buffer.sample_count) |_| {
        const sine_value: f32 = @sin(t_sine);
        const sample_value: i16 = @intFromFloat(sine_value * tone_volume);
        sample_out[0] = sample_value;
        sample_out[1] = sample_value;
        sample_out += 2;

        t_sine += (std.math.tau * 1) / wave_period;
    }
}

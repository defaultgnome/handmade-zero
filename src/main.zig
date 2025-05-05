const std = @import("std");
const engine = @import("engine");

// TODO(ariel): should we base this on optimize target?
pub const std_options: std.Options = .{
    .log_level = .debug,
    // TODO(ariel): move this part to the enigne and merge here
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .engine, .level = .debug },
    },
};

pub fn main() !void {
    try engine.run(.{
        .update = update,
    });
}

// ================
// === GAME API ===
// ================

const GameState = struct {
    blue_offset: i32,
    green_offset: i32,
    tone_hz: i32,
};

// TODO: probably we want to keep here only the handful public Game API the platform will use
// and move all the internal logic to a separate 'game' module.

pub fn update(memory: *engine.Memory, input: *engine.Input, buffer: *engine.OffscreenBuffer, sound_buffer: *engine.SoundBuffer) void {
    std.debug.assert(@sizeOf(GameState) <= memory.permanent_storage_size);

    var game_state: *GameState = @alignCast(@ptrCast(memory.permanent_storage));
    if (!memory.is_initialized) {
        // const file = platform.debug.readEntireFile("test.txt");
        // if (file.contents != null) {
        //     _ = platform.debug.writeEntireFile("test2.txt", file.contents.?, file.size);
        //     platform.debug.freeFileMemory(file.contents.?);
        // }
        game_state.tone_hz = 256;
        memory.is_initialized = true;
    }

    for (&input.controllers) |*controller| {
        if (!controller.is_connected) {
            continue;
        }

        if (controller.is_analog) {
            game_state.blue_offset += @intFromFloat(4 * controller.stick_average_x);
            game_state.tone_hz = 256 + @as(i32, @intFromFloat(128 * controller.stick_average_y));
        } else {
            if (controller.getButton(.move_left).ended_down) {
                game_state.blue_offset -= 1;
            } else if (controller.getButton(.move_right).ended_down) {
                game_state.blue_offset += 1;
            }
        }

        if (controller.getButton(.move_down).ended_down) {
            game_state.green_offset += 1;
        } else if (controller.getButton(.move_up).ended_down) {
            game_state.green_offset -= 1;
        }
    }

    outputSound(sound_buffer, game_state.tone_hz);
    renderWeirdGradient(buffer, game_state.blue_offset, game_state.green_offset);
}

// ---- Internal API ----
fn renderWeirdGradient(buffer: *engine.OffscreenBuffer, x_offset: i32, y_offset: i32) void {
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
fn outputSound(sound_buffer: *engine.SoundBuffer, tone_hz: i32) void {
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

//! A.K.A. the Engine
const std = @import("std");
const builtin = @import("builtin");

pub const windows = @import("./windows/windows.zig");

pub const log = std.log.scoped(.engine);

pub fn run() !void {
    switch (builtin.os.tag) {
        .windows => {
            try windows.run();
        },
        else => {
            @compileError("Unsupported platform");
        },
    }
}

/// this is the buffer that the game will draw to
pub const OffscreenBuffer = struct {
    bits: ?*anyopaque = null,
    width: i32,
    height: i32,
    pitch: usize,
};

/// this is the buffer that the game will use to play sound
pub const SoundBuffer = struct {
    sample_rate: u32,
    samples: [*]i16,
    sample_count: usize,
};

pub const Input = struct {
    controllers: [4]Controller,

    pub const Controller = struct {
        // TODO(ariel): extend to both sticks? (for chanllenge / need)
        /// if false, values will be set to the extreme values: -1.0f and 1.0f
        is_analog: bool,

        start_x: f32,
        start_y: f32,
        min_x: f32,
        min_y: f32,
        max_x: f32,
        max_y: f32,
        end_x: f32,
        end_y: f32,

        // TODO(ariel): is it better to have c union here?
        /// up, down, left, right, left_shoulder, right_shoulder
        buttons: [6]ButtonState,

        pub const ButtonState = struct {
            ended_down: bool,
            half_transition_count: u8,
        };

        pub const ButtonLabel = enum(usize) {
            // TODO(ariel): i think up, down, left, right should be used for dpad, and a, b, x, y for the buttons
            // or to be generic for more contorllers arrow_up and button_up
            /// y
            up = 0,
            /// a
            down = 1,
            /// x
            left = 2,
            /// b
            right = 3,
            left_shoulder = 4,
            right_shoulder = 5,
        };

        pub fn getButton(self: *Controller, label: ButtonLabel) *ButtonState {
            return &self.buttons[@intFromEnum(label)];
        }
    };
};

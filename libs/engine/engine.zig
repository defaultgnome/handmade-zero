//! A.K.A. the Engine
//!
//! we use, as casey says, a "Game as a Service to the OS" architecture style.
//! this means that here we start the platform code, and each platform will call the game API in certain entry points.
//! The Platform calls the Game, not the other way around.
//!
//! we need main.zig to impleament the Game API

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

// platforms, should be private and not exposed directly to the game
const windows = @import("./platform/windows/windows.zig");

// ---- here lie the function that the platform will call ----
pub const GameVTable = struct {
    update: *const fn (memory: *Memory, input: *Input, buffer: *OffscreenBuffer, sound_buffer: *SoundBuffer) void,
};

// ---- need to be called by the main.zig ----

/// need to be called by the main.zig
pub fn run(vtable: GameVTable) !void {
    switch (builtin.os.tag) {
        .windows => {
            try windows.run(vtable);
        },
        else => {
            @compileError("Unsupported platform");
        },
    }
}

// ---- objects that the platform will expose to the game ----

/// this is the buffer that the game will draw to
pub const OffscreenBuffer = struct {
    bits: ?*anyopaque = null,
    width: i32,
    height: i32,
    /// bytes per row
    pitch: usize,

    pub fn bytesPerPixel(self: OffscreenBuffer) usize {
        return self.pitch / self.width;
    }
};

/// this is the buffer that the game will use to play sound
pub const SoundBuffer = struct {
    sample_rate: u32,
    samples: [*]i16,
    sample_count: usize,
};

// TODO(ariel): should we make this a generic fn for the struct?
pub const Input = struct {
    pub const KEYBOARD_COUNT = 1;
    pub const GAMEPAD_COUNT = 4;
    /// keyboard is the first controller, the rest are gamepads
    controllers: [KEYBOARD_COUNT + GAMEPAD_COUNT]Controller,

    pub fn getKeyboard(self: *Input) *Controller {
        return &self.controllers[0];
    }

    pub fn getGamepad(self: *Input, index: usize) *Controller {
        assert(index < GAMEPAD_COUNT);
        // TODO(ariel): should we assert here that the gamepad is analog?
        return &self.controllers[index + KEYBOARD_COUNT];
    }

    pub const Controller = struct {
        is_connected: bool = false,
        /// gamepad CAN be digital when using the dpad
        is_analog: bool = false,
        // TODO(ariel): extend to both sticks? (for chanllenge / need)
        stick_average_x: f32 = 0,
        stick_average_y: f32 = 0,

        // TODO(ariel): is it better to have c union here?
        buttons: [@typeInfo(ButtonLabel).@"enum".fields.len]ButtonState,

        pub const ButtonState = struct {
            ended_down: bool = false,
            half_transition_count: u8 = 0,
        };

        pub const ButtonLabel = enum(usize) {
            move_up = 0,
            move_down,
            move_left,
            move_right,

            /// y
            action_up,
            /// a
            action_down,
            /// x
            action_left,
            /// b
            action_right,

            left_shoulder,
            right_shoulder,

            start,
            back,
        };

        pub fn getButton(self: *Controller, label: ButtonLabel) *ButtonState {
            return &self.buttons[@intFromEnum(label)];
        }

        pub fn reset(self: *Controller) void {
            self.* = std.mem.zeroes(Controller);
        }
    };
};

pub const Memory = struct {
    is_initialized: bool = false,
    permanent_storage_size: u64,
    /// required to be cleared to zero at startup
    permanent_storage: *anyopaque,
    transient_storage_size: u64,
    /// required to be cleared to zero at startup
    transient_storage: *anyopaque,
};

/// namespace for debug only functions
/// asserting that handmade_internal is true
pub const debug = struct {
    pub const ReadFileResult = struct {
        contents: ?*anyopaque,
        size: u32,
    };

    pub fn readEntireFile(filename: []const u8) ReadFileResult {
        switch (builtin.os.tag) {
            .windows => {
                return windows.debug.readEntireFile(filename);
            },
            else => {
                @compileError("Unsupported platform");
            },
        }
    }

    // TODO(ariel): should this be public?
    pub fn freeFileMemory(memory: *anyopaque) void {
        switch (builtin.os.tag) {
            .windows => {
                return windows.debug.freeFileMemory(memory);
            },
            else => {
                @compileError("Unsupported platform");
            },
        }
    }

    pub fn writeEntireFile(filename: []const u8, memory: *anyopaque, size: u32) bool {
        switch (builtin.os.tag) {
            .windows => {
                return windows.debug.writeEntireFile(filename, size, memory);
            },
            else => {
                @compileError("Unsupported platform");
            },
        }
    }
};

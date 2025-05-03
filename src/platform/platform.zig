//! A.K.A. the Engine
//!
//! we use, as casey says, a "Game as a Service to the OS" architecture style.
//! this means that here we start the platform code, and each platform will call the game API in certain entry points.
//! The Platform calls the Game, not the other way around.
//!
//! we need main.zig to impleament the Game API

const std = @import("std");
const builtin = @import("builtin");

pub const log = std.log.scoped(.engine);

// platforms, should be private and not exposed directly to the game
const windows = @import("./windows/windows.zig");

// TODO(ariel): hypotetically if this was a library, we would not need to import main.zig here
// maybe build.zig should define a "app" module that will be used here?
const game = @import("../main.zig");

// ---- here lie the function that the platform will call ----
pub const updateAndRender = game.updateAndRender;

// ---- need to be called by the main.zig ----

/// need to be called by the main.zig
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

// ---- objects that the platform will expose to the game ----

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

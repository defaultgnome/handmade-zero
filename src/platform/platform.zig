//! A.K.A. the Engine
const builtin = @import("builtin");

pub const windows = @import("./windows/windows.zig");

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

pub const OffscreenBuffer = struct {
    bits: ?*anyopaque = null,
    width: i32,
    height: i32,
    pitch: usize,
};

pub const SoundBuffer = struct {
    sample_rate: u32,
    samples: [*]i16,
    sample_count: usize,
};

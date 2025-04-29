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

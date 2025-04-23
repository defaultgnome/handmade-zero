const std = @import("std");
const win = @cImport(@cInclude("windows.h"));

pub export fn main(
    inst: std.os.windows.HINSTANCE,
    prev: ?std.os.windows.HINSTANCE,
    cmd_line: std.os.windows.LPWSTR,
    cmd_show: i32,
) callconv(.winapi) i32 {
    _ = inst;
    _ = prev;
    _ = cmd_line;
    _ = cmd_show;

    _ = win.MessageBoxA(
        null,
        "This is Handmade Zero",
        "Handmade Zero",
        win.MB_OK | win.MB_ICONINFORMATION,
    );

    return 0;
}

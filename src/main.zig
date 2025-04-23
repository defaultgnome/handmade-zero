const std = @import("std");
const win = @cImport(@cInclude("windows.h"));

var running = true;

pub export fn main(
    inst: std.os.windows.HINSTANCE,
    prev: ?std.os.windows.HINSTANCE,
    cmd_line: std.os.windows.LPWSTR,
    cmd_show: i32,
) callconv(.winapi) i32 {
    _ = prev;
    _ = cmd_line;
    _ = cmd_show;

    const window_class = win.WNDCLASSA{
        .lpfnWndProc = mainWindowCallback,
        .hInstance = @constCast(@ptrCast(&inst)),
        // .hIcon = ;
        .lpszClassName = "HandmadeZeroWindowClass",
    };

    if (win.RegisterClassA(&window_class) == 0) {
        std.log.info("Failed to register window class", .{});
        // TODO: Handle error the zig way?
        return 1;
    }
    const window = win.CreateWindowExA(
        0,
        window_class.lpszClassName,
        "Handmade Zero",
        win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        null,
        null,
        @constCast(@ptrCast(&inst)),
        null,
    ) orelse {
        std.log.info("Failed to create window", .{});
        // TODO: Handle error the zig way?
        return 1;
    };
    while (running) {
        var msg: win.MSG = undefined;
        if (win.GetMessageA(&msg, window, 0, 0) > 0) {
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageA(&msg);
        } else {
            running = false;
        }
    }
    return 0;
}

var paint_mode = win.WHITENESS;
fn mainWindowCallback(
    window: win.HWND,
    message: win.UINT,
    wparam: win.WPARAM,
    lparam: win.LPARAM,
) callconv(.c) win.LRESULT {
    var result: win.LRESULT = 0;

    switch (message) {
        win.WM_SIZE => {
            std.log.info("WM_SIZE", .{});
        },
        win.WM_DESTROY => {
            std.log.info("WM_DESTROY", .{});
            running = false;
        },
        win.WM_CLOSE => {
            std.log.info("WM_CLOSE", .{});
            running = false;
        },
        win.WM_ACTIVATEAPP => {
            std.log.info("WM_ACTIVATEAPP", .{});
        },
        win.WM_PAINT => {
            var ps: win.PAINTSTRUCT = undefined;
            const device_context = win.BeginPaint(window, &ps);
            const x = ps.rcPaint.left;
            const y = ps.rcPaint.top;
            const width = ps.rcPaint.right - ps.rcPaint.left;
            const height = ps.rcPaint.bottom - ps.rcPaint.top;
            _ = win.PatBlt(device_context, x, y, width, height, paint_mode);
            // just for fun, alternate between white and black
            paint_mode = if (paint_mode == win.WHITENESS) win.BLACKNESS else win.WHITENESS;
            _ = win.EndPaint(window, &ps);
        },
        else => {
            // std.log.info("Unknown message: {}", .{message});
            result = win.DefWindowProcA(window, message, wparam, lparam);
        },
    }
    return result;
}

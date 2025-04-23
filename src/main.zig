const std = @import("std");
const win = @cImport(@cInclude("windows.h"));

var running = true;
var bits: ?*anyopaque = null;
var bitmap_handle: win.HBITMAP = undefined;
var bitmap_device_context: win.HDC = undefined;

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
            var rect: win.RECT = undefined;
            _ = win.GetClientRect(window, &rect);
            const width: i32 = @intCast(rect.right - rect.left);
            const height: i32 = @intCast(rect.bottom - rect.top);
            resizeDIBSection(width, height);
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
            updateWindow(device_context, x, y, width, height);

            _ = win.PatBlt(device_context, x, y, width, height, win.WHITENESS);
            _ = win.EndPaint(window, &ps);
        },
        else => {
            // std.log.info("Unknown message: {}", .{message});
            result = win.DefWindowProcA(window, message, wparam, lparam);
        },
    }
    return result;
}

var bitmap_info = win.BITMAPINFO{
    .bmiHeader = win.BITMAPINFOHEADER{
        .biSize = @sizeOf(win.BITMAPINFOHEADER),
        .biWidth = undefined,
        .biHeight = undefined,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win.BI_RGB,
    },
};

fn resizeDIBSection(width: i32, height: i32) void {
    if (bitmap_handle != null) {
        _ = win.DeleteObject(bitmap_handle);
    }
    if (bitmap_device_context == null) {
        bitmap_device_context = win.CreateCompatibleDC(null);
    }
    bitmap_info.bmiHeader.biWidth = width;
    bitmap_info.bmiHeader.biHeight = height;
    bitmap_handle = win.CreateDIBSection(
        bitmap_device_context,
        &bitmap_info,
        win.DIB_RGB_COLORS,
        &bits,
        null,
        0,
    );
}

fn updateWindow(device_context: win.HDC, x: i32, y: i32, width: i32, height: i32) void {
    _ = win.StretchDIBits(
        device_context,
        x,
        y,
        width,
        height,
        x,
        y,
        width,
        height,
        bits,
        &bitmap_info,
        win.DIB_RGB_COLORS,
        win.SRCCOPY,
    );
}

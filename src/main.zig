const std = @import("std");
const win = @cImport(@cInclude("windows.h"));

var running = true;

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
var bits: ?*anyopaque = null;
var bitmap_width: i32 = 0;
var bitmap_height: i32 = 0;

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

            var rect: win.RECT = undefined;
            _ = win.GetClientRect(window, &rect);
            updateWindow(device_context, &rect, x, y, width, height);
            _ = win.EndPaint(window, &ps);
        },
        else => {
            // std.log.info("Unknown message: {}", .{message});
            result = win.DefWindowProcA(window, message, wparam, lparam);
        },
    }
    return result;
}

fn resizeDIBSection(width: i32, height: i32) void {
    if (bits != null) {
        _ = win.VirtualFree(bits, 0, win.MEM_RELEASE);
    }

    bitmap_width = width;
    bitmap_height = height;

    bitmap_info.bmiHeader.biWidth = bitmap_width;
    bitmap_info.bmiHeader.biHeight = -bitmap_height;

    const bytes_per_pixel = 4;
    const bitsmap_size: c_ulonglong = @intCast(bitmap_width * bitmap_height * bytes_per_pixel);
    bits = win.VirtualAlloc(
        null,
        bitsmap_size,
        win.MEM_COMMIT,
        win.PAGE_READWRITE,
    );

    const h = @as(usize, @intCast(bitmap_height));
    const w = @as(usize, @intCast(bitmap_width));
    const pitch: usize = @intCast(bitmap_width * bytes_per_pixel);
    var row: [*]u8 = @ptrCast(bits);
    for (0..h) |y| {
        var pixel = row;
        for (0..w) |x| {
            // BB GG RR xx
            pixel[0] = @truncate(x);
            pixel[1] = @truncate(y);
            pixel[2] = 0;
            pixel[3] = 0;
            pixel += bytes_per_pixel;
        }
        row += pitch;
    }
}

fn updateWindow(
    device_context: win.HDC,
    rect: *win.RECT,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
) void {
    _ = x;
    _ = y;
    _ = width;
    _ = height;

    const window_width = rect.right - rect.left;
    const window_height = rect.bottom - rect.top;

    // zig fmt: off
    _ = win.StretchDIBits(
        device_context,
        // x, y, width, height,
        // x, y, width, height,
        0, 0, bitmap_width, bitmap_height,
        0, 0, window_width, window_height,
        bits,
        &bitmap_info,
        win.DIB_RGB_COLORS, win.SRCCOPY,
    );
    // zig fmt: on
}

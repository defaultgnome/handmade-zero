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
const bytes_per_pixel = 4;

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
        .style = win.CS_HREDRAW | win.CS_VREDRAW,
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
    var x_offset: u32 = 0;
    const y_offset: u32 = 0;
    while (running) {
        var msg: win.MSG = undefined;
        while (win.PeekMessageA(&msg, window, 0, 0, win.PM_REMOVE) > 0) {
            if (msg.message == win.WM_QUIT) {
                running = false;
            }
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageA(&msg);
        }
        renderWeirdGradient(x_offset, y_offset);
        {
            const device_context = win.GetDC(window);
            defer _ = win.ReleaseDC(window, device_context);
            var client_rect: win.RECT = undefined;
            _ = win.GetClientRect(window, &client_rect);
            const window_width = client_rect.right - client_rect.left;
            const window_height = client_rect.bottom - client_rect.top;
            updateWindow(device_context, client_rect, 0, 0, window_width, window_height);
        }
        x_offset += 1;
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
            var client_rect: win.RECT = undefined;
            _ = win.GetClientRect(window, &client_rect);
            const width: i32 = @intCast(client_rect.right - client_rect.left);
            const height: i32 = @intCast(client_rect.bottom - client_rect.top);
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

            var client_rect: win.RECT = undefined;
            _ = win.GetClientRect(window, &client_rect);
            updateWindow(device_context, client_rect, x, y, width, height);
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

    const bitsmap_size: c_ulonglong = @intCast(bitmap_width * bitmap_height * bytes_per_pixel);
    bits = win.VirtualAlloc(
        null,
        bitsmap_size,
        win.MEM_COMMIT,
        win.PAGE_READWRITE,
    );
}

fn renderWeirdGradient(x_offset: u32, y_offset: u32) void {
    const h = @as(usize, @intCast(bitmap_height));
    const w = @as(usize, @intCast(bitmap_width));
    const pitch: usize = @intCast(bitmap_width * bytes_per_pixel);
    var row: [*]u8 = @ptrCast(bits);
    for (0..h) |y| {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        for (0..w) |x| {
            const blue: u8 = @truncate(@as(u32, @intCast(x)) + x_offset);
            const green: u16 = @truncate(@as(u32, @intCast(y)) + y_offset);
            pixel[0] = (green << 8) | blue;
            pixel += 1;
        }
        row += pitch;
    }
}

fn updateWindow(
    device_context: win.HDC,
    rect: win.RECT,
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

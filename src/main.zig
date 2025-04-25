const std = @import("std");
const win = @cImport(@cInclude("windows.h"));

const OffscreenBuffer = struct {
    info: win.BITMAPINFO,
    bits: ?*anyopaque = null,
    width: i32,
    height: i32,
    pitch: usize,
    bytes_per_pixel: i32,
};

var running = true;
var global_backbuffer: OffscreenBuffer = undefined;

pub export fn main(
    inst: std.os.windows.HINSTANCE,
    prev: ?std.os.windows.HINSTANCE,
    cmd_line: std.os.windows.LPWSTR,
    cmd_show: i32,
) callconv(.winapi) i32 {
    _ = prev;
    _ = cmd_line;
    _ = cmd_show;

    resizeDIBSection(&global_backbuffer, 1280, 720);

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
    var y_offset: u32 = 0;
    while (running) {
        var msg: win.MSG = undefined;
        while (win.PeekMessageA(&msg, window, 0, 0, win.PM_REMOVE) > 0) {
            if (msg.message == win.WM_QUIT) {
                running = false;
            }
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageA(&msg);
        }
        renderWeirdGradient(global_backbuffer, x_offset, y_offset);
        {
            const device_context = win.GetDC(window);
            defer _ = win.ReleaseDC(window, device_context);
            const window_dimensions = getWindowDimensions(window);
            displayBufferInWindow(
                device_context,
                window_dimensions.width,
                window_dimensions.height,
                global_backbuffer,
                0,
                0,
                window_dimensions.width,
                window_dimensions.height,
            );
        }
        x_offset += 1;
        y_offset += 1;
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
        win.WM_SIZE => {},
        win.WM_DESTROY => {
            running = false;
        },
        win.WM_CLOSE => {
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

            const window_dimensions = getWindowDimensions(window);
            displayBufferInWindow(
                device_context,
                window_dimensions.width,
                window_dimensions.height,
                global_backbuffer,
                x,
                y,
                width,
                height,
            );
            _ = win.EndPaint(window, &ps);
        },
        else => {
            result = win.DefWindowProcA(window, message, wparam, lparam);
        },
    }
    return result;
}

fn resizeDIBSection(buffer: *OffscreenBuffer, width: i32, height: i32) void {
    if (buffer.bits != null) {
        _ = win.VirtualFree(buffer.bits, 0, win.MEM_RELEASE);
    }

    buffer.width = width;
    buffer.height = height;
    buffer.bytes_per_pixel = 4;

    buffer.info.bmiHeader.biWidth = buffer.width;
    buffer.info.bmiHeader.biHeight = -buffer.height;
    buffer.info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    buffer.info.bmiHeader.biPlanes = 1;
    buffer.info.bmiHeader.biBitCount = 32;
    buffer.info.bmiHeader.biCompression = win.BI_RGB;

    const bitsmap_size: c_ulonglong = @intCast(buffer.width * buffer.height * buffer.bytes_per_pixel);
    buffer.bits = win.VirtualAlloc(
        null,
        bitsmap_size,
        win.MEM_COMMIT,
        win.PAGE_READWRITE,
    );

    buffer.pitch = @intCast(buffer.width * buffer.bytes_per_pixel);
}

fn renderWeirdGradient(buffer: OffscreenBuffer, x_offset: u32, y_offset: u32) void {
    const h = @as(usize, @intCast(buffer.height));
    const w = @as(usize, @intCast(buffer.width));
    var row: [*]u8 = @ptrCast(buffer.bits);
    for (0..h) |y| {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        for (0..w) |x| {
            const blue: u8 = @truncate(@as(u32, @intCast(x)) + x_offset);
            const green: u16 = @truncate(@as(u32, @intCast(y)) + y_offset);
            pixel[0] = (green << 8) | blue;
            pixel += 1;
        }
        row += buffer.pitch;
    }
}

fn displayBufferInWindow(
    device_context: win.HDC,
    window_width: i32,
    window_height: i32,
    buffer: OffscreenBuffer,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
) void {
    _ = x;
    _ = y;
    _ = width;
    _ = height;

    // zig fmt: off
    _ = win.StretchDIBits(
        device_context,
        // x, y, width, height,
        // x, y, width, height,
        0, 0, window_width, window_height,
        0, 0, buffer.width, buffer.height,
        buffer.bits,
        &buffer.info,
        win.DIB_RGB_COLORS, win.SRCCOPY,
    );
    // zig fmt: on
}

const WindowDimensions = struct {
    width: i32,
    height: i32,
};
fn getWindowDimensions(window: win.HWND) WindowDimensions {
    var rect: win.RECT = undefined;
    _ = win.GetClientRect(window, &rect);
    return WindowDimensions{
        .width = rect.right - rect.left,
        .height = rect.bottom - rect.top,
    };
}

const std = @import("std");
const win = @cImport(@cInclude("windows.h"));
const xinput = @cImport(@cInclude("xinput.h"));

const OffscreenBuffer = struct {
    info: win.BITMAPINFO,
    bits: ?*anyopaque = null,
    width: i32,
    height: i32,
    pitch: usize,
};

const XInputGetStateFn = *const fn (dwUserIndex: xinput.DWORD, pState: *xinput.XINPUT_STATE) callconv(.winapi) xinput.DWORD;
const XInputSetStateFn = *const fn (dwUserIndex: xinput.DWORD, pVibration: *xinput.XINPUT_VIBRATION) callconv(.winapi) xinput.DWORD;

fn XInputSetStateStub(dwUserIndex: xinput.DWORD, pVibration: *xinput.XINPUT_VIBRATION) callconv(.winapi) xinput.DWORD {
    _ = dwUserIndex;
    _ = pVibration;
    return 0;
}

fn XInputGetStateStub(dwUserIndex: xinput.DWORD, pState: *xinput.XINPUT_STATE) callconv(.winapi) xinput.DWORD {
    _ = dwUserIndex;
    _ = pState;
    return 0;
}

var XInputGetState: XInputGetStateFn = XInputGetStateStub;
var XInputSetState: XInputSetStateFn = XInputSetStateStub;

fn loadXInput() void {
    const xinput_library = win.LoadLibraryA("xinput1_3.dll");
    if (xinput_library == null) {
        std.log.info("Failed to load xinput1_3.dll", .{});
        return;
    }
    XInputGetState = @ptrCast(win.GetProcAddress(xinput_library, "XInputGetState"));
    XInputSetState = @ptrCast(win.GetProcAddress(xinput_library, "XInputSetState"));
}

var global_running = true;
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

    loadXInput();

    resizeDIBSection(&global_backbuffer, 1280, 720);

    const window_class = win.WNDCLASSA{
        .style = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_OWNDC,
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
    const device_context = win.GetDC(window);

    var x_offset: u32 = 0;
    var y_offset: u32 = 0;
    while (global_running) {
        var msg: win.MSG = undefined;
        while (win.PeekMessageA(&msg, window, 0, 0, win.PM_REMOVE) > 0) {
            if (msg.message == win.WM_QUIT) {
                global_running = false;
            }
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageA(&msg);
        }

        for (0..xinput.XUSER_MAX_COUNT) |controller_index| {
            var controller_state: xinput.XINPUT_STATE = undefined;
            if (XInputGetState(@intCast(controller_index), &controller_state) == win.ERROR_SUCCESS) {
                // Controller is connected
                const pad: xinput.XINPUT_GAMEPAD = controller_state.Gamepad;
                // const up = (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_UP) != 0;
                // const down = (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_DOWN) != 0;
                // const left = (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_LEFT) != 0;
                // const right = (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_RIGHT) != 0;
                // const start = (pad.wButtons & xinput.XINPUT_GAMEPAD_START) != 0;
                // const back = (pad.wButtons & xinput.XINPUT_GAMEPAD_BACK) != 0;
                // const left_shoulder = (pad.wButtons & xinput.XINPUT_GAMEPAD_LEFT_SHOULDER) != 0;
                // const right_shoulder = (pad.wButtons & xinput.XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0;
                const a_button = (pad.wButtons & xinput.XINPUT_GAMEPAD_A) != 0;
                // const b_button = (pad.wButtons & xinput.XINPUT_GAMEPAD_B) != 0;
                // const x_button = (pad.wButtons & xinput.XINPUT_GAMEPAD_X) != 0;
                // const y_button = (pad.wButtons & xinput.XINPUT_GAMEPAD_Y) != 0;
                // const stick_left_x = pad.sThumbLX;
                // const stick_left_y = pad.sThumbLY;
                if (a_button) {
                    y_offset += 1;
                }
            } else {
                // Controller is not connected
            }
        }

        renderWeirdGradient(&global_backbuffer, x_offset, y_offset);

        {
            const window_dimensions = getWindowDimensions(window);
            displayBufferInWindow(
                &global_backbuffer,
                device_context,
                window_dimensions.width,
                window_dimensions.height,
            );
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
        win.WM_DESTROY => {
            global_running = false;
        },
        win.WM_CLOSE => {
            global_running = false;
        },
        win.WM_ACTIVATEAPP => {
            std.log.info("WM_ACTIVATEAPP", .{});
        },
        win.WM_SYSKEYDOWN, win.WM_SYSKEYUP, win.WM_KEYDOWN, win.WM_KEYUP => {
            const vk_code = wparam;
            const was_down = (lparam & (1 << 30)) != 0;
            const is_down = (lparam & (1 << 31)) == 0;
            if (is_down != was_down) {
                switch (vk_code) {
                    'W' => {},
                    'A' => {},
                    'S' => {},
                    'D' => {},
                    'Q' => {},
                    'E' => {},
                    win.VK_UP => {},
                    win.VK_DOWN => {},
                    win.VK_LEFT => {},
                    win.VK_RIGHT => {},
                    win.VK_SPACE => {},
                    win.VK_ESCAPE => {
                        if (is_down and !was_down) {
                            global_running = false;
                        }
                    },
                    else => {},
                }
            }
        },
        win.WM_PAINT => {
            var ps: win.PAINTSTRUCT = undefined;
            const device_context = win.BeginPaint(window, &ps);
            const window_dimensions = getWindowDimensions(window);
            displayBufferInWindow(
                &global_backbuffer,
                device_context,
                window_dimensions.width,
                window_dimensions.height,
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
    const bytes_per_pixel = 4;

    buffer.info.bmiHeader.biWidth = buffer.width;
    // NOTE: Negative height for top-down DIB
    buffer.info.bmiHeader.biHeight = -buffer.height;
    buffer.info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    buffer.info.bmiHeader.biPlanes = 1;
    buffer.info.bmiHeader.biBitCount = 32;
    buffer.info.bmiHeader.biCompression = win.BI_RGB;

    const bitsmap_size: c_ulonglong = @intCast(buffer.width * buffer.height * bytes_per_pixel);
    buffer.bits = win.VirtualAlloc(
        null,
        bitsmap_size,
        win.MEM_COMMIT,
        win.PAGE_READWRITE,
    );

    buffer.pitch = @intCast(buffer.width * bytes_per_pixel);
}

fn renderWeirdGradient(buffer: *OffscreenBuffer, x_offset: u32, y_offset: u32) void {
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
    buffer: *OffscreenBuffer,
    device_context: win.HDC,
    window_width: i32,
    window_height: i32,
) void {

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

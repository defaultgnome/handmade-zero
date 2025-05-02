//! TODO(ariel): move this to a separate file, per API for windows
const std = @import("std");
const builtin = @import("builtin");

const win = @cImport(@cInclude("windows.h"));
const xinput = @cImport(@cInclude("xinput.h"));
const dsound = @cImport(@cInclude("dsound.h"));

const stdx = @import("stdx");

const game = @import("../../main.zig");
const platform = @import("../platform.zig");

var global_running = false;
var global_backbuffer: OffscreenBuffer = undefined;
var global_secondary_buffer: dsound.LPDIRECTSOUNDBUFFER = undefined;

pub fn run() !void {
    const inst = std.os.windows.kernel32.GetModuleHandleW(null);

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
        // TODO(ariel): Handle error the zig way?
        return error.FailedToRegisterWindowClass;
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
        // TODO(ariel): Handle error the zig way?
        return error.FailedToCreateWindow;
    };

    const device_context = win.GetDC(window);

    // Sound Test
    var sound_output = SoundOutput.init();
    loadDSound(window, sound_output.sample_rate, sound_output.secondary_buffer_size);
    clearSoundBuffer(&sound_output);
    _ = global_secondary_buffer.*.lpVtbl.*.Play.?(global_secondary_buffer, 0, 0, dsound.DSBPLAY_LOOPING);

    global_running = true;

    // TODO(ariel): use std.mem.allocator instead if this make sense
    const samples: [*]i16 = @ptrCast(@alignCast(win.VirtualAlloc(
        null,
        sound_output.secondary_buffer_size,
        win.MEM_RESERVE | win.MEM_COMMIT,
        win.PAGE_READWRITE,
    )));

    // TODO(ariel): why using an array? and not just two variables?
    var input = [2]platform.Input{ undefined, undefined };
    var old_input = &input[0];
    var new_input = &input[1];

    const qpf = std.os.windows.QueryPerformanceFrequency();
    var last_cycles_count = stdx.time.clock_cycles();
    var last_counter = std.os.windows.QueryPerformanceCounter();

    while (global_running) {
        var msg: win.MSG = undefined;

        while (win.PeekMessageA(&msg, window, 0, 0, win.PM_REMOVE) > 0) {
            if (msg.message == win.WM_QUIT) {
                global_running = false;
            }
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageA(&msg);
        }

        const max_controllers: usize = @min(xinput.XUSER_MAX_COUNT, new_input.controllers.len);
        for (0..max_controllers) |controller_index| {
            var old_controller = &old_input.controllers[controller_index];
            var new_controller = &new_input.controllers[controller_index];
            var controller_state: xinput.XINPUT_STATE = undefined;
            if (XInputGetState(@intCast(controller_index), &controller_state) == win.ERROR_SUCCESS) {
                // Controller is connected
                const pad: xinput.XINPUT_GAMEPAD = controller_state.Gamepad;
                // const up = (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_UP) != 0;
                // const down = (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_DOWN) != 0;
                // const left = (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_LEFT) != 0;
                // const right = (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_RIGHT) != 0;

                new_controller.is_analog = true;

                const stick_left_x: f32 = val: {
                    const f: f32 = @floatFromInt(pad.sThumbLX);
                    const div: f32 = if (f < 0) 32_768 else 32_767;
                    break :val f / div;
                };
                new_controller.start_x = old_controller.end_x;
                new_controller.end_x = stick_left_x;
                new_controller.min_x = stick_left_x;
                new_controller.max_x = stick_left_x;

                const stick_left_y: f32 = val: {
                    const f: f32 = @floatFromInt(pad.sThumbLY);
                    const div: f32 = if (f < 0) 32_768 else 32_767;
                    break :val f / div;
                };
                new_controller.start_y = old_controller.end_y;
                new_controller.end_y = stick_left_y;
                new_controller.min_y = stick_left_y;
                new_controller.max_y = stick_left_y;

                // TODO(casey): deadzone processing
                // XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE
                // XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE

                const buttons = [_]struct { xinput.DWORD, platform.Input.Controller.ButtonLabel }{
                    .{ xinput.XINPUT_GAMEPAD_A, .down },
                    .{ xinput.XINPUT_GAMEPAD_B, .right },
                    .{ xinput.XINPUT_GAMEPAD_X, .left },
                    .{ xinput.XINPUT_GAMEPAD_Y, .up },
                    .{ xinput.XINPUT_GAMEPAD_LEFT_SHOULDER, .left_shoulder },
                    .{ xinput.XINPUT_GAMEPAD_RIGHT_SHOULDER, .right_shoulder },
                };
                inline for (buttons) |button| {
                    processXInputDigitalButton(
                        pad.wButtons,
                        old_controller.getButton(button[1]),
                        button[0],
                        new_controller.getButton(button[1]),
                    );
                }
                // const start = (pad.wButtons & xinput.XINPUT_GAMEPAD_START) != 0;
                // const back = (pad.wButtons & xinput.XINPUT_GAMEPAD_BACK) != 0;

                // TODO(ariel): delete this
                // y_offset += @divTrunc(@as(i32, @intCast(stick_left_y)), 4096);
                // x_offset += @divTrunc(@as(i32, @intCast(stick_left_x)), 4096);

                // pentatonic scale
                // if (left_shoulder) {
                //     const stick_tone_offset: i32 = @intFromFloat(256 * @as(f32, @floatFromInt(stick_left_y >> 12)));
                //     sound_output.setTone(@intCast(@max(128, 512 + stick_tone_offset)));
                // } else if (a_button) {
                //     sound_output.setTone(512);
                // } else if (b_button) {
                //     sound_output.setTone(640);
                // } else if (x_button) {
                //     sound_output.setTone(768);
                // } else if (y_button) {
                //     sound_output.setTone(896);
                // }
            } else {
                // Controller is not connected
            }
        }

        {
            var byte_to_lock: win.DWORD = 0;
            var target_cursor: win.DWORD = 0;
            var bytes_to_write: win.DWORD = 0;
            var play_cursor: win.DWORD = 0;
            var write_cursor: win.DWORD = 0;
            var sound_is_valid = false;
            if (dsound.SUCCEEDED(global_secondary_buffer.*.lpVtbl.*.GetCurrentPosition.?(global_secondary_buffer, &play_cursor, &write_cursor))) {
                byte_to_lock = (sound_output.running_sample_index * sound_output.bytes_per_sample) % sound_output.secondary_buffer_size;
                target_cursor = (play_cursor + (sound_output.latency_sample_count * sound_output.bytes_per_sample)) % sound_output.secondary_buffer_size;
                if (byte_to_lock > target_cursor) {
                    bytes_to_write = sound_output.secondary_buffer_size - byte_to_lock;
                    bytes_to_write += target_cursor;
                } else {
                    bytes_to_write = target_cursor - byte_to_lock;
                }

                sound_is_valid = true;
            }
            var sound_buffer: platform.SoundBuffer = .{
                .sample_rate = sound_output.sample_rate,
                .samples = samples,
                .sample_count = bytes_to_write / sound_output.bytes_per_sample,
            };

            var buffer: platform.OffscreenBuffer = .{
                .bits = global_backbuffer.bits,
                .width = global_backbuffer.width,
                .height = global_backbuffer.height,
                .pitch = global_backbuffer.pitch,
            };
            game.updateAndRender(new_input, &buffer, &sound_buffer);

            if (sound_is_valid) {
                fillSoundBuffer(&sound_output, byte_to_lock, bytes_to_write, &sound_buffer);
            }

            {
                const window_dimensions = getWindowDimensions(window);
                displayBufferInWindow(
                    &global_backbuffer,
                    device_context,
                    window_dimensions.width,
                    window_dimensions.height,
                );
            }
        }

        {
            const end_cycles_count = stdx.time.clock_cycles();

            const end_counter = std.os.windows.QueryPerformanceCounter();

            const cycles_elapsed = end_cycles_count - last_cycles_count;
            // TODO(ariel): use `std.time.Instant.since`
            const counter_elapsed = end_counter - last_counter;
            const ms_per_frame: f64 = @as(f64, @floatFromInt(1000 * counter_elapsed)) / @as(f64, @floatFromInt(qpf));
            const fps: f64 = @as(f64, @floatFromInt(qpf)) / @as(f64, @floatFromInt(counter_elapsed));
            const mega_hz = 1_000 * 1_000;
            const mcpf: f64 = @as(f64, @floatFromInt(cycles_elapsed)) / mega_hz;
            platform.log.debug("{d:.2}ms/f, {d:.2}f/s / {d:.2}mc/f", .{ ms_per_frame, fps, mcpf });

            last_cycles_count = end_cycles_count;
            last_counter = end_counter;
        }

        {
            // TODO(ariel): should we defer this block from the top?
            std.mem.swap(platform.Input, new_input, old_input);
        }
    }
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
            const alt_key_was_down = (lparam & (1 << 29)) != 0;
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
                    win.VK_ESCAPE => {},
                    win.VK_F4 => {
                        if (alt_key_was_down) {
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
    // TODO(ariel): use std.mem.allocator instead if this make sense
    buffer.bits = win.VirtualAlloc(
        null,
        bitsmap_size,
        win.MEM_RESERVE | win.MEM_COMMIT,
        win.PAGE_READWRITE,
    );

    buffer.pitch = @intCast(buffer.width * bytes_per_pixel);
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

// === XInput ===
const XInputSetStateFn = *const fn (dwUserIndex: xinput.DWORD, pVibration: *xinput.XINPUT_VIBRATION) callconv(.winapi) xinput.DWORD;
fn XInputSetStateStub(dwUserIndex: xinput.DWORD, pVibration: *xinput.XINPUT_VIBRATION) callconv(.winapi) xinput.DWORD {
    _ = dwUserIndex;
    _ = pVibration;
    return win.ERROR_DEVICE_NOT_CONNECTED;
}
var XInputSetState: XInputSetStateFn = XInputSetStateStub;

const XInputGetStateFn = *const fn (dwUserIndex: xinput.DWORD, pState: *xinput.XINPUT_STATE) callconv(.winapi) xinput.DWORD;
fn XInputGetStateStub(dwUserIndex: xinput.DWORD, pState: *xinput.XINPUT_STATE) callconv(.winapi) xinput.DWORD {
    _ = dwUserIndex;
    _ = pState;
    return win.ERROR_DEVICE_NOT_CONNECTED;
}
var XInputGetState: XInputGetStateFn = XInputGetStateStub;

fn loadXInput() void {
    // TODO(ariel): try using std.DynLib instead of winapi
    // TODO(ariel): try to create a wrapper for loadLibraryA that will try to load the dll in the order of the array,
    // and return the first one that is found. else will throw, the zig way. (rn the caller will just catch and ignore)
    const versions = [_][*c]const u8{ "xinput1_4.dll", "xinput9_1_0.dll", "xinput1_3.dll" };
    var xinput_library: win.HMODULE = undefined;
    inline for (versions) |version| {
        xinput_library = win.LoadLibraryA(version);
        if (xinput_library != null) {
            break;
        }
    }
    if (xinput_library == null) {
        std.log.info("Failed to load xinput.dll", .{});
        return;
    }
    XInputGetState = @ptrCast(win.GetProcAddress(xinput_library, "XInputGetState"));
    XInputSetState = @ptrCast(win.GetProcAddress(xinput_library, "XInputSetState"));
}

// === DirectSound ===
const DirectSoundCreateFn = *const fn (
    lpGuid: *const win.GUID,
    lplpDS: *?*dsound.IDirectSound,
    pUnkOuter: ?*anyopaque,
) callconv(.winapi) win.HRESULT;

fn loadDSound(window: win.HWND, sample_per_second: u32, buffer_size: u32) void {
    const dsound_lib = win.LoadLibraryA("dsound.dll");
    if (dsound_lib == null) {
        std.log.info("Failed to load dsound.dll", .{});
        return;
    }
    const DirectSoundCreate: ?DirectSoundCreateFn = @ptrCast(win.GetProcAddress(dsound_lib, "DirectSoundCreate"));
    if (DirectSoundCreate != null) {
        var direct_sound: dsound.LPDIRECTSOUND = undefined;
        if (dsound.SUCCEEDED(DirectSoundCreate.?(&win.GUID_NULL, &direct_sound, null))) {
            var wave_format: dsound.WAVEFORMATEX = std.mem.zeroes(dsound.WAVEFORMATEX);
            wave_format.wFormatTag = dsound.WAVE_FORMAT_PCM;
            wave_format.nChannels = 2;
            wave_format.nSamplesPerSec = sample_per_second;
            wave_format.wBitsPerSample = 16;
            wave_format.nBlockAlign = (wave_format.nChannels * wave_format.wBitsPerSample) / 8;
            wave_format.nAvgBytesPerSec = wave_format.nSamplesPerSec * wave_format.nBlockAlign;
            wave_format.cbSize = 0;

            if (dsound.SUCCEEDED(direct_sound.*.lpVtbl.*.SetCooperativeLevel.?(direct_sound, @ptrCast(window), dsound.DSSCL_PRIORITY))) {
                var buffer_desc: dsound.DSBUFFERDESC = std.mem.zeroes(dsound.DSBUFFERDESC);
                buffer_desc.dwSize = @sizeOf(dsound.DSBUFFERDESC);
                buffer_desc.dwFlags = dsound.DSBCAPS_PRIMARYBUFFER;
                var primary_buffer: dsound.LPDIRECTSOUNDBUFFER = undefined;
                if (dsound.SUCCEEDED(direct_sound.*.lpVtbl.*.CreateSoundBuffer.?(direct_sound, &buffer_desc, &primary_buffer, null))) {
                    if (dsound.SUCCEEDED(primary_buffer.*.lpVtbl.*.SetFormat.?(primary_buffer, &wave_format))) {
                        std.log.info("Primary buffer format set", .{});
                    } else {
                        std.log.info("Failed to set primary buffer format", .{});
                    }
                } else {
                    std.log.info("Failed to create primary buffer", .{});
                }
            } else {
                std.log.info("Failed to set cooperative level", .{});
            }

            var buffer_desc: dsound.DSBUFFERDESC = std.mem.zeroes(dsound.DSBUFFERDESC);
            buffer_desc.dwSize = @sizeOf(dsound.DSBUFFERDESC);
            buffer_desc.dwFlags = 0;
            buffer_desc.dwBufferBytes = buffer_size;
            buffer_desc.lpwfxFormat = &wave_format;
            if (dsound.SUCCEEDED(direct_sound.*.lpVtbl.*.CreateSoundBuffer.?(direct_sound, &buffer_desc, &global_secondary_buffer, null))) {
                std.log.info("Secondary buffer created", .{});
            } else {
                std.log.info("Failed to create secondary buffer", .{});
            }
        } else {
            std.log.info("DirectSoundCreate failed", .{});
        }
    }
}

const OffscreenBuffer = struct {
    info: win.BITMAPINFO,
    bits: ?*anyopaque = null,
    width: i32,
    height: i32,
    pitch: usize,
};

const SoundOutput = struct {
    const Self = @This();

    sample_rate: u32,
    running_sample_index: u32,
    bytes_per_sample: u32,
    secondary_buffer_size: u32,
    latency_sample_count: u32,

    pub fn init() Self {
        var self = Self{
            .sample_rate = 48_000,
            .running_sample_index = 0,
            .bytes_per_sample = @sizeOf(u16) * 2,
            .secondary_buffer_size = undefined,
            .latency_sample_count = undefined,
        };
        self.secondary_buffer_size = self.sample_rate * self.bytes_per_sample;
        self.latency_sample_count = self.sample_rate / 15;
        return self;
    }
};

fn fillSoundBuffer(sound_output: *SoundOutput, byte_to_lock: win.DWORD, bytes_to_write: win.DWORD, source_buffer: *platform.SoundBuffer) void {
    var region1: win.LPVOID = undefined;
    var region2: win.LPVOID = undefined;
    var region1_size: win.DWORD = undefined;
    var region2_size: win.DWORD = undefined;

    if (dsound.SUCCEEDED(global_secondary_buffer.*.lpVtbl.*.Lock.?(
        global_secondary_buffer,
        byte_to_lock,
        bytes_to_write,
        &region1,
        &region1_size,
        &region2,
        &region2_size,
        0,
    ))) {
        var dest_sample: [*]i16 = @ptrCast(@alignCast(region1));
        var source_sample: [*]i16 = source_buffer.samples;
        const region1_sample_count = region1_size / sound_output.bytes_per_sample;
        for (0..region1_sample_count) |_| {
            dest_sample[0] = source_sample[0];
            dest_sample[1] = source_sample[1];
            dest_sample += 2;
            source_sample += 2;
            sound_output.running_sample_index += 1;
        }

        if (region2 != null) {
            dest_sample = @ptrCast(@alignCast(region2));
            const region2_sample_count = region2_size / sound_output.bytes_per_sample;
            for (0..region2_sample_count) |_| {
                dest_sample[0] = source_sample[0];
                dest_sample[1] = source_sample[1];
                dest_sample += 2;
                source_sample += 2;
                sound_output.running_sample_index += 1;
            }
        }

        _ = global_secondary_buffer.*.lpVtbl.*.Unlock.?(global_secondary_buffer, region1, region1_size, region2, region2_size);
    }
}

fn clearSoundBuffer(sound_output: *SoundOutput) void {
    var region1: win.LPVOID = undefined;
    var region2: win.LPVOID = undefined;
    var region1_size: win.DWORD = undefined;
    var region2_size: win.DWORD = undefined;

    if (dsound.SUCCEEDED(global_secondary_buffer.*.lpVtbl.*.Lock.?(
        global_secondary_buffer,
        0,
        sound_output.secondary_buffer_size,
        &region1,
        &region1_size,
        &region2,
        &region2_size,
        0,
    ))) {
        var dest_sample: [*]u8 = @ptrCast(@alignCast(region1));
        for (0..region1_size) |_| {
            dest_sample[0] = 0;
            dest_sample += 1;
        }
        if (region2 != null) {
            dest_sample = @ptrCast(@alignCast(region2));
            for (0..region2_size) |_| {
                dest_sample[0] = 0;
                dest_sample += 1;
            }
        }
        _ = global_secondary_buffer.*.lpVtbl.*.Unlock.?(global_secondary_buffer, region1, region1_size, region2, region2_size);
    }
}

// === Input ===

fn processXInputDigitalButton(
    x_input_button_state: xinput.DWORD,
    old_state: *platform.Input.Controller.ButtonState,
    button_bit: xinput.DWORD,
    new_state: *platform.Input.Controller.ButtonState,
) void {
    new_state.ended_down = (x_input_button_state & button_bit) == button_bit;
    new_state.half_transition_count = if (old_state.ended_down != new_state.ended_down) 1 else 0;
}

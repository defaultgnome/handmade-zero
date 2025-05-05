//! TODO(ariel): move this to a separate file, per API for windows
const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");

const win = @cImport(@cInclude("windows.h"));
const xinput = @cImport(@cInclude("xinput.h"));
const dsound = @cImport(@cInclude("dsound.h"));

const stdx = @import("stdx");

const internal = @import("../../internal.zig");
const engine = @import("../../engine.zig");

const assert = std.debug.assert;

var global_running = false;
var global_backbuffer: OffscreenBuffer = undefined;
var global_secondary_buffer: dsound.LPDIRECTSOUNDBUFFER = undefined;

pub fn run(vtable: engine.GameVTable) !void {
    const inst = std.os.windows.kernel32.GetModuleHandleW(null);

    // NOTE: set windows granularity to 1ms, so sleep can be as accurate as possible
    const sleep_is_granular = (win.timeBeginPeriod(1) == win.TIMERR_NOERROR);
    if (!sleep_is_granular) {
        internal.log.warn("Failed to set windows granularity to 1ms", .{});
    }

    loadXInput();

    resizeDIBSection(&global_backbuffer, 1280, 720);

    const window_class = win.WNDCLASSA{
        .style = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_OWNDC,
        .lpfnWndProc = mainWindowCallback,
        .hInstance = @constCast(@ptrCast(&inst)),
        // .hIcon = ;
        .lpszClassName = "HandmadeZeroWindowClass",
    };

    // TODO(casey): get monitor refresh rate from windows
    const monitor_refresh_rate = 60;
    const game_update_rate: comptime_float = monitor_refresh_rate / 2;
    const target_frame_time_ms = 1000.0 / game_update_rate;

    if (win.RegisterClassA(&window_class) == 0) {
        internal.log.err("Failed to register window class", .{});
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
        internal.log.err("Failed to create window", .{});
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
    ) orelse unreachable));

    const base_adderss: win.LPVOID = val: {
        if (options.handmade_internal) {
            break :val @ptrFromInt(stdx.mem.bytes_per_terabyte * 2);
        } else {
            break :val null;
        }
    };

    var memory = engine.Memory{
        .permanent_storage_size = stdx.mem.bytes_per_megabyte * 64,
        .permanent_storage = undefined,
        .transient_storage_size = stdx.mem.bytes_per_gigabyte * 4,
        .transient_storage = undefined,
    };
    const total_memory_size = memory.permanent_storage_size + memory.transient_storage_size;
    memory.permanent_storage = win.VirtualAlloc(
        base_adderss,
        total_memory_size,
        win.MEM_RESERVE | win.MEM_COMMIT,
        win.PAGE_READWRITE,
    ) orelse unreachable;

    memory.transient_storage = @ptrFromInt(@intFromPtr(memory.permanent_storage) + memory.permanent_storage_size);

    // TODO(ariel): why using an array? and not just two variables?
    var input = [2]engine.Input{ undefined, undefined };
    var old_input = &input[0];
    var new_input = &input[1];

    var cycles_count_start = stdx.time.CPUClock.cycles();
    var instant_start = std.time.Instant.now() catch unreachable;

    while (global_running) {
        const old_keyboard_controller = old_input.getKeyboard();
        var new_keyboard_controller = new_input.getKeyboard();
        new_keyboard_controller.reset();
        new_keyboard_controller.is_connected = true;
        // TODO(ariel): should we move this fn to Input.Controller?
        for (&new_keyboard_controller.buttons, 0..) |*button, i| {
            button.ended_down = old_keyboard_controller.buttons[i].ended_down;
        }

        processPendingMessages(window, new_keyboard_controller);

        const max_controllers: usize = @min(xinput.XUSER_MAX_COUNT, engine.Input.GAMEPAD_COUNT);
        for (0..max_controllers) |controller_index| {
            var old_controller = old_input.getGamepad(controller_index);
            var new_controller = new_input.getGamepad(controller_index);
            var controller_state: xinput.XINPUT_STATE = undefined;
            if (XInputGetState(@intCast(controller_index), &controller_state) == win.ERROR_SUCCESS) {
                new_controller.is_connected = true;
                const pad: xinput.XINPUT_GAMEPAD = controller_state.Gamepad;

                new_controller.stick_average_x = processXInputStickValue(pad.sThumbLX, .left);
                new_controller.stick_average_y = processXInputStickValue(pad.sThumbLY, .left);

                if (new_controller.stick_average_x != 0 or new_controller.stick_average_y != 0) {
                    new_controller.is_analog = true;
                }

                if (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_UP != 0) {
                    new_controller.stick_average_y = 1;
                    new_controller.is_analog = false;
                } else if (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_DOWN != 0) {
                    new_controller.stick_average_y = -1;
                    new_controller.is_analog = false;
                }

                if (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_LEFT != 0) {
                    new_controller.stick_average_x = -1;
                    new_controller.is_analog = false;
                } else if (pad.wButtons & xinput.XINPUT_GAMEPAD_DPAD_RIGHT != 0) {
                    new_controller.stick_average_x = 1;
                    new_controller.is_analog = false;
                }

                const buttons = [_]struct { xinput.DWORD, engine.Input.Controller.ButtonLabel }{
                    .{ xinput.XINPUT_GAMEPAD_A, .action_down },
                    .{ xinput.XINPUT_GAMEPAD_B, .action_right },
                    .{ xinput.XINPUT_GAMEPAD_X, .action_left },
                    .{ xinput.XINPUT_GAMEPAD_Y, .action_up },
                    .{ xinput.XINPUT_GAMEPAD_LEFT_SHOULDER, .left_shoulder },
                    .{ xinput.XINPUT_GAMEPAD_RIGHT_SHOULDER, .right_shoulder },
                    .{ xinput.XINPUT_GAMEPAD_START, .start },
                    .{ xinput.XINPUT_GAMEPAD_BACK, .back },
                };
                inline for (buttons) |button| {
                    processXInputDigitalButton(
                        pad.wButtons,
                        old_controller.getButton(button[1]),
                        button[0],
                        new_controller.getButton(button[1]),
                    );
                }

                const threshold = 0.5;
                processXInputDigitalButton(
                    @intFromBool(new_controller.stick_average_x < -threshold),
                    old_controller.getButton(.move_left),
                    1,
                    new_controller.getButton(.move_left),
                );
                processXInputDigitalButton(
                    @intFromBool(new_controller.stick_average_x > threshold),
                    old_controller.getButton(.move_right),
                    1,
                    new_controller.getButton(.move_right),
                );
                processXInputDigitalButton(
                    @intFromBool(new_controller.stick_average_y < -threshold),
                    old_controller.getButton(.move_down),
                    1,
                    new_controller.getButton(.move_down),
                );
                processXInputDigitalButton(
                    @intFromBool(new_controller.stick_average_y > threshold),
                    old_controller.getButton(.move_up),
                    1,
                    new_controller.getButton(.move_up),
                );
            } else {
                // Because we swap the old and new input, we need to set the is_connected to false
                // it could be that the controller was connected before, but now it's not.
                new_controller.is_connected = false;
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
            var sound_buffer: engine.SoundBuffer = .{
                .sample_rate = sound_output.sample_rate,
                .samples = samples,
                .sample_count = bytes_to_write / sound_output.bytes_per_sample,
            };

            var buffer: engine.OffscreenBuffer = .{
                .bits = global_backbuffer.bits,
                .width = global_backbuffer.width,
                .height = global_backbuffer.height,
                .pitch = global_backbuffer.pitch,
            };
            vtable.update(&memory, new_input, &buffer, &sound_buffer);

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
            const cycles_count_end = stdx.time.CPUClock.cycles();
            const instant_end = std.time.Instant.now() catch unreachable;

            const cycles_count_elapsed = cycles_count_end.since(cycles_count_start);
            const instant_elapsed_ns = instant_end.since(instant_start);
            var instant_elapsed_ms: f32 = @as(f32, @floatFromInt(instant_elapsed_ns)) / std.time.ns_per_ms;
            if (instant_elapsed_ms < target_frame_time_ms) {
                if (sleep_is_granular) {
                    const time_to_sleep = @as(u64, @intFromFloat(target_frame_time_ms * std.time.ns_per_ms)) - instant_elapsed_ns;
                    if (time_to_sleep > 0) {
                        std.Thread.sleep(time_to_sleep);
                    }
                }
                while (instant_elapsed_ms < target_frame_time_ms) {
                    const now = std.time.Instant.now() catch unreachable;
                    instant_elapsed_ms = @as(f32, @floatFromInt(now.since(instant_start))) / std.time.ns_per_ms;
                }
            } else {
                // TODO(casey): handle missed frame rate
                internal.log.warn("Missed Frame Rate! took {d:.2}ms (+{d:.2}ms) to complete", .{ instant_elapsed_ms, instant_elapsed_ms - target_frame_time_ms });
            }

            // TODO(ariel): remove this / or use less spammy log
            if (false) {
                const fps: f32 = 1000.0 / instant_elapsed_ms;
                const mega_hz = 1_000 * 1_000;
                const mcpf: f64 = @as(f64, @floatFromInt(cycles_count_elapsed)) / mega_hz;
                internal.log.debug("{d:.2}ms/f, {d:.2}f/s / {d:.2}mc/f", .{ instant_elapsed_ms, fps, mcpf });
            }
            cycles_count_start = cycles_count_end;
            instant_start = instant_end;
        }

        {
            // TODO(ariel): should we defer this block from the top?
            std.mem.swap(engine.Input, new_input, old_input);
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
            internal.log.debug("WM_ACTIVATEAPP", .{});
        },
        win.WM_SYSKEYDOWN, win.WM_SYSKEYUP, win.WM_KEYDOWN, win.WM_KEYUP => {
            @panic("keyboard event came in through a non dispatch message");
            // const vk_code = wparam;
            // const was_down = (lparam & (1 << 30)) != 0;
            // const is_down = (lparam & (1 << 31)) == 0;
            // const alt_key_was_down = (lparam & (1 << 29)) != 0;
            // if (is_down != was_down) {
            //     switch (vk_code) {
            //         'W' => {},
            //         'A' => {},
            //         'S' => {},
            //         'D' => {},
            //         'Q' => {},
            //         'E' => {},
            //         win.VK_UP => {},
            //         win.VK_DOWN => {},
            //         win.VK_LEFT => {},
            //         win.VK_RIGHT => {},
            //         win.VK_SPACE => {},
            //         win.VK_ESCAPE => {},
            //         win.VK_F4 => {
            //             if (alt_key_was_down) {
            //                 global_running = false;
            //             }
            //         },
            //         else => {},
            //     }
            // }
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
        internal.log.err("Failed to load xinput.dll", .{});
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
        internal.log.err("Failed to load dsound.dll", .{});
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
                        internal.log.debug("Primary buffer format set", .{});
                    } else {
                        internal.log.err("Failed to set primary buffer format", .{});
                    }
                } else {
                    internal.log.err("Failed to create primary buffer", .{});
                }
            } else {
                internal.log.err("Failed to set cooperative level", .{});
            }

            var buffer_desc: dsound.DSBUFFERDESC = std.mem.zeroes(dsound.DSBUFFERDESC);
            buffer_desc.dwSize = @sizeOf(dsound.DSBUFFERDESC);
            buffer_desc.dwFlags = 0;
            buffer_desc.dwBufferBytes = buffer_size;
            buffer_desc.lpwfxFormat = &wave_format;
            if (dsound.SUCCEEDED(direct_sound.*.lpVtbl.*.CreateSoundBuffer.?(direct_sound, &buffer_desc, &global_secondary_buffer, null))) {
                internal.log.debug("Secondary buffer created", .{});
            } else {
                internal.log.err("Failed to create secondary buffer", .{});
            }
        } else {
            internal.log.err("DirectSoundCreate failed", .{});
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

fn fillSoundBuffer(sound_output: *SoundOutput, byte_to_lock: win.DWORD, bytes_to_write: win.DWORD, source_buffer: *engine.SoundBuffer) void {
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
    old_state: *engine.Input.Controller.ButtonState,
    button_bit: xinput.DWORD,
    new_state: *engine.Input.Controller.ButtonState,
) void {
    new_state.ended_down = (x_input_button_state & button_bit) == button_bit;
    new_state.half_transition_count = if (old_state.ended_down != new_state.ended_down) 1 else 0;
}

fn processKeyboardMessage(
    new_state: *engine.Input.Controller.ButtonState,
    is_down: bool,
) void {
    assert(new_state.ended_down != is_down);
    new_state.ended_down = is_down;
    new_state.half_transition_count += 1;
}

const StickPlacement = enum {
    left,
    right,

    fn deadzone(self: @This()) c_int {
        return switch (self) {
            .left => xinput.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE,
            .right => xinput.XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE,
        };
    }
};
fn processXInputStickValue(stick_value: xinput.SHORT, placement: StickPlacement) f32 {
    var result: f32 = 0;
    const deadzone = placement.deadzone();
    const deadzone_f32: f32 = @floatFromInt(deadzone);
    if (stick_value < -deadzone) {
        result = @as(f32, @floatFromInt(stick_value + deadzone)) / (32_768 - deadzone_f32);
    } else if (stick_value > deadzone) {
        result = @as(f32, @floatFromInt(stick_value - deadzone)) / (32_768 - deadzone_f32);
    }
    return result;
}

fn processPendingMessages(window: win.HWND, keyboard_controller: *engine.Input.Controller) void {
    var msg: win.MSG = undefined;
    while (win.PeekMessageA(&msg, window, 0, 0, win.PM_REMOVE) > 0) {
        switch (msg.message) {
            win.WM_QUIT => {
                global_running = false;
            },
            win.WM_SYSKEYDOWN, win.WM_SYSKEYUP, win.WM_KEYDOWN, win.WM_KEYUP => {
                const vk_code = msg.wParam;
                const was_down = (msg.lParam & (1 << 30)) != 0;
                const is_down = (msg.lParam & (1 << 31)) == 0;
                const alt_key_was_down = (msg.lParam & (1 << 29)) != 0;
                if (is_down != was_down) {
                    switch (vk_code) {
                        'W' => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.move_up),
                                is_down,
                            );
                        },
                        'A' => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.move_left),
                                is_down,
                            );
                        },
                        'S' => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.move_down),
                                is_down,
                            );
                        },
                        'D' => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.move_right),
                                is_down,
                            );
                        },
                        'Q' => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.left_shoulder),
                                is_down,
                            );
                        },
                        'E' => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.right_shoulder),
                                is_down,
                            );
                        },
                        win.VK_UP => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.action_up),
                                is_down,
                            );
                        },
                        win.VK_DOWN => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.action_down),
                                is_down,
                            );
                        },
                        win.VK_LEFT => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.action_left),
                                is_down,
                            );
                        },
                        win.VK_RIGHT => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.action_right),
                                is_down,
                            );
                        },
                        win.VK_SPACE => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.back),
                                is_down,
                            );
                        },
                        win.VK_ESCAPE => {
                            processKeyboardMessage(
                                keyboard_controller.getButton(.start),
                                is_down,
                            );
                        },
                        win.VK_F4 => {
                            if (alt_key_was_down) {
                                global_running = false;
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {
                _ = win.TranslateMessage(&msg);
                _ = win.DispatchMessageA(&msg);
            },
        }
    }
}

/// namespace for debug only functions
/// asserting that handmade_internal is true
pub const debug = struct {
    pub fn readEntireFile(filename: []const u8) engine.debug.ReadFileResult {
        assert(options.handmade_internal);

        var result = engine.debug.ReadFileResult{
            .contents = null,
            .size = 0,
        };

        const file_handle = win.CreateFileA(
            filename.ptr,
            win.GENERIC_READ,
            win.FILE_SHARE_READ,
            null,
            win.OPEN_EXISTING,
            0,
            null,
        );

        if (file_handle != win.INVALID_HANDLE_VALUE) {
            var file_size: win.LARGE_INTEGER = undefined;
            if (win.GetFileSizeEx(file_handle, &file_size) != 0) {
                if (file_size.QuadPart > 0) {
                    const file_size_u32: u32 = @intCast(file_size.QuadPart);
                    result.contents = win.VirtualAlloc(
                        null,
                        file_size_u32,
                        win.MEM_RESERVE | win.MEM_COMMIT,
                        win.PAGE_READWRITE,
                    );
                    if (result.contents != null) {
                        var bytes_read: win.DWORD = undefined;
                        if (win.ReadFile(
                            file_handle,
                            result.contents,
                            file_size_u32,
                            &bytes_read,
                            null,
                        ) != 0 and bytes_read == file_size_u32) {
                            // NOTE: file is read successfully
                            result.size = file_size_u32;
                        } else {
                            if (result.contents != null) {
                                freeFileMemory(result.contents.?);
                                result.contents = null;
                            }
                        }
                    } else {
                        internal.log.err("Failed to read file: {s}", .{filename});
                    }
                } else {
                    internal.log.err("File is empty: {s}", .{filename});
                }
            } else {
                internal.log.err("Failed to get file size: {s}", .{filename});
            }
            _ = win.CloseHandle(file_handle);
        } else {
            internal.log.err("Failed to open file: {s}", .{filename});
        }

        return result;
    }

    // TODO(ariel): use zig error instead of bool
    pub fn writeEntireFile(filename: []const u8, memory_size: u32, memory: *anyopaque) bool {
        assert(options.handmade_internal);

        var result = false;

        const file_handle = win.CreateFileA(
            filename.ptr,
            win.GENERIC_WRITE,
            0,
            null,
            win.CREATE_ALWAYS,
            0,
            null,
        );

        if (file_handle != win.INVALID_HANDLE_VALUE) {
            var bytes_written: win.DWORD = undefined;
            if (win.WriteFile(
                file_handle,
                memory,
                memory_size,
                &bytes_written,
                null,
            ) != 0) {
                // NOTE: file is written successfully
                result = bytes_written == memory_size;
            } else {
                internal.log.err("Failed to write file: {s}", .{filename});
            }

            _ = win.CloseHandle(file_handle);
        } else {
            internal.log.err("Failed to open file: {s}", .{filename});
        }

        return result;
    }

    pub fn freeFileMemory(bitmap_memory: *anyopaque) void {
        assert(options.handmade_internal);
        _ = win.VirtualFree(bitmap_memory, 0, win.MEM_RELEASE);
    }
};

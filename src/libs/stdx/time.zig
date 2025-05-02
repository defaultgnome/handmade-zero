const std = @import("std");
const builtin = @import("builtin");
/// use the `rdtsc` instruction to get the number of clock cycles since the last reset
///
/// source: https://github.com/ziglang/zig/issues/22705#issuecomment-2661759383
pub fn clock_cycles() u64 {
    switch (builtin.target.cpu.arch) {
        // tested with qemu-i386: works
        .x86,
        // tested with my own system: works
        .x86_64,
        => {
            var lower: u32 = undefined;
            var higher: u32 = undefined;
            lower = asm volatile ("rdtsc"
                : [lower] "={eax}" (-> u32),
                :
                : "edx", "eax"
            );
            higher = asm volatile ("movl %%edx, %[higher]"
                : [higher] "=r" (-> u32),
                :
                : "edx"
            );
            return (@as(u64, higher) << 32) | (@as(u64, lower));
        },

        // tested with qemu-riscv32: works
        .riscv32,
        // tested with qemu-riscv64: works
        .riscv64,
        => if (!comptime std.Target.riscv.featureSetHas(builtin.target.cpu.features, .zicntr)) {
            return asm volatile ("rdcycle a0"
                : [a0] "={a0}" (-> usize),
                :
                : "a0"
            );
        },

        // tested with qemu-ppc: works
        .powerpc,
        // untested
        .powerpcle,
        // tested with qemu-ppc64: works
        .powerpc64,
        // tested with qemu-ppc64le: works
        .powerpc64le,
        => {
            const lower = asm volatile ("mfspr 0, 0x10C"
                : [lower] "={r0}" (-> u32),
                :
                : "r0"
            );
            const upper = asm volatile ("mfspr 3, 0x10D"
                : [upper] "={r3}" (-> u32),
                :
                : "r3"
            );
            return (@as(u64, upper) << 32) | (@as(u64, lower));
        },

        // + tested on an M4 mac: works
        // - tested with qemu-aarch64: fails with illegal instruction.
        // - I suspect this to be an issue with QEMU because the instruction has the "_el0" suffix
        // - which means the system register should be readable from user space.
        // - Or perhaps this counter needs to be enabled first?
        .aarch64,
        // untested
        .aarch64_be,
        => {
            return asm volatile ("mrs x0, cntpct_el0"
                : [x0] "={x0}" (-> u64),
                :
                : "x0"
            );
        },

        else => {},
    }
    @compileError("unsupported");
}

const core = @import("../core.zig");
const State = core.State;

pub const assembly = @embedFile("../x86_64/avx.s");

pub inline fn encrypt(data: State, keys: State) State {
    return asm (
        \\ vaesenc %[k], %[in], %[out]
        : [out] "=x" (-> State),
        : [in] "x" (data),
          [k] "x" (keys),
    );
}

pub inline fn encryptLast(data: State, keys: State) State {
    return asm (
        \\ vaesenclast %[k], %[in], %[out]
        : [out] "=x" (-> State),
        : [in] "x" (data),
          [k] "x" (keys),
    );
}

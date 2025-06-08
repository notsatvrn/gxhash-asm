const core = @import("../core.zig");
const i8x16 = core.i8x16;

pub const assembly = @embedFile("../x86_64/avx.s");

pub inline fn encrypt(data: i8x16, keys: i8x16) i8x16 {
    return asm (
        \\ vaesenc %[k], %[in], %[out]
        : [out] "=x" (-> i8x16),
        : [in] "x" (data),
          [k] "x" (keys),
    );
}

pub inline fn encryptLast(data: i8x16, keys: i8x16) i8x16 {
    return asm (
        \\ vaesenclast %[k], %[in], %[out]
        : [out] "=x" (-> i8x16),
        : [in] "x" (data),
          [k] "x" (keys),
    );
}

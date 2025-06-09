const core = @import("../core.zig");
const i8x16 = core.i8x16;

pub inline fn encrypt(data: i8x16, keys: i8x16) i8x16 {
    return (asm (
        \\ mov   %[out].16b, %[in].16b
        \\ aese  %[out].16b, %[zero].16b
        \\ aesmc %[out].16b, %[out].16b
        : [out] "=&x" (-> i8x16),
        : [in] "x" (data),
          [zero] "x" (core.empty),
    )) ^ keys;
}

pub inline fn encryptLast(data: i8x16, keys: i8x16) i8x16 {
    return (asm (
        \\ mov   %[out].16b, %[in].16b
        \\ aese  %[out].16b, %[zero].16b
        : [out] "=&x" (-> i8x16),
        : [in] "x" (data),
          [zero] "x" (core.empty),
    )) ^ keys;
}

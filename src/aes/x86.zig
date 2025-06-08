const core = @import("../core.zig");
const i8x16 = core.i8x16;

pub const assembly = @embedFile("../x86_64/sse.s");

pub inline fn encrypt(data: i8x16, keys: i8x16) i8x16 {
    var out = data;
    asm (
        \\ aesenc %[k], %[out]
        : [out] "+x" (out),
        : [k] "x" (keys),
    );
    return out;
}

pub inline fn encryptLast(data: i8x16, keys: i8x16) i8x16 {
    var out = data;
    asm (
        \\ aesenclast %[k], %[out]
        : [out] "+x" (out),
        : [k] "x" (keys),
    );
    return out;
}

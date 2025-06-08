// Extracted from the standard library software AES implementation and optimized.
// !!! VERY SLOW !!!
// If you don't need stable hashes, consider using a different hashing algo on platforms other than x86 and ARM.

const std = @import("std");

const core = @import("../core.zig");
const i8x16 = core.i8x16;
const u8x16 = core.u8x16;
const u32x4 = core.u32x4;

const software = true;

pub inline fn encrypt(data: i8x16, keys: i8x16) i8x16 {
    @prefetch(&table, .{});

    const bytes: u8x16 = @bitCast(data);

    const t0 = table[0];
    const t1 = table[1];
    const t2 = table[2];
    const t3 = table[3];

    const s0: i8x16 = @bitCast(u32x4{ t0[bytes[0]], t0[bytes[4]], t0[bytes[8]], t0[bytes[12]] });
    const s1: i8x16 = @bitCast(u32x4{ t1[bytes[5]], t1[bytes[9]], t1[bytes[13]], t1[bytes[1]] });
    const s2: i8x16 = @bitCast(u32x4{ t2[bytes[10]], t2[bytes[14]], t2[bytes[2]], t2[bytes[6]] });
    const s3: i8x16 = @bitCast(u32x4{ t3[bytes[15]], t3[bytes[3]], t3[bytes[7]], t3[bytes[11]] });

    return (s0 ^ s1 ^ s2 ^ s3) ^ keys;
}

pub inline fn encryptLast(data: i8x16, keys: i8x16) i8x16 {
    @prefetch(&sbox, .{});

    const bytes: u8x16 = @bitCast(data);

    // Last round uses s-box directly and XORs to produce output.
    const out = u8x16{
        sbox[bytes[0]],
        sbox[bytes[5]],
        sbox[bytes[10]],
        sbox[bytes[15]],

        sbox[bytes[4]],
        sbox[bytes[9]],
        sbox[bytes[14]],
        sbox[bytes[3]],

        sbox[bytes[8]],
        sbox[bytes[13]],
        sbox[bytes[2]],
        sbox[bytes[7]],

        sbox[bytes[12]],
        sbox[bytes[1]],
        sbox[bytes[6]],
        sbox[bytes[11]],
    };

    return @as(i8x16, @bitCast(out)) ^ keys;
}

// constants

// Rijndael's irreducible polynomial.
const poly: u9 = 1 << 8 | 1 << 4 | 1 << 3 | 1 << 1 | 1 << 0; // x⁸ + x⁴ + x³ + x + 1

// Powers of x mod poly in GF(2).
const powx = init: {
    var array: [16]u8 = undefined;

    var value = 1;
    for (&array) |*power| {
        power.* = value;
        value = mul(value, 2);
    }

    break :init array;
};

const sbox align(64) = generateSbox(); // S-box for encryption
const table align(64) = generateTable(); // 4-byte LUTs for encryption

// Generate S-box substitution values.
fn generateSbox() [256]u8 {
    @setEvalBranchQuota(10000);

    var out: [256]u8 = undefined;

    var p: u8 = 1;
    var q: u8 = 1;
    for (out) |_| {
        p = mul(p, 3);
        q = mul(q, 0xf6); // divide by 3

        var value: u8 = q ^ 0x63;
        value ^= std.math.rotl(u8, q, 1);
        value ^= std.math.rotl(u8, q, 2);
        value ^= std.math.rotl(u8, q, 3);
        value ^= std.math.rotl(u8, q, 4);

        out[p] = value;
    }

    out[0x00] = 0x63;

    return out;
}

// Generate lookup tables.
fn generateTable() [4][256]u32 {
    var out: [4][256]u32 = undefined;

    for (generateSbox(), 0..) |value, index| {
        out[0][index] = std.math.shl(u32, mul(value, 0x3), 24);
        out[0][index] |= std.math.shl(u32, mul(value, 0x1), 16);
        out[0][index] |= std.math.shl(u32, mul(value, 0x1), 8);
        out[0][index] |= mul(value, 0x2);

        out[1][index] = std.math.rotl(u32, out[0][index], 8);
        out[2][index] = std.math.rotl(u32, out[0][index], 16);
        out[3][index] = std.math.rotl(u32, out[0][index], 24);
    }

    return out;
}

// Multiply a and b as GF(2) polynomials modulo poly.
fn mul(a: u8, b: u8) u8 {
    @setEvalBranchQuota(30000);

    var i: u8 = a;
    var j: u9 = b;
    var s: u9 = 0;

    while (i > 0) : (i >>= 1) {
        if (i & 1 != 0) {
            s ^= j;
        }

        j *= 2;
        if (j & 0x100 != 0) {
            j ^= poly;
        }
    }

    return @as(u8, @truncate(s));
}

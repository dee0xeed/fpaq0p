
const std = @import("std");
const os = std.os;
const Model = @import("bswi-model.zig").Model;

pub const Decoder = struct {

    model: *Model,
    fd: i32,
    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,
     x: u32 = 0,

    pub fn init(m: *Model, fd: i32) !Decoder {

        var d = Decoder {
            .model = m,
            .fd = fd,
        };

        var b: [1]u8 = undefined;
        var k: usize = 0;

        while (k < 4) : (k += 1) {
            var byte: u8 = undefined;
            var r = try os.read(d.fd, b[0..]);
            byte = b[0];
            if (0 == r) byte = 0;
            d.x = (d.x << 8) | byte;
        }
        return d;
    }

    pub fn give(self: *Decoder) !u1 {

        const xm = self.xl + ((self.xr - self.xl) >> Model.NBITS) * self.model.getP0();
        var bit: u1 = 1;
        if (self.x <= xm) {
            bit = 0;
            self.xr = xm;
        } else {
            self.xl = xm + 1;
        }

        self.model.update(bit);

        while (0 == ((self.xl ^ self.xr) & 0xFF00_0000)) {

            self.xl <<= 8;
            self.xr = (self.xr << 8) | 0x0000_00FF;

            var b: [1]u8 = undefined;
            var byte: u8 = undefined;
            var r = try os.read(self.fd, b[0..]);
            byte = b[0];
            if (0 == r) byte = 0;
            self.x = (self.x << 8) | byte;
        }

        return bit;
    }
};

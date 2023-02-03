
const std = @import("std");
const os = std.os;
const Model = @import("bswi-model.zig").Model;

pub const Encoder = struct {

    model: *Model,
    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,
    fd: i32,

    pub fn init(m: *Model, fd: i32) Encoder {
        return Encoder {
            .model = m,
            .fd = fd,
        };
    }

    pub fn take(self: *Encoder, bit: u1) !void {

        const xm = self.xl + ((self.xr - self.xl) >> Model.NBITS) * self.model.getP0();

        // left/lower part of the interval corresponds to zero

        if (0 == bit) {
            self.xr = xm;
        } else {
            self.xl = xm + 1;
        }

        self.model.update(bit);

        while (0 == ((self.xl ^ self.xr) & 0xFF00_0000)) {
            var b: [1]u8 = .{@intCast(u8, self.xr >> 24)};
            _ = try os.write(self.fd, b[0..]);
            self.xl <<= 8;
            self.xr = (self.xr << 8) | 0x0000_00FF;
        }
    }

    pub fn foldup(self: *Encoder) !void {
        var b: [1]u8 = .{@intCast(u8, self.xr >> 24)};
        _ = try os.write(self.fd, b[0..]);
    }
};

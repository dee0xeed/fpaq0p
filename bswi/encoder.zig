
const std = @import("std");
const os = std.os;
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;
const Model = @import("bswi-model.zig").Model;
const Writer = @import("buff-writer.zig").Writer;

pub const Encoder = struct {

    model: *Model,
    file: *fs.File,
    writer: *Writer,
    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,

    pub fn init(m: *Model, f: *fs.File, w: *Writer) Encoder {
        var self = Encoder {
            .model = m,
            .file = f,
            .writer = w,
        };
        return self;
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
            var byte = @intCast(u8, self.xr >> 24);
            try self.writer.take(byte);
            self.xl <<= 8;
            self.xr = (self.xr << 8) | 0x0000_00FF;
        }
    }

    pub fn foldup(self: *Encoder) !void {
        var byte = @intCast(u8, self.xr >> 24);
        try self.writer.take(byte);
        try self.writer.flush();
    }
};

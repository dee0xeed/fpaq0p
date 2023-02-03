
const std = @import("std");
const os = std.os;
const mem = std.mem;
const Allocator = mem.Allocator;

const Encoder = @import("encoder.zig").Encoder;
const Decoder = @import("decoder.zig").Decoder;
const Model = @import("bswi-model.zig").Model;

pub fn compress(order: u5, rfd: i32, wfd: i32, size: u32, a: Allocator) !void {

    var model = try Model.init(order, a);
    var encoder = Encoder.init(&model, wfd);
    var byte: u8 = 0;
    var k: usize = 0;
    var j: usize = 0;
    var bit: u1 = 0;

    // store original file size first (BE)
    var buf: [4]u8 = .{
        @intCast(u8, (size >> 24) & 0xFF),
        @intCast(u8, (size >> 16) & 0xFF),
        @intCast(u8, (size >>  8) & 0xFF),
        @intCast(u8, (size >>  0) & 0xFF),
    };
    _ = try os.write(wfd, buf[0..]);

    k = 0;
    while (k < size) : (k += 1) {

        _ = try os.read(rfd, buf[0..1]);

        j = 0;
        byte = buf[0];
        while (j < 8) : (j += 1) {
            bit = @intCast(u1, byte & 0b0000_0001);
            try encoder.take(bit);
            byte >>= 1;
        }
    }
    try encoder.foldup();
}

pub fn decompress(order: u5, rfd: i32, wfd: i32, a: Allocator) !void {

    var buf: [1]u8 = .{0};
    var size: u32 = 0;
    var k: isize = 0;
    var j: isize = 0;

    // fetch original file size first
    while (j < 4) : (j += 1) {
        _ = try os.read(rfd, buf[0..]);
        size = (size << 8) | buf[0];
    }

    var m = try Model.init(order, a);
    var decoder = try Decoder.init(&m, rfd);

    var bit: u1 = 0;
    var byte: u8 = 0;
    var bbb: u8 = 0;

    while (k < size) : (k += 1) {

        j = 0;
        byte = 0;
        while (j < 8) : (j += 1) {
            bit = try decoder.give();
            bbb = bit;
            bbb <<= 7;
            byte = (byte >> 1) | bbb;
        }
        buf = .{byte};
        _ = try os.write(wfd, buf[0..]);
    }
}

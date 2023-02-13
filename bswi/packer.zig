
const std = @import("std");
const os = std.os;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const Allocator = mem.Allocator;

const Encoder = @import("encoder.zig").Encoder;
const Decoder = @import("decoder.zig").Decoder;
const Model = @import("bswi-model.zig").Model;
const Reader = @import("buff-reader.zig").Reader;
const Writer = @import("buff-writer.zig").Writer;

pub fn compress(order: u5, rf: *fs.File, wf: *fs.File, size: u32, a: Allocator) !void {

    var k: usize = 0;
    var reader = try Reader.init(rf, 4096, a);
    var writer = try Writer.init(wf, 4096, a);
    var model = try Model.init(order, a);
    var encoder = Encoder.init(&model, wf, &writer);

    // store original file size first (BE)
    var buf: [4]u8 = .{
        @intCast(u8, (size >> 24) & 0xFF),
        @intCast(u8, (size >> 16) & 0xFF),
        @intCast(u8, (size >>  8) & 0xFF),
        @intCast(u8, (size >>  0) & 0xFF),
    };

    try writer.take(buf[0]);
    try writer.take(buf[1]);
    try writer.take(buf[2]);
    try writer.take(buf[3]);

    while (k < size) : (k += 1) {
        var byte = try reader.give() orelse unreachable;
        var j: u8 = 0;
        while (j < 8) : (j += 1) {
            var bit = @intCast(u1, byte & 0b0000_0001);
            try encoder.take(bit);
            byte >>= 1;
        }
    }
    try encoder.foldup();
}

pub fn decompress(order: u5, rf: *fs.File, wf: *fs.File, a: Allocator) !void {

//    var buf: [1]u8 = .{0};
    var size: u32 = 0;
    var k: isize = 0;
    var j: isize = 0;
    var byte: u8 = 0;

    var reader = try Reader.init(rf, 4096, a);
    var writer = try Writer.init(wf, 4096, a);

    // fetch original file size first
    while (j < 4) : (j += 1) {
        byte = try reader.give() orelse unreachable;
        size = (size << 8) | byte;
    }

    var m = try Model.init(order, a);
    var decoder = try Decoder.init(&m, rf, &reader);

    var bit: u1 = 0;
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
        _ = try writer.take(byte);
    }
    try writer.flush();
}

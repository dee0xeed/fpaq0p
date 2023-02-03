
const std = @import("std");
const os = std.os;
const mem = std.mem;
const Allocator = mem.Allocator;

const Encoder = @import("encoder.zig").Encoder;
const Decoder = @import("decoder.zig").Decoder;
const Model = @import("bswi-model.zig").Model;

fn compress(rfd: i32, wfd: i32, size: u32, a: Allocator) !void {

    var model = try Model.init(4, a);
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

fn decompress(rfd: i32, wfd: i32, a: Allocator) !void {

    var buf: [1]u8 = .{0};
    var size: u32 = 0;
    var k: isize = 0;
    var j: isize = 0;

    // fetch original file size first
    while (j < 4) : (j += 1) {
        _ = try os.read(rfd, buf[0..]);
        size = (size << 8) | buf[0];
    }

    var m = try Model.init(4, a);
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

fn help(prog: []const u8) void {
    std.debug.print("Usage: {s} <cmd> <infile> <outfile>\n", .{prog});
    std.debug.print("  cmd: c to compress, d to decompress\n", .{});
}

fn fileSize(fd: i32) u32 {
    const size = os.linux.lseek(fd, 0, os.SEEK.END);
    _ = os.linux.lseek(fd, 0, os.SEEK.SET);
    return @intCast(u32, size & 0xFFFF_FFFF);
}

pub fn main() !void {

    const prog = mem.sliceTo(os.argv[0], 0);
    if (os.argv.len != 4) {
        help(prog);
        return;
    }

    const mode = mem.sliceTo(os.argv[1], 0);
    if ((mode.len != 1) or ((mode[0] != 'c') and (mode[0] != 'd'))) {
        help(prog);
        return;
    }

    const rfile = mem.sliceTo(os.argv[2], 0);
    const wfile = mem.sliceTo(os.argv[3], 0);

    const rfd = try os.open(rfile, os.O.RDONLY, 0);
    const wfd = try os.open(wfile, os.O.WRONLY | os.O.CREAT | os.O.TRUNC, 0o0664);
    const rsize = fileSize(rfd);

    var ts1: os.timespec = undefined;
    try os.clock_gettime(os.CLOCK.REALTIME, &ts1);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    switch (mode[0]) {
        'c' => try compress(rfd, wfd, rsize, allocator),
        'd' => try decompress(rfd, wfd, allocator),
        else => unreachable,
    }

    var ts2: os.timespec = undefined;
    try os.clock_gettime(os.CLOCK.REALTIME, &ts2);

    const t1 = ts1.tv_sec * 1_000 + @divTrunc(ts1.tv_nsec, 1_000_000);
    const t2 = ts2.tv_sec * 1_000 + @divTrunc(ts2.tv_nsec, 1_000_000);
    const dt = t2 - t1;

    const wsize = fileSize(wfd);
    std.debug.print("{s} ({} bytes) -> {s} ({} bytes) in {} msec\n", .{rfile, rsize, wfile, wsize, dt});
}

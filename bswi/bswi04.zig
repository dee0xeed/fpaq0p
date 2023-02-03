
const std = @import("std");
const os = std.os;
const mem = std.mem;

const Encoder = @import("encoder.zig").Encoder;
const Decoder = @import("decoder.zig").Decoder;
const Model = @import("model.zig").Model;

const Model04 = struct {

    base: Model = undefined,
    // position of a bit in a byte, cyclically 0..7
    ix: u8 = 0,
    // context (sliding 4 bits)
    cx: u4 = 0,
    // probabilities of zero for given ix and cx
    // index of this array is calculated as `(ix << 4) | cx`
    p0: [8 * 16]u16 = undefined,

    fn init() Model04 {
        var model = Model04 {
            .base = Model {
                .getP0Impl = getP0,
                .updateImpl = update,
            },
        };
        var k: usize = 0;
        while (k < model.p0.len) : (k += 1) {
            model.p0[k] = Model.P0MAX / 2;
        }
        return model;
    }

    // returns probability of '0' for given bit position (ix) and context (cx)
    pub fn getP0(base: *Model) u16 {
        var self = @fieldParentPtr(Model04, "base", base);
        const i: u16 = (self.ix << 4) | self.cx;
        return self.p0[i];
    }

    pub fn update(base: *Model, bit: u1) void {
        var self = @fieldParentPtr(Model04, "base", base);
        var delta: u16 = 0;
        const i: u16 = (self.ix << 4) | self.cx;
        if (0 == bit) {
            delta = (Model.P0MAX - self.p0[i]) >> Model.DS;
            self.p0[i] += delta;
        } else {
            delta = self.p0[i] >> Model.DS;
            self.p0[i] -= delta;
        }
        self.cx = (self.cx << 1) | bit;
        self.ix = (self.ix + 1) & 0x0007;
    }
};

fn compress(rfd: i32, wfd: i32, size: u32) !void {

    var model = Model04.init();
    var encoder = Encoder.init(&model.base, wfd);
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

fn decompress(rfd: i32, wfd: i32) !void {

    var buf: [1]u8 = .{0};
    var size: u32 = 0;
    var k: isize = 0;
    var j: isize = 0;

    // fetch original file size first
    while (j < 4) : (j += 1) {
        _ = try os.read(rfd, buf[0..]);
        size = (size << 8) | buf[0];
    }

    var m = Model04.init();
    var decoder = try Decoder.init(&m.base, rfd);

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

    switch (mode[0]) {
        'c' => try compress(rfd, wfd, rsize),
        'd' => try decompress(rfd, wfd),
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

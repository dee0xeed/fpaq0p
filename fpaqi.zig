
const std = @import("std");
const os = std.os;
const mem = std.mem;

const Model = struct {

    const NBITS = 12;
    const P0MAX = 1 << NBITS;

    // 3 - bigger delta_p0, faster adaptation; 6 - smaller delta_p0, slower adaptation
    // 4 seems to be better in most cases (than 5)
    const DS = 4; 

    // position of a bit in a byte, cyclically 0..7
    ix: u16 = 0,

    // context (sliding byte)
    cx: u8 = 0,

    // probabilities of zero for given ix and cx
    // index of this array is calculated as `(ix << 8) | cx`
    p0: [8 * 256]u16 = undefined,

    fn init() Model {
        var m = Model{};
        var k: usize = 0;
        while (k < 8 * 256) : (k += 1) {
            m.p0[k] = P0MAX / 2;
        }
        return m;
    }

    // returns probability of '0' for given bit position (ix) and context (cx)
    fn getP0(self: *Model) u16 {
        const i: u16 = (self.ix << 8) | self.cx;
        return self.p0[i];
    }

    fn update(self: *Model, bit: u1) void {
        var delta: u16 = 0;
        const i: u16 = (self.ix << 8) | self.cx;
        if (0 == bit) {
            delta = (P0MAX - self.p0[i]) >> DS;
            self.p0[i] += delta;
        } else {
            delta = self.p0[i] >> DS;
            self.p0[i] -= delta;
        }
        self.cx = (self.cx << 1) | bit;
        self.ix = (self.ix + 1) & 0x0007;
    }
};

const Encoder = struct {

    model: *Model,
    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,
    fd: i32,

    fn init(m: *Model, fd: i32) Encoder {
        return Encoder {
            .model = m,
            .fd = fd,
        };
    }

    fn encode(self: *Encoder, bit: u1) !void {

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

    fn foldup(self: *Encoder) !void {
        var b: [1]u8 = .{@intCast(u8, self.xr >> 24)};
        _ = try os.write(self.fd, b[0..]);
    }
};

const Decoder = struct {

    model: *Model,
    fd: i32,
    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,
     x: u32 = 0,

    fn init(m: *Model, fd: i32) !Decoder {

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

    fn decode(self: *Decoder) !u1 {

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

fn compress(rfd: i32, wfd: i32, size: u32) !void {

    var m = Model.init();
    var e = Encoder.init(&m, wfd);
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
            try e.encode(bit);
            byte >>= 1;
        }
    }
    try e.foldup();
}

fn decompress(rfd: i32, wfd: i32) !void {

    // read original file size first
    var buf: [1]u8 = .{0};
    var size: u32 = 0;
    var k: isize = 0;
    var j: isize = 0;

    while (j < 4) : (j += 1) {
        _ = try os.read(rfd, buf[0..]);
        size = (size << 8) | buf[0];
    }

    var m = Model.init();
    var d = try Decoder.init(&m, rfd);

    var bit: u1 = 0;
    var byte: u8 = 0;
    var bbb: u8 = 0;

    while (k < size) : (k += 1) {

        j = 0;
        byte = 0;
        while (j < 8) : (j += 1) {
            bit = try d.decode();
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

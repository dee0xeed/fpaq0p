
const std = @import("std");
const os = std.os;
const mem = std.mem;

const Model = struct {

    const NBITS = 12;
    const P0MAX = 1 << NBITS;
    const WTMAX = 1 << NBITS;
    const DS = 4; 

    // position of a bit in a byte, cyclically 0..7
    ix: u32 = 0,

    // contexts (sliding bit windows)
    cx_8: u8 = 0,
    cx_12: u12 = 0,
    cx_16: u16 = 0,
    // and weights
//    wt: [3]u32 = .{WTMAX/3, WTMAX/3, WTMAX/3},
    wt: [3]u32 = .{1,1,1},
  //  n: usize = 3,
    p0: [3]u16 = .{P0MAX/2, P0MAX/2, P0MAX/2},

    // probabilities of zero for given ix and cx[k]
    // index of this array is calculated as `(ix << 8) | cx[0]`
    p0_8: [8 * (1 << 8)]u16 = undefined,
    // index of this array is calculated as `(ix << 12) | cx[1]`
    p0_12: [8 * (1 << 12)]u16 = undefined,
    // index of this array is calculated as `(ix << 16) | cx[2]`
    p0_16: [8 * (1 << 16)]u16 = undefined,

    fn init() Model {
        var m = Model{};
        var k: usize = 0;
        while (k < m.p0_8.len) : (k += 1) {
            m.p0_8[k] = P0MAX / 2;
        }
        k = 0;
        while (k < m.p0_12.len) : (k += 1) {
            m.p0_12[k] = P0MAX / 2;
        }
        k = 0;
        while (k < m.p0_16.len) : (k += 1) {
            m.p0_16[k] = P0MAX / 2;
        }
        return m;
    }

    // returns probability of '0' for given bit position (ix) and context (cx)
    fn getP0(self: *Model) u16 {

        const i_8: u32 = (self.ix << 8) | self.cx_8;
        const i_12: u32 = (self.ix << 12) | self.cx_12;
        const i_16: u32 = (self.ix << 16) | self.cx_16;

        const p0a = self.p0_8[i_8];
        const p0b = self.p0_12[i_12];
        const p0c = self.p0_16[i_16];
        const p0 = (p0a*self.wt[0] + p0b*self.wt[1] + p0c*self.wt[2]) / (self.wt[0] + self.wt[1] + self.wt[2]);
        //std.debug.print("{}/{} {}/{} {}/{} -> {}\n", .{p0a, self.wt[0], p0b, self.wt[1], p0c, self.wt[2], p0});

        // save current predictions for use in update()
        self.p0[0] = p0a;
        self.p0[1] = p0b;
        self.p0[2] = p0c;

        return @intCast(u16, p0);
    }

    fn update(self: *Model, bit: u1) void {

        var delta_8: u16 = 0;
        var delta_12: u16 = 0;
        var delta_16: u16 = 0;

        const i_8: u32 = (self.ix << 8) | self.cx_8;
        const i_12: u32 = (self.ix << 12) | self.cx_12;
        const i_16: u32 = (self.ix << 16) | self.cx_16;

        if (0 == bit) {

            delta_8 = (P0MAX - self.p0_8[i_8]) >> DS;
            self.p0_8[i_8] += delta_8;

            delta_12 = (P0MAX - self.p0_12[i_12]) >> DS;
            self.p0_12[i_12] += delta_12;

            delta_16 = (P0MAX - self.p0_16[i_16]) >> DS;
            self.p0_16[i_16] += delta_16;

        } else {

            delta_8 = self.p0_8[i_8] >> DS;
            self.p0_8[i_8] -= delta_8;

            delta_12 = self.p0_12[i_12] >> DS;
            self.p0_12[i_12] -= delta_12;

            delta_16 = self.p0_16[i_16] >> DS;
            self.p0_16[i_16] -= delta_16;
        }

        // update weights
        var i: usize = 0;
        if (0 == bit) {
            i = 0;
            while (i < 3) : (i += 1) {
                if (self.p0[i] > P0MAX/2) {         // good -> increase
                    self.wt[i] += 1;
                } else if (self.p0[i] < P0MAX/2) {  // bad -> decrease
                    if (self.wt[i] > 0)
                        self.wt[i] -= 1;
                }
            }
        } else {
            i = 0;
            while (i < 3) : (i += 1) {
                if (self.p0[i] < P0MAX/2) {         // good -> increase
                    self.wt[i] += 1;
                } else if (self.p0[i] > P0MAX/2) {  // bad -> decrease
                    if (self.wt[i] > 0)
                        self.wt[i] -= 1;
                }
            }
        }

        var max: u32 = 0;
        i = 0;
        while (i < 3) : (i += 1) {
            if (self.wt[i] > max)
                max = self.wt[i];
        }
        if (max > 511) {
            i = 0;
            while (i < 3) : (i += 1) {
                self.wt[i] >>= 1;
            }
        }

        self.cx_8 = (self.cx_8 << 1) | bit;
        self.cx_12 = (self.cx_12 << 1) | bit;
        self.cx_16 = (self.cx_16 << 1) | bit;
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

        const p0 = self.model.getP0();
        const xm = self.xl + ((self.xr - self.xl) >> Model.NBITS) * p0;

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

        const p0 = self.model.getP0();
        const xm = self.xl + ((self.xr - self.xl) >> Model.NBITS) * p0;
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
    std.debug.print("w[e1] = {} w[e3] = {} w[e4] = {}\n", .{m.wt[0], m.wt[1], m.wt[2]});
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

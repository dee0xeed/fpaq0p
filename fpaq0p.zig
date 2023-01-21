
const std = @import("std");
const os = std.os;
const mem = std.mem;

const Model = struct {

    const NBITS = 12;
    const P1MAX = 1 << NBITS;
    const DS = 5;

    cx: u16 = 1,
    p1: [512]u16 = undefined,

    fn init() Model {
        var m = Model{};
        var k: usize = 0;
        while (k < 512) : (k += 1) {
            m.p1[k] = P1MAX / 2;
        }
        return m;
    }

    fn getP1(self: *Model) u16 {
        return self.p1[self.cx];
    }

    fn update(self: *Model, bit: u1) void {
        var delta: u16 = 0;
        if (1 == bit) {
            delta = (P1MAX - self.p1[self.cx]) >> DS;
            self.p1[self.cx] += delta;
        } else {
            delta = self.p1[self.cx] >> DS;
            self.p1[self.cx] -= delta;
        }
        self.cx += self.cx + bit;
        if (self.cx >= 512)
            self.cx = 1;
    }
};

const Codec = struct {

    model: *Model,
    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,
    fd: i32,
     x: u32 = 0,

    fn init(m: *Model, fd: i32) Codec {
        return Codec {
            .model = m,
            .fd = fd,
        };
    }

    fn encode(self: *Codec, bit: u1) !void {

        const xm = self.xl + ((self.xr - self.xl) >> Model.NBITS) * self.model.getP1();

        if (1 == bit) {
            self.xr = xm;
        } else {
            self.xl = xm + 1;
        }

        self.model.update(bit);

        while (((self.xl ^ self.xr) & 0xFF00_0000) == 0) {
            var b: [1]u8 = undefined;
            b[0] = @intCast(u8, self.xr >> 24);
            _ = try os.write(self.fd, b[0..]);
            self.xl <<= 8;
            self.xr = (self.xr << 8) | 0x0000_00FF;
        }
    }

    // to be called in the end of compression
    fn foldup(self: *Codec) !void {
        var b: [1]u8 = undefined;
        b[0] = @intCast(u8, self.xr >> 24);
        _ = try os.write(self.fd, b[0..]);
    }

    // to be called in the beginning of decompression
    fn begin(self: *Codec) !void {
        var b: [1]u8 = undefined;
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            var byte: u8 = undefined;
            var r = try os.read(self.fd, b[0..]);
            byte = b[0];
            if (0 == r) byte = 0;
            self.x = (self.x << 8) | byte;
        }
    }

    fn decode(self: *Codec) !u1 {

        const xm = self.xl + ((self.xr - self.xl) >> Model.NBITS) * self.model.getP1();
        var bit: u1 = 0;
        if (self.x <= xm) {
            bit = 1;
            self.xr = xm;
        } else {
            self.xl = xm + 1;
        }

        self.model.update(bit);

        while (((self.xl ^ self.xr) & 0xFF00_0000) == 0) {

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

fn compress(rfd: i32, wfd: i32) !void {

    var m = Model.init();
    var c = Codec.init(&m, wfd);

    while (true) {

        var b: [1]u8 = undefined;
        var r: usize = 0;

        r = try os.read(rfd, b[0..]);
        if (0 == r)
            break;

        var k: usize = 0;
        var byte = b[0];

        try c.encode(0);
        while (k < 8) : (k += 1) {
            const bit: u1 = @intCast(u1, (byte >> (7 - @intCast(u3, k))) & 0x01);
            try c.encode(bit);
        }
    }
    try c.encode(1);
    try c.foldup();
}

fn decompress(rfd: i32, wfd: i32) !void {

    var m = Model.init();
    var c = Codec.init(&m, rfd);

    try c.begin();

    while (true) {
    
        var bit: u1 = try c.decode();
        if (1 == bit)
            break;
    
        var byte: u8 = 0;
        var k: usize = 0;

        while (k < 8) : (k += 1) {
            bit = try c.decode();
            byte = (byte << 1) | bit;
        }

        var b: [1]u8 = .{byte};
        _ = try os.write(wfd, b[0..]);
    }
}

fn help(prog: []const u8) void {
    std.debug.print("Usage: {s} <cmd> <infile> <outfile>\n", .{prog});
    std.debug.print("  cmd: c to compress, d to decompress\n", .{});
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
    const wfd = try os.open(wfile, os.O.WRONLY | os.O.CREAT, 0o0664);

    var ts1: os.timespec = undefined;
    try os.clock_gettime(os.CLOCK.REALTIME, &ts1);

    switch (mode[0]) {
        'c' => try compress(rfd, wfd),
        'd' => try decompress(rfd, wfd),
        else => unreachable,
    }

    var ts2: os.timespec = undefined;
    try os.clock_gettime(os.CLOCK.REALTIME, &ts2);

    const t1 = ts1.tv_sec * 1_000 + @divTrunc(ts1.tv_nsec, 1_000_000);
    const t2 = ts2.tv_sec * 1_000 + @divTrunc(ts2.tv_nsec, 1_000_000);
    const dt = t2 - t1;

    const rsize = os.linux.lseek(rfd, 0, os.SEEK.END);
    const wsize = os.linux.lseek(wfd, 0, os.SEEK.END);
    std.debug.print("{s} ({} bytes) -> {s} ({} bytes) in {} msec\n", .{rfile, rsize, wfile, wsize, dt});
}

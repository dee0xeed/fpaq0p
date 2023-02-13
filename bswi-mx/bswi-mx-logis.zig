
const std = @import("std");
const os = std.os;
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;

const Reader = struct {

    file: *fs.File = undefined,
    buff: []u8 = undefined,
    bcnt: u32 = 0,
    curr: u32 = 0,

    fn init(f: *fs.File, s: u32, a: Allocator) !Reader {
        var self = Reader{};
        self.buff = try a.alloc(u8, s);
        self.file = f;
        return self;
    }

    fn give(self: *Reader) !?u8 {
        if (0 == self.bcnt) {
            self.bcnt = @intCast(u32, try self.file.read(self.buff[0..]));
            if (0 == self.bcnt) return null;
            self.curr = 0;
        }
        self.bcnt -= 1;
        const byte = self.buff[self.curr];
        self.curr += 1;
        return byte;
    }
};

const Writer = struct {

    buff: []u8 = undefined,
    bcnt: u32 = 0,
    file: *fs.File = undefined,

    fn init(f: *fs.File, s: u32, a: Allocator) !Writer {
        var self = Writer{};
        self.buff = try a.alloc(u8, s);
        self.file = f;
        return self;
    }

    fn take(self: *Writer, byte: u8) !void {
        if (self.bcnt == self.buff.len) {
            _ = try self.file.write(self.buff[0..]);
            self.bcnt = 0;
        }
        self.buff[self.bcnt] = byte;
        self.bcnt += 1;
    }

    fn flush(self: *Writer) !void {
        if (self.bcnt > 0) {
            _ = try self.file.write(self.buff[0..self.bcnt]);
            self.bcnt = 0;
        }
    }
};

const Stat = struct {
    n0: usize = undefined,
    n1: usize = undefined,

    fn p0(self: *Stat) f64 {
        return (@intToFloat(f64, self.n0) + 0.5) / (@intToFloat(f64, self.n0 + self.n1) + 1.0);
    }
};

const Model = struct {

    const NBITS = 12;

    // position of a bit in a byte, cyclically 0..7
    ix: u32 = 0,
    // contexts (sliding bit windows)
    cx1: u8 = 0,
    cx2: u12 = 0,
    cx3: u16 = 0,

    // probabilities of zero for given ix and cx[k]
    // index of this array is calculated as `(ix << 8) | cx1`
    s1: []Stat = undefined,
    // index of this array is calculated as `(ix << 12) | cx2`
    s2: []Stat = undefined,
    // index of this array is calculated as `(ix << 16) | cx3`
    s3: []Stat = undefined,

    w1: f64 = 0.0,
    w2: f64 = 0.0,
    w3: f64 = 0.0,
    px: f64 = 0.0,
    d1: f64 = 0.0,
    d2: f64 = 0.0,
    d3: f64 = 0.0,

    fn init(a: Allocator) !Model {
        var m = Model{};
        var k: usize = undefined;

        m.s1 = try a.alloc(Stat, 8 * (1 << 8));
        m.s2 = try a.alloc(Stat, 8 * (1 << 12));
        m.s3 = try a.alloc(Stat, 8 * (1 << 16));

        k = 0;
        while (k < m.s1.len) : (k += 1) {
            m.s1[k].n0 = 0;
            m.s1[k].n1 = 0;
        }

        k = 0;
        while (k < m.s2.len) : (k += 1) {
            m.s2[k].n0 = 0;
            m.s2[k].n1 = 0;
        }

        k = 0;
        while (k < m.s3.len) : (k += 1) {
            m.s3[k].n0 = 0;
            m.s3[k].n1 = 0;
        }

        return m;
    }

    fn logit(x: f64) f64 {
        return @log(x / (1.0 - x));
    }

    fn expit(x: f64) f64 {
        return 1.0 / (1.0 + @exp(-x));
    }

    // returns probability of '0' for given bit position (ix) and context (cx)
    fn getP0(self: *Model) u16 {

        const _i1: u32 = (self.ix << 8) | self.cx1;
        const _i2: u32 = (self.ix << 12) | self.cx2;
        const _i3: u32 = (self.ix << 16) | self.cx3;

        const p1 = self.s1[_i1].p0();
        const p2 = self.s2[_i2].p0();
        const p3 = self.s3[_i3].p0();

        self.d1 = logit(p1);
        self.d2 = logit(p2);
        self.d3 = logit(p3);

        const f1: f64 = 0.2;
        self.px = f1 * ((self.w1 * self.d1) + (self.w2 * self.d2) + (self.w3 * self.d3));
        self.px = expit(self.px);

        return @floatToInt(u16, 4096.0 * self.px);
    }

    fn clip(x: f64) f64 {
        if (x < -16.0) return -16.0;
        if (x > 16.0) return 16.0;
        return x;
    }

    fn update(self: *Model, bit: u1) void {

        const _i1: u32 = (self.ix << 8) | self.cx1;
        const _i2: u32 = (self.ix << 12) | self.cx2;
        const _i3: u32 = (self.ix << 16) | self.cx3;

        if (0 == bit) {
            self.s1[_i1].n0 += 1;
            self.s2[_i2].n0 += 1;
            self.s3[_i3].n0 += 1;
        } else {
            self.s1[_i1].n1 += 1;
            self.s2[_i2].n1 += 1;
            self.s3[_i3].n1 += 1;
        }

        const err: f64 = (1.0 - @intToFloat(f64, bit)) - self.px;
        const lrt: f64 = 0.02;
        self.w1 += self.d1 * err * lrt;
        self.w2 += self.d2 * err * lrt;
        self.w3 += self.d3 * err * lrt;

        self.w1 = clip(self.w1);
        self.w2 = clip(self.w2);
        self.w3 = clip(self.w3);

        self.cx1 = (self.cx1 << 1) | bit;
        self.cx2 = (self.cx2 << 1) | bit;
        self.cx3 = (self.cx3 << 1) | bit;
        self.ix = (self.ix + 1) & 0x0007;
    }
};

const Encoder = struct {

    model: *Model,
    file: *fs.File,
    writer: *Writer,
    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,

    fn init(m: *Model, f: *fs.File, w: *Writer) Encoder {
        var self = Encoder {
            .model = m,
            .file = f,
            .writer = w,
        };
        return self;
    }

    fn take(self: *Encoder, bit: u1) !void {

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
            var byte = @intCast(u8, self.xr >> 24);
            try self.writer.take(byte);
            self.xl <<= 8;
            self.xr = (self.xr << 8) | 0x0000_00FF;
        }
    }

    fn foldup(self: *Encoder) !void {
        var byte = @intCast(u8, self.xr >> 24);
        try self.writer.take(byte);
        try self.writer.flush();
    }
};

const Decoder = struct {

    model: *Model,
    file: *fs.File,
    reader: * Reader,

    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,
     x: u32 = 0,

    fn init(m: *Model, f: *fs.File, r: *Reader) !Decoder {

        var d = Decoder {
            .model = m,
            .file = f,
            .reader = r,
        };

        var byte: u8 = undefined;
        var k: usize = 0;

        while (k < 4) : (k += 1) {
            byte = try r.give() orelse 0;
            // if (null == byte) byte = 0;
            d.x = (d.x << 8) | byte;
        }
        return d;
    }

    fn give(self: *Decoder) !u1 {

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

            var byte = try self.reader.give() orelse 0;
            self.x = (self.x << 8) | byte;
        }

        return bit;
    }
};

fn compress(rf: *fs.File, wf: *fs.File, size: u32, a: Allocator) !void {

    var k: usize = 0;
    var reader = try Reader.init(rf, 4096, a);
    var writer = try Writer.init(wf, 4096, a);
    var model = try Model.init(a);
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
    std.debug.print("w0={d:.3} w1={d:.3} w2={d:.3}\n", .{model.w1, model.w2, model.w3});
}

pub fn decompress(rf: *fs.File, wf: *fs.File, a: Allocator) !void {

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

    var m = try Model.init(a);
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

    var ts1: os.timespec = undefined;
    try os.clock_gettime(os.CLOCK.REALTIME, &ts1);

    const rfile = mem.sliceTo(os.argv[2], 0);
    const wfile = mem.sliceTo(os.argv[3], 0);

    var path_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const rpath = try fs.realpath(rfile, &path_buf);
    var rf = try fs.openFileAbsolute(rpath, .{});
    const rsize = (try rf.stat()).size;
    var wf = try fs.cwd().createFile(wfile, .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    switch (mode[0]) {
        'c' => try compress(&rf, &wf, @intCast(u32, rsize), allocator),
        'd' => try decompress(&rf, &wf, allocator),
        else => unreachable,
    }

    var ts2: os.timespec = undefined;
    try os.clock_gettime(os.CLOCK.REALTIME, &ts2);

    const t1 = ts1.tv_sec * 1_000 + @divTrunc(ts1.tv_nsec, 1_000_000);
    const t2 = ts2.tv_sec * 1_000 + @divTrunc(ts2.tv_nsec, 1_000_000);
    const dt = t2 - t1;

    const wsize = (try wf.stat()).size;
    std.debug.print("{s} ({} bytes) -> {s} ({} bytes) in {} msec\n", .{rfile, rsize, wfile, wsize, dt});
}

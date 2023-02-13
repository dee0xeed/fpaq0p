
const std = @import("std");
const os = std.os;
const fs = std.fs;
const mem = std.mem;

const Reader = struct {

    file: *fs.File,
    buff: [4096]u8 = undefined,
    bcnt: u32 = 0,
    curr: u32 = 0,

    fn init(f: *fs.File) Reader {
        return Reader{.file = f};
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

    file: *fs.File,
    buff: [4096]u8 = undefined,
    bcnt: u32 = 0,

    fn init(f: *fs.File) Writer {
        return Writer{.file = f};
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
        }
    }
};

const Model = struct {

    const NBITS = 12;
    const P1MAX = 1 << NBITS;
    const DS = 5;

    cx: u16 = 1,
    p1: [512]u16 = undefined,

    fn init() Model {
        var m = Model{};
        var k: usize = 0;
        while (k < m.p1.len) : (k += 1) {
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

const Encoder = struct {

    model: *Model,
    writer: *Writer,

    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,

    fn init(m: *Model, w: *Writer) Encoder {
        return Encoder {
            .model = m,
            .writer= w,
        };
    }

    fn take(self: *Encoder, bit: u1) !void {

        const xm = self.xl + ((self.xr - self.xl) >> Model.NBITS) * self.model.getP1();

        if (1 == bit) {
            self.xr = xm;
        } else {
            self.xl = xm + 1;
        }

        self.model.update(bit);

        while (((self.xl ^ self.xr) & 0xFF00_0000) == 0) {
            var byte = @intCast(u8, self.xr >> 24);
            try self.writer.take(byte);
            self.xl <<= 8;
            self.xr = (self.xr << 8) | 0x0000_00FF;
        }
    }

    // to be called in the end of compression
    fn foldup(self: *Encoder) !void {
        var byte = @intCast(u8, self.xr >> 24);
        try self.writer.take(byte);
        try self.writer.flush();
    }
};

const Decoder = struct {

    model: *Model,
    reader: *Reader,

    xl: u32 = 0,
    xr: u32 = 0xFFFF_FFFF,
     x: u32 = 0,

    fn init(m: *Model, r: *Reader) Decoder {
        return Decoder {
            .model = m,
            .reader= r,
        };
    }

    // to be called in the beginning of decompression
    fn begin(self: *Decoder) !void {
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            var byte = try self.reader.give() orelse 0;
            self.x = (self.x << 8) | byte;
        }
    }

    fn give(self: *Decoder) !u1 {

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
            var byte = try self.reader.give() orelse 0;
            self.x = (self.x << 8) | byte;
        }

        return bit;
    }
};

fn compress(r: *Reader, w: *Writer) !void {

    var m = Model.init();
    var e = Encoder.init(&m, w);

    while (true) {

        var byte = try r.give() orelse break;
        var k: usize = 0;

        try e.take(0);
        while (k < 8) : (k += 1) {
            const bit: u1 = @intCast(u1, (byte >> (7 - @intCast(u3, k))) & 0x01);
            try e.take(bit);
        }
    }
    try e.take(1);
    try e.foldup();
}

fn decompress(r: *Reader, w: *Writer) !void {

    var m = Model.init();
    var d = Decoder.init(&m, r);

    try d.begin();

    while (true) {

        var bit = try d.give();
        if (1 == bit)
            break;

        var byte: u8 = 0;
        var k: usize = 0;

        while (k < 8) : (k += 1) {
            bit = try d.give();
            byte = (byte << 1) | bit;
        }

        try w.take(byte);
    }
    try w.flush();
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

    var reader = Reader.init(&rf);
    var writer = Writer.init(&wf);

    switch (mode[0]) {
        'c' => try compress(&reader, &writer),
        'd' => try decompress(&reader, &writer),
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

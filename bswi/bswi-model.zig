
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

pub const Model = struct {

    pub const NBITS = 12;
    pub const P0MAX = 1 << NBITS;
    // 3 - bigger delta_p0, faster adaptation; 6 - smaller delta_p0, slower adaptation
    // 4 seems to be better in most cases (than 5)
    pub const DS = 4; 
    const IX_MASK = 0x0000_0007;

    // order (number of most recent *bits*)
    order: u5,

    // context (sliding window .order bits wide)
    cx: u32 = 0,
    cx_mask: u32 = 0,

    // position of a bit in a byte, cyclically 0..7
    ix: u32 = 0,

    // probabilities of zero (scaled to 0..4096) for given ix and cx
    // index of this array is calculated as `(ix << .order) | cx`
    p0: []u16 = undefined,

    pub fn init(order: u5, a: Allocator) !Model {
        var model = Model {.order = order};
        model.order = order;
        model.cx_mask = (@as(u32, 1) << order) - 1;
        const table_len = 8 * (@as(u32, 1) << order);
        model.p0 = try a.alloc(u16, table_len);
        var k: usize = 0;
        while (k < model.p0.len) : (k += 1) {
            model.p0[k] = P0MAX / 2;
        }
        return model;
    }

    // returns probability of '0' for given bit position (ix) and context (cx)
    pub fn getP0(self: *Model) u16 {
        const i: u32 = (self.ix << self.order) | self.cx;
        return self.p0[i];
    }

    pub fn update(self: *Model, bit: u1) void {
        var delta: u16 = 0;
        const i: u32 = (self.ix << self.order) | self.cx;
        if (0 == bit) {
            delta = (P0MAX - self.p0[i]) >> DS;
            self.p0[i] += delta;
        } else {
            delta = self.p0[i] >> DS;
            self.p0[i] -= delta;
        }
        self.cx = ((self.cx << 1) | bit) & self.cx_mask;
        self.ix = (self.ix + 1) & IX_MASK;
    }
};

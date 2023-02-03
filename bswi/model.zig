
// generic model (~ "abstract class" / "interface")
pub const Model = struct {

    pub const NBITS = 12;
    pub const P0MAX = 1 << NBITS;
    // 3 - bigger delta_p0, faster adaptation; 6 - smaller delta_p0, slower adaptation
    // 4 seems to be better in most cases (than 5)
    pub const DS = 4; 

    // position of a bit in a byte, cyclically 0..7
    ix: u8 = 0,
    // context (sliding 4 bits)
    cx: u4 = 0,
    // probabilities of zero for given ix and cx
    // index of this array is calculated as `(ix << 4) | cx`
    p0: [8 * 16]u16 = undefined,

    getP0Impl: *const fn(self: *Model) u16,
    updateImpl: *const fn(self: *Model, bit: u1) void,

    // returns probability of '0' for given bit position (ix) and context (cx)
    pub fn getP0(self: *Model) u16 {
        return self.getP0Impl(self);
    }

    pub fn update(self: *Model, bit: u1) void {
        return self.updateImpl(self, bit);
    }
};

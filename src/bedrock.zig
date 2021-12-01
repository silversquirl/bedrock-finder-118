const std = @import("std");

pub const PatternFinder = struct {
    gen: GradientGenerator,
    // Layers along Y, rows along Z, columns along X
    pattern: []const []const []const ?Block,

    pub noinline fn search(self: PatternFinder, a: Point, b: Point, resultFn: fn (p: Point) void) void {
        var z: i32 = a.z;
        while (z <= b.z) : (z += 1) {
            var x: i32 = a.x;
            while (x <= b.x) : (x += 1) {
                var y: i32 = a.y;
                while (y <= b.y) : (y += 1) {
                    if (self.check(x, y, z)) {
                        resultFn(.{ .x = x, .y = y, .z = z });
                    }
                }
            }
        }
    }

    pub noinline fn check(self: PatternFinder, x: i32, y: i32, z: i32) bool {
        // TODO: evict the pharoahs from this evil pyramid of doom
        for (self.pattern) |layer, py| {
            for (layer) |row, pz| {
                for (row) |block_opt, px| {
                    if (block_opt) |block| {
                        const block_at = self.gen.at(
                            x + @intCast(i32, px),
                            y + @intCast(i32, py),
                            z + @intCast(i32, pz),
                        );
                        if (block != block_at) {
                            return false;
                        }
                    }
                }
            }
        }
        return true;
    }
};

pub const Point = struct {
    x: i32,
    y: i32,
    z: i32,
};

pub const GradientGenerator = struct {
    rand: PosRandom,
    lower: Block,
    upper: Block,
    lower_y: i32,
    upper_y: i32,

    pub fn at(self: GradientGenerator, x: i32, y: i32, z: i32) Block {
        if (y <= self.lower_y) {
            return self.lower;
        }
        if (y >= self.upper_y) {
            return self.upper;
        }

        const fac = 1 - normalize(
            @intToFloat(f64, y),
            @intToFloat(f64, self.lower_y),
            @intToFloat(f64, self.upper_y),
        );

        if (self.rand.at(x, y, z).nextf() < fac) {
            return self.lower;
        } else {
            return self.upper;
        }
    }

    fn normalize(x: f64, zero: f64, one: f64) f64 {
        return (x - zero) / (one - zero);
    }

    pub fn overworldFloor(seed: i64) GradientGenerator {
        var world_random = Random.init(seed);
        return GradientGenerator{
            .rand = PosRandom.init(&world_random),
            .lower = .bedrock,
            .upper = .other,
            .lower_y = -64,
            .upper_y = -59,
        };
    }

    pub fn netherFloor(seed: i64) GradientGenerator {
        var world_random = Random.init(seed);
        return GradientGenerator{
            .rand = PosRandom.init(&world_random),
            .lower = .bedrock,
            .upper = .other,
            .lower_y = 0,
            .upper_y = 5,
        };
    }
    pub fn netherCeiling(seed: i64) GradientGenerator {
        var world_random = Random.init(seed);
        _ = world_random.next64(); // Discard floor seed
        return GradientGenerator{
            .rand = PosRandom.init(&world_random),
            .lower = .other,
            .upper = .bedrock,
            .lower_y = 122,
            .upper_y = 127,
        };
    }
};

pub const Block = enum {
    bedrock,
    other,
};

pub const Random = struct {
    seed: i64,

    const magic = 0x5DEECE66D;
    const mask = ((1 << 48) - 1);

    pub fn init(seed: i64) Random {
        return .{ .seed = (seed ^ magic) & mask };
    }

    pub fn next(self: *Random, bits: u6) i32 {
        std.debug.assert(bits <= 32);
        self.seed = (self.seed *% magic +% 0xb) & mask;
        return @truncate(i32, self.seed >> (48 - bits));
    }

    pub fn next64(self: *Random) i64 {
        const top: i64 = self.next(32);
        const bottom: i64 = self.next(32);
        const result = (top << 32) + bottom;
        return result;
    }

    pub fn nextf(self: *Random) f32 {
        return @intToFloat(f32, self.next(24)) * 5.9604645e-8;
    }
};

pub const PosRandom = struct {
    seed: i64,

    pub fn init(world: *Random) PosRandom {
        return .{ .seed = world.next64() };
    }

    pub fn at(self: PosRandom, x: i32, y: i32, z: i32) Random {
        var seed = @as(i64, x *% 3129871) ^ (@as(i64, z) *% 116129781) ^ y;
        seed = seed *% seed *% 42317861 +% seed *% 0xb;
        return Random.init((seed >> 16) ^ self.seed);
    }
};
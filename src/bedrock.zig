const std = @import("std");

pub const PatternFinder = struct {
    gen: GradientGenerator,
    // Layers along Y, rows along Z, columns along X
    pattern: []const []const []const ?Block,

    pub fn search(
        self: PatternFinder,
        a: Point,
        b: Point,
        comptime resultFn: fn (p: Point) void,
        comptime progressFn: ?fn (count: u64, total: u64) void,
    ) void {
        const total: u64 = a.areaTo(b);
        var count: u64 = 0;
        var it = a.iterTo(b);
        while (it.next()) |p| {
            if (progressFn) |f| {
                count += 1;
                f(count, total);
            }
            if (self.check(p)) {
                resultFn(p);
            }
        }
    }

    pub fn check(self: PatternFinder, p: Point) bool {
        // TODO: evict the pharoahs from this evil pyramid of doom
        for (self.pattern) |layer, py| {
            for (layer) |row, pz| {
                for (row) |block_opt, px| {
                    if (block_opt) |block| {
                        const block_at = self.gen.at(
                            p.x + @intCast(i32, px),
                            p.y + @intCast(i32, py),
                            p.z + @intCast(i32, pz),
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

pub const Point = packed struct {
    x: i32,
    y: i32,
    z: i32,

    pub fn fromV(vec: std.meta.Vector(3, i32)) Point {
        return @bitCast(Point, vec);
    }
    pub fn v(self: Point) std.meta.Vector(3, i32) {
        return @bitCast([3]i32, self);
    }

    pub fn areaTo(a: Point, b: Point) u64 {
        return @reduce(.Mul, @intCast(std.meta.Vector(3, u64), b.v() - a.v()));
    }

    pub fn iterTo(a: Point, b: Point) Iterator {
        return .{ .pos = a, .start = a, .end = b };
    }

    pub const Iterator = struct {
        pos: Point,
        start: Point,
        end: Point,

        pub fn next(self: *Iterator) ?Point {
            if (self.pos.y >= self.end.y - 1) {
                self.pos.y = self.start.y;
                if (self.pos.x >= self.end.x - 1) {
                    self.pos.x = self.start.x;
                    if (self.pos.z >= self.end.z - 1) {
                        return null;
                    } else {
                        self.pos.z += 1;
                    }
                } else {
                    self.pos.x += 1;
                }
            } else {
                self.pos.y += 1;
            }
            return self.pos;
        }
    };
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

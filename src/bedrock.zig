const std = @import("std");

pub const PatternFinder = struct {
    gen: GradientGenerator,
    // Layers along Y, rows along Z, columns along X
    pattern: []const []const []const ?Block,

    pub fn search(
        self: PatternFinder,
        a: Point,
        b: Point,
        context: anytype,
        comptime resultFn: fn (@TypeOf(context), Point) void,
        comptime progressFn: ?fn (@TypeOf(context), count: u64, total: u64) void,
    ) void {
        const total: u64 = a.areaTo(b);
        var count: u64 = 0;
        var it = a.iterTo(b);
        while (it.next()) |p| {
            if (progressFn) |f| {
                if (count % 1000 == 0) {
                    f(context, count, total);
                }
                count += 1;
            }
            if (self.check(p)) {
                resultFn(context, p);
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
        return @reduce(
            .Mul,
            @intCast(
                std.meta.Vector(3, u64),
                b.v() - a.v(),
            ) + @splat(3, @as(u64, 1)),
        );
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

        var rand_at = self.rand.at(x, y, z);
        if (rand_at.nextf() < fac) {
            return self.lower;
        } else {
            return self.upper;
        }
    }

    fn normalize(x: f64, zero: f64, one: f64) f64 {
        return (x - zero) / (one - zero);
    }

    pub fn overworldFloor(seed: i64) GradientGenerator {
        var random = Random.initHash(seed, "minecraft:bedrock_floor", .xoroshiro);
        return GradientGenerator{
            .rand = PosRandom.init(&random),
            .lower = .bedrock,
            .upper = .other,
            .lower_y = -64,
            .upper_y = -59,
        };
    }

    pub fn netherFloor(seed: i64) GradientGenerator {
        var random = Random.initHash(seed, "minecraft:bedrock_floor", .legacy);
        return GradientGenerator{
            .rand = PosRandom.init(&random),
            .lower = .bedrock,
            .upper = .other,
            .lower_y = 0,
            .upper_y = 5,
        };
    }
    pub fn netherCeiling(seed: i64) GradientGenerator {
        var random = Random.initHash(seed, "minecraft:bedrock_roof", .legacy);
        return GradientGenerator{
            .rand = PosRandom.init(&random),
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

pub const RandomAlgorithm = enum { legacy, xoroshiro };
pub const Random = union(RandomAlgorithm) {
    legacy: u64,
    xoroshiro: [2]u64,

    const lmagic = 0x5DEECE66D;
    const lmask = ((1 << 48) - 1);

    pub fn init(seed: i64, algo: RandomAlgorithm) Random {
        return switch (algo) {
            .legacy => .{ .legacy = (@bitCast(u64, seed) ^ lmagic) & lmask },
            .xoroshiro => xoroshiroInit(seed128(seed)),
        };
    }

    const xmagic0: u64 = 0x6a09e667f3bcc909;
    const xmagic1: u64 = 0x9e3779b97f4a7c15;
    fn xoroshiroInit(seed: [2]u64) Random {
        if (seed[0] == 0 and seed[1] == 0) {
            return .{ .xoroshiro = .{ xmagic1, xmagic0 } };
        }
        return .{ .xoroshiro = seed };
    }
    fn seed128(seed: i64) [2]u64 {
        var lo = @bitCast(u64, seed) ^ xmagic0;
        var hi = lo +% xmagic1;
        return .{ mix(lo), mix(hi) };
    }
    fn mix(v: u64) u64 {
        var x = v;
        x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
        x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
        return x ^ (x >> 31);
    }

    pub fn initHash(seed: i64, str: []const u8, algo: RandomAlgorithm) Random {
        var seeder = init(seed, algo);
        switch (algo) {
            .legacy => return init(
                seeder.next64() ^ javaStringHash(str),
                .legacy,
            ),

            .xoroshiro => {
                var hash: [16]u8 = undefined;
                std.crypto.hash.Md5.hash(str, &hash, .{});

                const hseed = .{
                    std.mem.readIntBig(u64, hash[0..8]),
                    std.mem.readIntBig(u64, hash[8..]),
                };

                return xoroshiroInit(.{
                    hseed[0] ^ @bitCast(u64, seeder.next64()),
                    hseed[1] ^ @bitCast(u64, seeder.next64()),
                });
            },
        }
    }

    pub fn next(self: *Random, bits: u6) i32 {
        std.debug.assert(bits <= 32);
        switch (self.*) {
            .legacy => |*seed| {
                seed.* = (seed.* *% lmagic +% 0xb) & lmask;
                return @truncate(i32, @bitCast(i64, seed.*) >> (48 - bits));
            },

            .xoroshiro => {
                const shift = @intCast(u6, @as(u7, 64) - bits);
                const rbits = @bitCast(u64, self.next64());
                return @intCast(i32, rbits >> shift);
            },
        }
    }

    pub fn next64(self: *Random) i64 {
        switch (self.*) {
            .legacy => {
                const top: i64 = self.next(32);
                const bottom: i64 = self.next(32);
                const result = (top << 32) + bottom;
                return result;
            },

            .xoroshiro => |*s| {
                const v = std.math.rotl(u64, s[0] +% s[1], 17) +% s[0];
                s[1] ^= s[0];
                s[0] = std.math.rotl(u64, s[0], 49) ^ s[1] ^ (s[1] << 21);
                s[1] = std.math.rotl(u64, s[1], 28);
                return @bitCast(i64, v);
            },
        }
    }

    pub fn nextf(self: *Random) f32 {
        return @intToFloat(f32, self.next(24)) * 5.9604645e-8;
    }
};

pub const PosRandom = union(RandomAlgorithm) {
    legacy: i64,
    xoroshiro: [2]u64,

    pub fn init(world: *Random) PosRandom {
        return switch (world.*) {
            .legacy => .{ .legacy = world.next64() },
            .xoroshiro => .{
                .xoroshiro = .{
                    @bitCast(u64, world.next64()),
                    @bitCast(u64, world.next64()),
                },
            },
        };
    }

    pub fn at(self: PosRandom, x: i32, y: i32, z: i32) Random {
        var seed = @as(i64, x *% 3129871) ^ (@as(i64, z) *% 116129781) ^ y;
        seed = seed *% seed *% 42317861 +% seed *% 0xb;
        seed >>= 16;

        return switch (self) {
            .legacy => |rseed| Random.init(seed ^ rseed, .legacy),
            .xoroshiro => |rseed| Random.xoroshiroInit(.{
                @bitCast(u64, seed) ^ rseed[0], rseed[1],
            }),
        };
    }
};

// Unicode strings not supported because I'm lazy and Java is horrible
pub fn javaStringHash(str: []const u8) u32 {
    var hash: u32 = 0;
    for (str) |ch| {
        std.debug.assert(ch < 0x80);
        hash = 31 *% hash +% ch;
    }
    return hash;
}

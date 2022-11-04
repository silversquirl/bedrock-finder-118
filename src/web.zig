const std = @import("std");
const bedrock = @import("bedrock.zig");

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    consoleLog(msg.ptr, msg.len);
    asm volatile ("unreachable");
    unreachable;
}

export fn searchInit(
    world_seed: i64,
    gen_type: BedrockGenType,
    x0: i32,
    y0: i32,
    z0: i32,
    x1: i32,
    y1: i32,
    z1: i32,
) ?*AsyncSearcher {
    const gen = switch (gen_type) {
        .overworld_floor => bedrock.GradientGenerator.overworldFloor(world_seed),
        .nether_floor => bedrock.GradientGenerator.netherFloor(world_seed),
        .nether_ceiling => bedrock.GradientGenerator.netherCeiling(world_seed),
    };
    const finder = bedrock.PatternFinder{
        .gen = gen,
        .pattern = &.{&.{ // TODO: un-hardcode
            &.{ .bedrock, .bedrock, .bedrock },
            &.{ .bedrock, .bedrock, .bedrock },
            &.{ .bedrock, .bedrock, .bedrock },
        }},
    };

    return AsyncSearcher.init(
        std.heap.page_allocator,
        finder,
        .{ .x = x0, .y = y0, .z = z0 },
        .{ .x = x1, .y = y1, .z = z1 },
    ) catch null;
}

const BedrockGenType = enum(u8) {
    overworld_floor,
    nether_floor,
    nether_ceiling,
};

export fn searchStep(searcher: *AsyncSearcher) bool {
    return searcher.step();
}

export fn searchProgress(searcher: *AsyncSearcher) f64 {
    return searcher.progress;
}

export fn searchDeinit(searcher: *AsyncSearcher) void {
    searcher.deinit();
}

const AsyncSearcher = struct {
    allocator: std.mem.Allocator,
    progress: f64 = 0,

    done: bool = false,
    frame: anyframe = undefined,
    frame_storage: @Frame(search) = undefined,

    pub fn init(
        allocator: std.mem.Allocator,
        finder: bedrock.PatternFinder,
        a: bedrock.Point,
        b: bedrock.Point,
    ) !*AsyncSearcher {
        const self = try allocator.create(AsyncSearcher);
        self.* = .{ .allocator = allocator };
        self.frame_storage = async self.search(finder, a, b);
        return self;
    }
    pub fn deinit(self: *AsyncSearcher) void {
        self.allocator.destroy(self);
    }

    pub fn step(self: *AsyncSearcher) bool {
        if (!self.done) {
            resume self.frame;
        }
        return !self.done;
    }

    fn yield(self: *AsyncSearcher) void {
        suspend {
            self.frame = @frame();
        }
    }

    fn search(
        self: *AsyncSearcher,
        finder: bedrock.PatternFinder,
        a: bedrock.Point,
        b: bedrock.Point,
    ) void {
        self.yield();
        finder.search(a, b, self, reportResult, reportProgress);
        self.done = true;
    }

    pub fn reportResult(_: *AsyncSearcher, p: bedrock.Point) void {
        resultCallback(p.x, p.y, p.z);
    }
    pub fn reportProgress(self: *AsyncSearcher, completed: u64, total: u64) void {
        const resolution = 10_000;
        if (total == 0) {
            self.progress = 1;
        } else {
            const progress = resolution * completed / total;
            const fraction = @intToFloat(f64, progress) / resolution;
            self.progress = fraction;
        }
        self.yield();
    }
};

extern "bedrock" fn resultCallback(x: i32, y: i32, z: i32) void;
extern "bedrock" fn consoleLog(msg: [*]const u8, len: usize) void;

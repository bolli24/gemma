const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs.zig");

const ArrayList = std.ArrayList;

const Circle = struct { size: f32, color: rl.Color = rl.Color.red };
const Pos = ecs.component(rl.Vector2, "pos");
const Velocity = ecs.component(rl.Vector2, "velocity");
const Player = ecs.component(struct { size: f32 }, "player");

const screenWidth = 800;
const screenHeight = 450;
const player_speed = 200.0;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    rl.initWindow(screenWidth, screenHeight, "gemma");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(120); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // var balls = ArrayList(Ball).init(gpa.allocator());
    // defer balls.deinit();

    // const rand = prng.random();

    const base_speed = 200.0;

    var world = ecs.World.init(gpa.allocator());
    const rand = prng.random();

    const player = try world.create();
    try world.add_component(player, Pos{.{ .x = screenWidth * 0.5, .y = screenHeight * 0.5 }});
    try world.add_component(player, Player{.{ .size = 20.0 }});

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------

        if (rl.isKeyPressed(.space)) {
            const entity = try world.create();
            const dir = rl.Vector2.init(0, 1).rotate(rand.float(f32) * 2 * std.math.pi);
            const speed = std.math.lerp(base_speed / 2, base_speed * 2, rand.float(f32));

            const pos = rl.Vector2.init(
                std.math.lerp(40, screenWidth - 40, rand.float(f32)),
                std.math.lerp(40, screenHeight - 40, rand.float(f32)),
            );

            try world.add_component(entity, Pos{pos});
            try world.add_component(entity, Velocity{dir.scale(speed)});
            try world.add_component(entity, Circle{
                .size = rand.float(f32) * 20 + 3,
                .color = .init(rand.int(u8), rand.int(u8), rand.int(u8), 255),
            });
        }

        try world.runSystem(update_balls);
        try world.runSystem(player_control);
        try world.runSystem(player_kill);
        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);

        try world.runSystem(draw_circles);

        const player_pos: rl.Vector2 = (try world.components(Pos)).get(player).?[0];
        rl.drawRectangle(@intFromFloat(player_pos.x), @intFromFloat(player_pos.y), 20, 20, .red);

        //----------------------------------------------------------------------------------
    }
}

fn player_control(query: *ecs.Query(struct { Pos, Player })) void {
    if (query.single()) |item| {
        const pos = item[0];
        pos[0] = pos[0].add(getMovement().scale(rl.getFrameTime() * player_speed));
    }
}

fn player_kill(commands: *ecs.Commands, player_q: *ecs.Query(struct { Pos, Player }), balls: *ecs.Query(struct { ecs.Entity, Pos, Circle })) !void {
    const player = player_q.single() orelse return;
    var balls_iter = balls.iter();
    while (balls_iter.next()) |ball| {
        const entity, const pos, const circle = ball;

        if (intersect(player[0][0], player[1][0].size, pos[0], circle.size)) {
            circle.color = rl.Color.red;
            try commands.delete(entity);
        }
    }
}

fn intersect(rect_pos: rl.Vector2, rect_size: f32, circle_pos: rl.Vector2, circle_size: f32) bool {
    const half_size = rect_size * 0.5;
    const dist = rl.Vector2.init(@abs(circle_pos.x - rect_pos.x), @abs(circle_pos.y - rect_pos.y));
    if (dist.x > half_size + circle_size) return false;
    if (dist.y > half_size + circle_size) return false;

    if (dist.x <= half_size) return true;
    if (dist.y <= half_size) return true;

    const corner_dist_sq = (dist.x - half_size) * (dist.x - half_size) - (dist.y - half_size) * (dist.y - half_size);

    return corner_dist_sq <= circle_size * circle_size;
}

fn draw_circles(query: *ecs.Query(struct { Pos, Circle })) void {
    var iter = query.iter();
    while (iter.next()) |item| {
        const pos, const circle = item;
        rl.drawCircle(@intFromFloat(pos[0].x), @intFromFloat(pos[0].y), circle.size, circle.color);
    }
}

// fn collide_circles(query: *ecs.Query(struct { Pos, Circle }), wo)

fn update_balls(query: *ecs.Query(struct { Pos, Velocity, Circle })) void {
    var iter = query.iter();
    while (iter.next()) |item| {
        const pos, const velocity, const circle = item;
        pos[0] = pos[0].add(velocity[0].scale(rl.getFrameTime()));

        // @compileLog(item);

        if (pos[0].x >= @as(f32, @floatFromInt(screenWidth)) - circle.size or pos[0].x <= circle.size) {
            velocity[0].x = -velocity[0].x;
        }

        if (pos[0].y >= @as(f32, @floatFromInt(screenHeight)) - circle.size or pos[0].y <= circle.size) {
            velocity[0].y = -velocity[0].y;
        }
    }
}

fn getMovement() rl.Vector2 {
    var movement = rl.Vector2.zero();

    if (rl.isKeyDown(.s)) movement.y += 1;
    if (rl.isKeyDown(.w)) movement.y -= 1;
    if (rl.isKeyDown(.d)) movement.x += 1;
    if (rl.isKeyDown(.a)) movement.x -= 1;

    return movement.normalize();
}

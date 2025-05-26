const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs.zig");

const ArrayList = std.ArrayList;

const Circle = struct { size: f32, color: rl.Color = rl.Color.red };
const Pos = struct { rl.Vector2 };
const Velocity = struct { rl.Vector2 };

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "gemma");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(120); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // var balls = ArrayList(Ball).init(gpa.allocator());
    // defer balls.deinit();

    // const rand = prng.random();

    var player: rl.Vector2 = .{ .x = screenWidth * 0.5, .y = screenHeight * 0.5 };
    const player_speed = 200.0;
    const base_speed = 200.0;

    var world = ecs.World.init(gpa.allocator());
    const rand = prng.random();
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        player = player.add(getMovement().scale(rl.getFrameTime() * player_speed));

        if (rl.isKeyPressed(.space)) {
            const entity = try world.create();
            const dir = rl.Vector2.init(0, 1).rotate(rand.float(f32) * 2 * std.math.pi);
            const speed = std.math.lerp(base_speed / 2, base_speed * 2, rand.float(f32));

            const pos = rl.Vector2.init(
                std.math.lerp(40, screenWidth - 40, rand.float(f32)),
                std.math.lerp(40, screenHeight - 40, rand.float(f32)),
            );

            try world.add_component(entity, .{pos});
            try world.add_component(entity, .{dir.scale(speed)});
            try world.add_component(entity, Circle{
                .size = rand.float(f32) * 20 + 3,
                .color = .init(rand.int(u8), rand.int(u8), rand.int(u8), 255),
            });

            @compileLog(ecs.typeId(Pos));
            @compileLog(ecs.typeId(Velocity));
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);

        try world.runSystem(draw_circles);

        rl.drawRectangle(@intFromFloat(player.x), @intFromFloat(player.y), 20, 20, .red);

        //----------------------------------------------------------------------------------
    }
}

fn draw_circles(query: *ecs.Query(struct { Pos, Circle })) void {
    while (query.next()) |item| {
        const pos, const circle = item;
        rl.drawCircle(@intFromFloat(pos[0].x), @intFromFloat(pos[0].y), circle.size, circle.color);
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

const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs.zig");

const ArrayList = std.ArrayList;

const Ball = struct { pos: rl.Vector2, velocity: rl.Vector2, size: f32, color: rl.Color = rl.Color.red };

pub fn main() anyerror!void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};

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

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------

        player = player.add(getMovement().scale(rl.getFrameTime() * player_speed));

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);

        rl.drawRectangle(@intFromFloat(player.x), @intFromFloat(player.y), 20, 20, .red);

        //----------------------------------------------------------------------------------
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

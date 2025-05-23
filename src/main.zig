const std = @import("std");
const rl = @import("raylib");

pub fn main() anyerror!void {
    std.log.info("Hello world.", .{});
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var pos: rl.Vector2 = rl.Vector2.init(screenWidth / 2, screenHeight / 2);
    const base_speed = 200.0;
    const size = 20;
    var velocity = rl.Vector2.init(base_speed, base_speed);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------

        pos = pos.add(velocity.scale(rl.getFrameTime()));
        if (pos.x >= @as(f32, @floatFromInt(screenWidth - size)) or pos.x <= @as(f32, @floatFromInt(size))) {
            velocity.x = -velocity.x;
        }

        if (pos.y >= @as(f32, @floatFromInt(screenHeight - size)) or pos.y <= @as(f32, @floatFromInt(size))) {
            velocity.y = -velocity.y;
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);

        rl.drawCircle(@intFromFloat(pos.x), @intFromFloat(pos.y), size, rl.Color.red);
        //----------------------------------------------------------------------------------
    }
}

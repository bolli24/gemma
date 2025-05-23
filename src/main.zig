const std = @import("std");
const rl = @import("raylib");
const ArrayList = std.ArrayList;

const Ball = struct { pos: rl.Vector2, velocity: rl.Vector2, size: f32, color: rl.Color = rl.Color.red };

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    const base_speed = 200.0;

    var balls = ArrayList(Ball).init(gpa.allocator());
    defer balls.deinit();

    const rand = prng.random();

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------

        if (rl.isKeyPressed(.space)) {
            const dir = rl.Vector2.init(0, 1).rotate(rand.float(f32) * 2 * std.math.pi);
            const speed = std.math.lerp(base_speed / 2, base_speed * 2, rand.float(f32));
            try balls.append(Ball{
                .pos = rl.Vector2.init(
                    std.math.lerp(40, screenWidth - 40, rand.float(f32)),
                    std.math.lerp(40, screenHeight - 40, rand.float(f32)),
                ),
                .velocity = dir.scale(speed),
                .size = rand.float(f32) * 20 + 3,
                .color = .init(rand.int(u8), rand.int(u8), rand.int(u8), 255),
            });
        }

        for (balls.items) |*ball| {
            ball.pos = ball.pos.add(ball.velocity.scale(rl.getFrameTime()));
        }

        for (balls.items, 0..) |*ball, index| {
            if (ball.pos.x >= @as(f32, @floatFromInt(screenWidth)) - ball.size or ball.pos.x <= ball.size) {
                ball.velocity.x = -ball.velocity.x;
            }

            if (ball.pos.y >= @as(f32, @floatFromInt(screenHeight)) - ball.size or ball.pos.y <= ball.size) {
                ball.velocity.y = -ball.velocity.y;
            }

            for (balls.items[index + 1 ..]) |*other| {
                const overlap = (ball.size + other.size) - ball.pos.distance(other.pos);

                if (overlap < 0) continue;

                const difference = ball.pos.subtract(other.pos).normalize();
                ball.pos = ball.pos.add(difference.scale(0.5 * overlap));
                other.pos = other.pos.add(difference.scale(-0.5 * overlap));

                const plane = rl.Vector2.init(difference.x, -difference.y);

                ball.velocity = ball.velocity.reflect(plane);
                other.velocity = other.velocity.reflect(plane);
            }
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);
        for (balls.items) |*ball| {
            rl.drawCircle(
                @intFromFloat(ball.pos.x),
                @intFromFloat(ball.pos.y),
                ball.size,
                ball.color,
            );
        }
        //----------------------------------------------------------------------------------
    }
}

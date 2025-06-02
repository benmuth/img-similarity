const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    rl.initWindow(800, 1000, "hello world!");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const file_name: [:0]const u8 = "test-images/img.jpeg";
    const image = try rl.Image.init(file_name);
    const image_texture = try rl.loadTextureFromImage(image);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.blue);
        rl.drawTextureEx(image_texture, .{ .x = 0, .y = 0 }, 0, 0.35, rl.Color.ray_white);
    }
}

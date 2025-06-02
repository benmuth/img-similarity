const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    rl.initWindow(800, 600, "hello world!");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.blue);
    }

    const file_name: [:0]const u8 = "test-images/img.jpeg";
    const image = try rl.Image.init(file_name);
    std.debug.print("valid: {}\n", .{rl.isImageValid(image)});
}

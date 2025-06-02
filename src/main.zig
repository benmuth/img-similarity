const std = @import("std");
const rl = @import("raylib");

pub fn main() void {
    rl.initWindow(800, 600, "hello world!");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.blue);
    }
    std.debug.print("hello world!\n", .{});
}

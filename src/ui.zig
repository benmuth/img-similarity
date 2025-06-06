const std = @import("std");
const rl = @import("raylib");
const image = @import("image.zig");

pub const State = struct {
    image_idx: usize = 0,
    set_idx: usize = 0,

    images: [][]image.Image,

    pub fn init(images: [][]image.Image) State {
        return .{
            .images = images,
        };
    }
};

pub fn drawImageSet(images: []image.Image, x_offset: f32) void {
    for (images) |img| {
        rl.drawTextureEx(
            img.texture,
            .{ .x = img.x - x_offset, .y = 0 },
            0,
            img.scale,
            rl.Color.ray_white,
        );
    }
}
const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    rl.initWindow(1200, 800, "hello world!");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const dir_name = "test-images";

    const scale: f32 = 0.4;
    const images = try loadImagesFromDir(allocator, dir_name, scale);
    var state = State.init(images, scale);

    while (!rl.windowShouldClose()) {
        // update
        if (rl.isKeyPressed(rl.KeyboardKey.left)) {
            state.image_idx -|= 1;
        } else if (rl.isKeyPressed(rl.KeyboardKey.right)) {
            if (state.image_idx < state.images.len - 1) {
                state.image_idx += 1;
            }
        }

        const starting_x = state.images[state.image_idx].x;

        // draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.blue);
        for (state.images) |image| {
            std.debug.print("x: {d}\n", .{image.x});
            rl.drawTextureEx(image.texture, .{ .x = image.x - starting_x, .y = 0 }, 0, state.scale, rl.Color.ray_white);
        }
    }
}

fn loadImagesFromDir(allocator: std.mem.Allocator, dir_name: []const u8, scale: f32) ![]Image {
    var images = std.ArrayListUnmanaged(Image).empty;

    const dir = try std.fs.cwd().openDir(dir_name, .{ .iterate = true });
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var x: f32 = 0;
    while (try walker.next()) |entry| {
        const real_path = try entry.dir.realpathAlloc(allocator, entry.path);
        const real_path_z = try allocator.dupeZ(u8, real_path);
        std.debug.print("loading image from path: {s}\n", .{real_path_z});

        const rl_image = try rl.Image.init(real_path_z);
        if (rl.isImageValid(rl_image)) {
            const image = try Image.init(rl_image, x * scale);
            try images.append(allocator, image);
            x += @floatFromInt(rl_image.width);
        }
    }

    return try images.toOwnedSlice(allocator);
}

const State = struct {
    image_idx: usize = 0,
    x_offset: u32 = 0,
    scale: f32 = 1,

    images: []Image,

    fn init(images: []Image, scale: f32) State {
        return .{
            .images = images,
            .scale = scale,
        };
    }
};

const Image = struct {
    rl_image: rl.Image,
    texture: rl.Texture,
    x: f32,

    fn init(image: rl.Image, x: f32) !Image {
        return .{
            .rl_image = image,
            .texture = try rl.loadTextureFromImage(image),
            .x = x,
        };
    }
};

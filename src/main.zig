const std = @import("std");
const rl = @import("raylib");

const width = 1200;
const height = 800;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    rl.initWindow(width, height, "Similar images");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const paths_1 = try pathsFromDir(allocator, "test-images-1");
    const paths_2 = try pathsFromDir(allocator, "test-images-2");

    const image_set_1 = try imageSetFromPaths(allocator, paths_1);
    const image_set_1_resize = try reduceSize(allocator, image_set_1);
    const image_set_2 = try imageSetFromPaths(allocator, paths_2);
    const image_set_2_resize = try reduceSize(allocator, image_set_2);
    var images: [2][]Image = .{ image_set_1_resize, image_set_2_resize };
    // const new_images = try hashImages(images);
    var state = State.init(images[0..]);

    while (!rl.windowShouldClose()) {
        // update
        if (rl.isKeyPressed(rl.KeyboardKey.left)) {
            state.image_idx -|= 1;
        } else if (rl.isKeyPressed(rl.KeyboardKey.right)) {
            if (state.image_idx < state.images[0].len - 1) {
                state.image_idx += 1;
            }
        } else if (rl.isKeyPressed(rl.KeyboardKey.up)) {
            state.set_idx -|= 1;
            if (state.image_idx >= state.images[state.set_idx].len) {
                state.image_idx = state.images[state.set_idx].len - 1;
            }
        } else if (rl.isKeyPressed(rl.KeyboardKey.down)) {
            if (state.set_idx < state.images.len - 1) {
                state.set_idx += 1;
                if (state.image_idx >= state.images[state.set_idx].len) {
                    state.image_idx = state.images[state.set_idx].len - 1;
                }
            }
        }

        // draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.blue);

        drawImageSet(state.images[state.set_idx], state.images[state.set_idx][state.image_idx].x);
    }
}

const State = struct {
    image_idx: usize = 0,
    set_idx: usize = 0,

    x_offset: u32 = 0,

    images: [][]Image,

    fn init(images: [][]Image) State {
        return .{
            .images = images,
        };
    }
};

/// An image to be displayed in the window
const Image = struct {
    // the underlying Raylib image data
    rl_image: rl.Image,

    // the path to the image
    path: []const u8,

    // the x offset from the left edge of the first image
    x: f32,

    // the image as a Raylib texture
    texture: rl.Texture,

    // the amount each image should be scaled by to have it fit in the window
    scale: f32,

    fn init(image: rl.Image, path: []const u8, x: f32) !Image {
        return .{
            .rl_image = image,
            .path = path,
            .x = x,
            .texture = try rl.loadTextureFromImage(image),
            .scale = calcImageScale(image),
        };
    }
};

fn calcImageScale(image: rl.Image) f32 {
    var scale: f32 = undefined;
    if (image.width > image.height) {
        // scale to width
        if (image.width > width) {
            scale = width / @as(f32, @floatFromInt(image.width));
        }
    } else {
        // scale to height
        if (image.height > height) {
            scale = height / @as(f32, @floatFromInt(image.height));
        }
    }
    return scale;
}

fn drawImageSet(images: []Image, x_offset: f32) void {
    for (images) |image| {
        rl.drawTextureEx(
            image.texture,
            .{ .x = image.x - x_offset, .y = 0 },
            0,
            image.scale,
            rl.Color.ray_white,
        );
    }
}

fn pathsFromDir(allocator: std.mem.Allocator, dir_name: []const u8) ![][:0]const u8 {
    var paths = std.ArrayListUnmanaged([:0]const u8).empty;

    const dir = try std.fs.cwd().openDir(dir_name, .{ .iterate = true });
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const real_path = try entry.dir.realpathAlloc(allocator, entry.path);
        const real_path_z = try allocator.dupeZ(u8, real_path);
        try paths.append(allocator, real_path_z);
    }
    return paths.toOwnedSlice(allocator);
}

fn imageSetFromPaths(allocator: std.mem.Allocator, paths: [][:0]const u8) ![]Image {
    var images = std.ArrayListUnmanaged(Image).empty;

    var initial_x: f32 = 0;
    for (paths) |path| {
        std.debug.print("loading image from path: {s}\n", .{path});

        const rl_image = try rl.Image.init(path);
        if (rl.isImageValid(rl_image)) {
            const image = try Image.init(rl_image, path, initial_x);
            try images.append(allocator, image);
            initial_x += @as(f32, @floatFromInt(rl_image.width)) * image.scale;
        } else {
            std.debug.print("invalid path: {s}\n", .{path});
        }
    }

    return try images.toOwnedSlice(allocator);
}

//
// image hashing
//

// a hash steps
// - [ ]reduce size to an 8x8 square
// - [ ]convert picture to grayscale
// - [ ]compute mean value of the 64 colors
// - [ ]set bits of a 64-bit integer based on whether the pixel is above or below the mean

fn reduceSize(allocator: std.mem.Allocator, images: []Image) ![]Image {
    const images_copy = try allocator.dupe(Image, images);
    std.debug.print("before: \n", .{});
    printMetadata(images_copy);
    for (images_copy) |*image| {
        image.rl_image.resize(8, 8);
        // const pixels: *[8 * 8 * 3]u8 = @ptrCast(image.rl_image.data);
        // var new_pixels: [400 * 400 * 3]u8 = undefined;
        // std.debug.print("pixels: {d}\n", .{pixels});
        // scaleImage8x8To400x400(pixels, &new_pixels);
        // std.debug.print("new_pixels: {d}\n", .{new_pixels});
        // rl.updateTexture(image.texture, @ptrCast(&new_pixels));
        // /
        image.rl_image.resizeNN(400, 400);
        image.texture = try rl.loadTextureFromImage(image.rl_image);
    }

    // for (images_copy) |*image| {

    // }

    std.debug.print("after: \n", .{});
    printMetadata(images_copy);
    return images_copy;
}

fn printMetadata(images: []Image) void {
    for (images) |image| {
        std.debug.print("width: {d}, height: {d}\ntexture_width: {d}, texture_height: {d}\n", .{ image.rl_image.width, image.rl_image.height, image.texture.width, image.texture.height });
    }
}

// const HashResult = struct {};

// fn hashImages(allocator: std.mem.Allocator, images: []Image) ![]Image {
//     for (images) |*image| {
//         // const image_width = image.rl_image.width;
//         // const image_height = image.rl_image.height;

//         image.rl_image.resize(8, 8);
//         var output: [400 * 400 * 3]u8 = undefined;
//         scaleImage8x8To400x400(@ptrCast(image.rl_image.data), &output);

//         image.texture = try rl.loadTextureFromImage(image.rl_image);
//         rl.updateTexture(image.texture, &output);
//         image.scale = calcImageScale(image.rl_image);
//         std.debug.print("image: {}\n", .{image});
//     }

//     return images;
// }

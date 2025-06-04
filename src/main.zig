const std = @import("std");
const rl = @import("raylib");

const width = 1200;
const height = 800;

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    rl.initWindow(width, height, "Similar images");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const paths_1 = pathsFromDir(allocator, "test-images-1");
    const paths_2 = pathsFromDir(allocator, "test-images-2");

    const image_set_1 = imageSetFromPaths(allocator, paths_1);
    const image_set_2 = imageSetFromPaths(allocator, paths_2);

    const image_set_1_resize = reduceSize(allocator, image_set_1);
    const image_set_2_resize = reduceSize(allocator, image_set_2);

    std.debug.print("image: {any}\n", .{image_set_2_resize});

    var images: [2][]Image = .{ image_set_1_resize, image_set_2_resize };
    // var images: [2][]Image = .{ image_set_1, image_set_2 };
    // const new_images = hashImages(images);
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

    fn init(image: rl.Image, path: []const u8, x: f32) Image {
        return .{
            .rl_image = image,
            .path = path,
            .x = x,
            .texture = rl.loadTextureFromImage(image) catch |err|
                fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ path, @errorName(err) }),
            .scale = calcImageScale(image),
        };
    }
};

fn calcImageScale(image: rl.Image) f32 {
    var scale: f32 = 1;
    if (image.width > image.height) {
        // scale to width
        if (image.width != width) {
            scale = width / @as(f32, @floatFromInt(image.width));
        }
    } else {
        // scale to height
        if (image.height != height) {
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

fn pathsFromDir(allocator: std.mem.Allocator, dir_name: []const u8) [][:0]const u8 {
    var paths = std.ArrayListUnmanaged([:0]const u8).empty;

    const dir = std.fs.cwd().openDir(dir_name, .{ .iterate = true }) catch |err|
        fatal(.bad_file, "Failed to open dir {s}: {s}\n", .{ dir_name, @errorName(err) });
    var walker = dir.walk(allocator) catch |err|
        fatal(.bad_file, "Failed to walk dir {s}: {s}\n", .{ dir_name, @errorName(err) });
    defer walker.deinit();

    while (walker.next() catch |err| fatal(
        .bad_file,
        "Failed to iterate through dir {s}: {s}",
        .{ dir_name, @errorName(err) },
    )) |entry| {
        const real_path = entry.dir.realpathAlloc(allocator, entry.path) catch |err|
            fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});
        const real_path_z = allocator.dupeZ(u8, real_path) catch |err|
            fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});
        paths.append(allocator, real_path_z) catch |err|
            fatal(.no_space_left, "Faild to append path {s} to list: {s}", .{ real_path_z, @errorName(err) });
    }
    const paths_slice = paths.toOwnedSlice(allocator) catch |err|
        fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});
    return paths_slice;
}

fn imageSetFromPaths(allocator: std.mem.Allocator, paths: [][:0]const u8) []Image {
    var images = std.ArrayListUnmanaged(Image).empty;

    var initial_x: f32 = 0;
    for (paths) |path| {
        std.debug.print("loading image from path: {s}\n", .{path});

        const rl_image = rl.Image.init(path) catch |err|
            fatal(.bad_file, "Failed to load image {s}: {s}", .{ path, @errorName(err) });
        if (rl.isImageValid(rl_image)) {
            const image = Image.init(rl_image, path, initial_x);
            images.append(allocator, image) catch |err|
                fatal(.no_space_left, "Failed to append image to list: {s}", .{@errorName(err)});
            initial_x += @as(f32, @floatFromInt(rl_image.width)) * image.scale;
        } else {
            std.debug.print("invalid path: {s}\n", .{path});
        }
    }

    return images.toOwnedSlice(allocator) catch |err|
        fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});
}

// updates the images' x offset based on their new size
fn updateImages(allocator: std.mem.Allocator, images: []Image) []Image {
    const new_images = allocator.dupe(Image, images) catch |err|
        fatal(.no_space_left, "Failed to duplicate images: {s}", .{@errorName(err)});

    var x_offset: f32 = 0;
    for (new_images) |*image| {
        image.x = x_offset;
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
        var scale = calcImageScale(image.rl_image);
        if (scale < 1e-6) {
            std.debug.print("TOO SMALL!\n", .{});
            var copy = rl.imageCopy(image.rl_image);
            copy.resizeNN(height, height);
            // std.debug.print("copy size: {d} {d}", .{ width, height });
            scale = calcImageScale(copy);
            std.debug.print("new scale: {d}", .{scale});
            // std.debug.print("img data: {any}\n", .{copy});
            image.texture = rl.loadTextureFromImage(copy) catch |err|
                fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
        }
        image.scale = scale;
        std.debug.print("size: {d}, scale: {d}\n", .{ image.rl_image.width, scale });
        x_offset += (@as(f32, @floatFromInt(image.texture.width)) * image.scale);
    }
    return new_images;
}

//
// image hashing
//

// aHash steps
// - [ ]reduce size to an 8x8 square
// - [ ]convert picture to grayscale
// - [ ]compute mean value of the 64 colors
// - [ ]set bits of a 64-bit integer based on whether the pixel is above or below the mean

fn reduceSize(allocator: std.mem.Allocator, images: []Image) []Image {
    const images_copy = allocator.dupe(Image, images) catch |err|
        fatal(.no_space_left, "Failed to duplicate images: {s}", .{@errorName(err)});
    std.debug.print("before: \n", .{});
    printMetadata(images_copy);
    for (images_copy) |*image| {
        image.rl_image.resize(8, 8);
        // image.rl_image.resizeNN(400, 400);
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
    }

    std.debug.print("after: \n", .{});
    printMetadata(images_copy);

    const updated_images = updateImages(allocator, images_copy);

    return updated_images;
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
//

const FatalReason = enum(u8) {
    cli = 1,
    no_space_left = 2,
    bad_file = 3,
    unknown_command = 4,

    fn exit_status(reason: FatalReason) u8 {
        return @intFromEnum(reason);
    }
};

// taken from TigerBeetle (https://ziggit.dev/t/handling-out-of-memory-errors/10224/4)
pub fn fatal(reason: FatalReason, comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    const status = reason.exit_status();
    std.debug.assert(status != 0);
    std.process.exit(status);
}

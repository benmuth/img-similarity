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

    const paths_1 = pathsFromDir(allocator, "test-images-1");

    var images = std.ArrayListUnmanaged([]Image).empty;

    try images.append(allocator, imageSetFromPaths(allocator, paths_1));
    try images.append(allocator, applyStep(allocator, images.items[0], reduceSize));
    try images.append(allocator, applyStep(allocator, images.items[1], convertToGrayscale));
    try images.append(allocator, applyStep(allocator, images.items[2], computeBits));

    var state = State.init(images.items);

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

    return paths.toOwnedSlice(allocator) catch |err|
        fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});
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
            fatal(.bad_file, "invalid path: {s}", .{path});
        }
    }

    return images.toOwnedSlice(allocator) catch |err|
        fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});
}

// updates the images' display attributes
fn updateImages(images: []Image) void {
    var x_offset: f32 = 0;
    for (images) |*image| {
        image.x = x_offset;
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });

        image.scale = calcImageScale(image.rl_image);
        x_offset += (@as(f32, @floatFromInt(image.texture.width)) * image.scale);
    }
}

// creates a copy of the image set and applies a transformation, to be displayed
fn applyStep(allocator: std.mem.Allocator, images: []Image, transform: *const fn ([]Image) void) []Image {
    const copy = allocator.dupe(Image, images) catch |err|
        fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});

    transform(copy);
    return copy;
}

//
// image hashing
//

// aHash steps
// - [x]reduce size to an 8x8 square
// - [x]convert picture to grayscale
// - [ ]set bits of a 64-bit integer based on whether the pixel is above or below the mean

fn reduceSize(images: []Image) void {
    for (images) |*image| {
        image.rl_image.resize(8, 8);
        // image.rl_image.resizeNN(400, 400);
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
    }

    updateImages(images);
}

fn convertToGrayscale(images: []Image) void {
    for (images) |*image| {
        image.rl_image.grayscale();
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
    }
}

fn computeBits(grayscale_images: []Image) void {
    for (grayscale_images) |*grayscale_image| {
        const num_pixels: usize = @intCast(grayscale_image.rl_image.width * grayscale_image.rl_image.height);
        const data: []u8 = @as([*]u8, @ptrCast(grayscale_image.rl_image.data))[0..num_pixels];

        var sum: u32 = 0;
        for (data) |byte| sum += byte;
        const mean: f32 = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(num_pixels));

        var new_data: [4096]u8 = undefined;
        for (data, 0..) |byte, i|
            new_data[i] = if (@as(f32, @floatFromInt(byte)) > mean) 255 else 0;

        const new_image: rl.Image = .{
            .data = @ptrCast(new_data[0..num_pixels].ptr),
            .width = grayscale_image.rl_image.width,
            .height = grayscale_image.rl_image.height,
            .mipmaps = grayscale_image.rl_image.mipmaps,
            .format = grayscale_image.rl_image.format,
        };

        grayscale_image.rl_image = new_image;
        grayscale_image.texture = rl.loadTextureFromImage(grayscale_image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ grayscale_image.path, @errorName(err) });
    }
}

fn printMetadata(images: []Image) void {
    for (images) |image| {
        std.debug.print("width: {d}, height: {d}\ntexture_width: {d}, texture_height: {d}\nformat: {s}\n", .{ image.rl_image.width, image.rl_image.height, image.texture.width, image.texture.height, @tagName(image.rl_image.format) });
    }
}

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

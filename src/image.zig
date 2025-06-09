const std = @import("std");
const rl = @import("raylib");
const fatal = @import("main.zig").fatal;

const width = 1200;
const height = 800;

/// An image to be displayed in the window
pub const Image = struct {
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

    pub fn init(image: *rl.Image, path: []const u8, x: f32) Image {
        // resize before loading texture
        const scale = calcImageScale(image.*);
        const new_width: f32 = @as(f32, @floatFromInt(image.width)) * scale;
        const new_height: f32 = @as(f32, @floatFromInt(image.height)) * scale;
        image.resizeNN(@intFromFloat(new_width), @intFromFloat(new_height));

        return .{
            .rl_image = image.*,
            .path = path,
            .x = x,
            .texture = rl.loadTextureFromImage(image.*) catch |err|
                fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ path, @errorName(err) }),
            .scale = 1,
        };
    }
};

pub fn calcImageScale(image: rl.Image) f32 {
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

pub fn pathsFromDir(allocator: std.mem.Allocator, dir_name: []const u8) [][:0]const u8 {
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

        if (!supportedFormat(real_path)) {
            std.log.info("Unsupported format: skipping {s}", .{real_path});
            continue;
        }

        const real_path_z = allocator.dupeZ(u8, real_path) catch |err|
            fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});

        paths.append(allocator, real_path_z) catch |err|
            fatal(.no_space_left, "Faild to append path {s} to list: {s}", .{ real_path_z, @errorName(err) });
    }

    if (paths.items.len == 0) {
        fatal(.bad_file, "No valid paths in {s}", .{dir_name});
    }

    return paths.toOwnedSlice(allocator) catch |err|
        fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});
}

pub fn imageSetFromPaths(allocator: std.mem.Allocator, paths: [][:0]const u8) []Image {
    var images = std.ArrayListUnmanaged(Image).empty;

    var initial_x: f32 = 0;
    for (paths) |path| {
        std.debug.print("loading image from path: {s}\n", .{path});

        var rl_image = rl.Image.init(path) catch |err|
            fatal(.bad_file, "Failed to load image {s}: {s}", .{ path, @errorName(err) });

        if (rl.isImageValid(rl_image)) {
            const image = Image.init(&rl_image, path, initial_x);
            images.append(allocator, image) catch |err|
                fatal(.no_space_left, "Failed to append image to list: {s}", .{@errorName(err)});

            initial_x += @as(f32, @floatFromInt(image.rl_image.width));
        } else {
            fatal(.bad_file, "invalid path: {s}", .{path});
        }
    }

    return images.toOwnedSlice(allocator) catch |err|
        fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});
}

// updates the images' attributes for display
pub fn updateImages(images: []Image) void {
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
pub fn applyStep(allocator: std.mem.Allocator, images: []Image, transform: *const fn ([]Image) void) []Image {
    const copy = allocator.alloc(Image, images.len) catch |err|
        fatal(.no_space_left, "Failed to allocate: {s}", .{@errorName(err)});

    // Deep copy each image
    for (images, 0..) |img, i| {
        // Copy the image struct
        copy[i] = img;
        copy[i].rl_image = img.rl_image.copy();

        // Create a new texture from the copied image
        copy[i].texture = rl.loadTextureFromImage(copy[i].rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ copy[i].path, @errorName(err) });
    }

    transform(copy);
    updateImages(copy);
    return copy;
}

// Core hash computation function - works with raw grayscale image data
fn computeHashFromData(pixel_data: []const u8) u64 {
    const bit: u64 = 1;
    const num_pixels = 64;
    std.debug.assert(pixel_data.len == num_pixels);

    var sum: u32 = 0;
    for (pixel_data) |byte| sum += byte;
    const mean: f32 = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(num_pixels));

    var hash: u64 = 0;
    for (pixel_data, 0..num_pixels) |byte, j|
        hash |= if (@as(f32, @floatFromInt(byte)) > mean) bit << @as(u6, @truncate(j)) else 0;

    return hash;
}

// Compute hashes
pub fn computeImageHashes(allocator: std.mem.Allocator, paths: [][:0]const u8) []u64 {
    // Load images without creating textures
    var rl_images = std.ArrayListUnmanaged(rl.Image).empty;
    defer {
        for (rl_images.items) |img| {
            img.unload();
        }
        rl_images.deinit(allocator);
    }
    // Load all images
    for (paths) |path| {
        const rl_image = rl.Image.init(path) catch |err|
            fatal(.bad_file, "Failed to load image {s}: {s}", .{ path, @errorName(err) });

        if (!rl.isImageValid(rl_image)) {
            fatal(.bad_file, "invalid path: {s}", .{path});
        }

        rl_images.append(allocator, rl_image) catch |err|
            fatal(.no_space_left, "Failed to append image to list: {s}", .{@errorName(err)});
    }

    // Reduce size to 8x8
    for (rl_images.items) |*img| {
        img.resizeNN(8, 8);
    }

    // Convert to grayscale
    for (rl_images.items) |*img| {
        img.grayscale();
    }

    // Compute hashes from the processed images
    var hashes = allocator.alloc(u64, rl_images.items.len) catch |err|
        fatal(.no_space_left, "Failed to append image to list: {s}", .{@errorName(err)});
    const num_pixels = 64;

    for (rl_images.items, 0..) |*img, i| {
        std.debug.assert(img.width * img.height == num_pixels);
        const data: []u8 = @as([*]u8, @ptrCast(img.data))[0..num_pixels];
        hashes[i] = computeHashFromData(data);
    }

    return hashes;
}

// Compute hashes as a step for transform mode
pub fn computeHashes(grayscale_images: []Image, hashes: []u64) []u64 {
    const num_pixels = 64;
    for (grayscale_images, 0..) |*grayscale_image, i| {
        std.debug.assert(grayscale_image.rl_image.width * grayscale_image.rl_image.height == num_pixels);
        const data: []u8 = @as([*]u8, @ptrCast(grayscale_image.rl_image.data))[0..num_pixels];
        hashes[i] = computeHashFromData(data);
    }

    return hashes;
}

pub fn imageSetsTransformation(allocator: std.mem.Allocator, directory: []const u8) [][]Image {
    const paths = pathsFromDir(allocator, directory);
    const images = imageSetFromPaths(allocator, paths);

    var image_sets = std.ArrayListUnmanaged([]Image).empty;

    image_sets.append(allocator, images) catch |err|
        fatal(.no_space_left, "Failed to append image set to list: {s}", .{@errorName(err)});

    image_sets.append(
        allocator,
        applyStep(allocator, image_sets.items[0], reduceTo8x8),
    ) catch |err|
        fatal(.no_space_left, "Failed to append image set to list: {s}", .{@errorName(err)});

    image_sets.append(
        allocator,
        applyStep(allocator, image_sets.items[1], convertToGrayscale),
    ) catch |err|
        fatal(.no_space_left, "Failed to append image set to list: {s}", .{@errorName(err)});

    image_sets.append(
        allocator,
        applyStep(allocator, image_sets.items[2], makeHashImages),
    ) catch |err|
        fatal(.no_space_left, "Failed to append image set to list: {s}", .{@errorName(err)});

    return image_sets.toOwnedSlice(allocator) catch |err|
        fatal(.no_space_left, "Failed to allocate list: {s}", .{@errorName(err)});
}

pub fn imageSetsBySimilarity(allocator: std.mem.Allocator, directory: []const u8) [][]Image {
    const paths = pathsFromDir(allocator, directory);
    const hashes = computeImageHashes(allocator, paths);

    // NOTE: look into gray code sorting to avoid O(n^2) complexity. Maybe reserve it for large
    // directories. Need to do measurements.

    const hammingThreshold = 3;

    var path_groups = std.ArrayListUnmanaged([][:0]const u8).empty;
    var used = allocator.alloc(bool, hashes.len) catch |err|
        fatal(.no_space_left, "Failed to allocate list: {s}", .{@errorName(err)});
    for (0..used.len) |i| used[i] = false;

    for (hashes, 0..) |hash_1, i| {
        if (used[i]) continue;

        var path_group = std.ArrayListUnmanaged([:0]const u8).empty;
        path_group.append(allocator, paths[i]) catch |err|
            fatal(.no_space_left, "Failed to append path to list: {s}", .{@errorName(err)});

        used[i] = true;

        for (hashes[1..], 1..hashes.len) |hash_2, j| {
            if (used[j]) continue;

            if (@popCount(hash_1 ^ hash_2) < hammingThreshold) {
                used[j] = true;

                path_group.append(allocator, paths[j]) catch |err|
                    fatal(.no_space_left, "Failed to append path to list: {s}", .{@errorName(err)});
            }
        }
        path_groups.append(allocator, path_group.items) catch |err|
            fatal(.no_space_left, "Failed to append path to list: {s}", .{@errorName(err)});
    }

    var image_sets = std.ArrayListUnmanaged([]Image).empty;
    for (path_groups.items) |path_group| {
        if (path_group.len < 2) continue; // only keep sets with duplicates
        const image_set = imageSetFromPaths(allocator, path_group);
        image_sets.append(allocator, image_set) catch |err|
            fatal(.no_space_left, "Failed to append image set to list: {s}", .{@errorName(err)});
    }

    return image_sets.toOwnedSlice(allocator) catch |err|
        fatal(.no_space_left, "Failed to allocate list: {s}", .{@errorName(err)});
}

//
// Image transformation functions for GUI pipeline
//

pub fn reduceTo8x8(images: []Image) void {
    for (images) |*image| {
        image.rl_image.resizeNN(8, 8);
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
    }
}

pub fn convertToGrayscale(images: []Image) void {
    for (images) |*image| {
        image.rl_image.grayscale();
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
    }
}

pub fn makeHashImages(grayscale_images: []Image) void {
    var hashes: [128]u64 = undefined;
    const new_hashes = computeHashes(grayscale_images, hashes[0..grayscale_images.len]);
    const num_pixels = 64;
    const bit: u64 = 1;
    for (new_hashes, 0..) |hash, i| {
        var grayscale_image = &grayscale_images[i];
        const data: []u8 = @as([*]u8, @ptrCast(grayscale_image.rl_image.data))[0..num_pixels];
        for (0..num_pixels) |j| {
            data[j] = if (((bit << @as(u6, @truncate(j))) & hash) > 0) 255 else 0;
        }

        grayscale_image.texture = rl.loadTextureFromImage(grayscale_image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ grayscale_image.path, @errorName(err) });
    }
}

pub fn printMetadata(images: []Image) void {
    for (images) |image| {
        std.debug.print("width: {d}, height: {d}\ntexture_width: {d}, texture_height: {d}\nformat: {s}\n", .{ image.rl_image.width, image.rl_image.height, image.texture.width, image.texture.height, @tagName(image.rl_image.format) });
    }
}

pub fn supportedFormat(path: []u8) bool {
    const ext_start = std.mem.lastIndexOfScalar(u8, path, '.') orelse return false;
    const lower_extension = std.ascii.lowerString(path[ext_start + 1 ..], path[ext_start + 1 ..]);

    const supported_img_formats: [10][]const u8 = .{
        "png",
        "bmp",
        "tga",
        "jpg",
        "jpeg",
        "gif",
        "pic",
        "hdr",
        "pnm",
        "psd",
    };

    for (supported_img_formats) |format| {
        if (std.mem.eql(u8, lower_extension, format)) {
            return true;
        }
    }

    return false;
}

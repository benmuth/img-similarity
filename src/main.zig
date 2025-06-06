const std = @import("std");
const rl = @import("raylib");

const width = 1200;
const height = 800;

const CliMode = enum {
    gui,
    show_steps,
    fast,
};

const CliArgs = struct {
    mode: CliMode = .gui,
    directory: []const u8 = "test-images-1",
    help: bool = false,
};

fn parseArgs(allocator: std.mem.Allocator) !CliArgs {
    var args = CliArgs{};
    var arg_iter = std.process.args();
    _ = arg_iter.skip(); // skip program name

    while (arg_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            args.help = true;
        } else if (std.mem.eql(u8, arg, "--show-steps") or std.mem.eql(u8, arg, "-s")) {
            args.mode = .show_steps;
        } else if (std.mem.eql(u8, arg, "--fast") or std.mem.eql(u8, arg, "-f")) {
            args.mode = .fast;
        } else if (std.mem.eql(u8, arg, "--dir") or std.mem.eql(u8, arg, "-d")) {
            if (arg_iter.next()) |dir_path| {
                args.directory = try allocator.dupe(u8, dir_path);
            } else {
                fatal(.cli, "Missing directory path after {s}", .{arg});
            }
        } else {
            fatal(.cli, "Unknown argument: {s}", .{arg});
        }
    }

    return args;
}

fn printHelp() void {
    std.debug.print(
        \\Usage: img-similarity [OPTIONS]
        \\
        \\Options:
        \\  -d, --dir <PATH>     Directory containing images to process (default: test-images-1)
        \\  -s, --show-steps     Show transformation steps using GUI (for debugging)
        \\  -f, --fast           Fast hashing without GUI display (for speed)
        \\  -h, --help           Show this help message
        \\
        \\Examples:
        \\  img-similarity                          # GUI mode (default)
        \\  img-similarity --fast --dir ./photos   # Fast CLI hashing
        \\  img-similarity --show-steps             # GUI with current directory
        \\
    , .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = parseArgs(allocator) catch |err| {
        fatal(.cli, "Failed to parse arguments: {s}", .{@errorName(err)});
    };

    if (args.help) {
        printHelp();
        return;
    }

    switch (args.mode) {
        .gui => try runGuiMode(allocator, args.directory),
        .show_steps => try runShowStepsMode(allocator, args.directory),
        .fast => try runFastMode(allocator, args.directory),
    }
}

fn runGuiMode(allocator: std.mem.Allocator, directory: []const u8) !void {
    std.debug.print("running GUI for directory: {s}\n", .{directory});

    rl.initWindow(width, height, "Similar images");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const paths = pathsFromDir(allocator, directory);
    if (paths.len == 0) {
        fatal(.bad_file, "No valid paths in {s}", .{directory});
    }

    const images = imageSetFromPaths(allocator, paths);
    fitToWindow(images);

    var image_sets = std.ArrayListUnmanaged([]Image).empty;
    try image_sets.append(allocator, images);
    try image_sets.append(allocator, applyStep(allocator, image_sets.items[0], reduceSize));
    try image_sets.append(allocator, applyStep(allocator, image_sets.items[1], convertToGrayscale));
    try image_sets.append(allocator, applyStep(allocator, image_sets.items[2], makeHashImages));

    var state = State.init(image_sets.items);

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

fn runShowStepsMode(allocator: std.mem.Allocator, directory: []const u8) !void {
    // Same as GUI mode - shows transformations with Raylib
    try runGuiMode(allocator, directory);
}

fn runFastMode(allocator: std.mem.Allocator, directory: []const u8) !void {
    const paths = pathsFromDir(allocator, directory);
    if (paths.len == 0) {
        fatal(.bad_file, "No valid paths in {s}", .{directory});
    }

    const hashes = try computeImageHashes(allocator, paths);

    for (paths, hashes) |path, hash| {
        std.debug.print("{s}: {x:0>16}\n", .{ path, hash });
    }
}

fn computeImageHashes(allocator: std.mem.Allocator, paths: [][:0]const u8) ![]u64 {
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

        try rl_images.append(allocator, rl_image);
    }

    // Apply transformations in sequence (same as GUI pipeline)
    // Step 1: Reduce size to 8x8
    for (rl_images.items) |*img| {
        img.resizeNN(8, 8);
    }

    // Step 2: Convert to grayscale
    for (rl_images.items) |*img| {
        img.grayscale();
    }

    // Step 3: Compute hashes from the processed images
    var hashes = try allocator.alloc(u64, rl_images.items.len);
    const bit: u64 = 1;
    const num_pixels = 64;

    for (rl_images.items, 0..) |*img, i| {
        std.debug.assert(img.width * img.height == num_pixels);
        const data: []u8 = @as([*]u8, @ptrCast(img.data))[0..num_pixels];

        var sum: u32 = 0;
        for (data) |byte| sum += byte;
        const mean: f32 = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(num_pixels));

        hashes[i] = 0;
        for (data, 0..num_pixels) |byte, j|
            hashes[i] |= if (@as(f32, @floatFromInt(byte)) > mean) bit << @as(u6, @truncate(j)) else 0;
    }

    return hashes;
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

        if (!supportedFormat(real_path)) {
            std.log.info("Unsupported format: skipping {s}", .{real_path});
            continue;
        }

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

fn fitToWindow(images: []Image) void {
    for (images) |*image| {
        const new_width: f32 = @as(f32, @floatFromInt(image.rl_image.width)) * image.scale;
        const new_height: f32 = @as(f32, @floatFromInt(image.rl_image.height)) * image.scale;
        image.rl_image.resizeNN(@intFromFloat(new_width), @intFromFloat(new_height));
    }
    updateImages(images);
}

// updates the images' attributes for display
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

//
// image hashing
//

// aHash steps
// - [x]reduce size to an 8x8 square
// - [x]convert picture to grayscale
// - [x]set bits of a 64-bit integer based on whether the pixel is above or below the mean

fn reduceSize(images: []Image) void {
    for (images) |*image| {
        image.rl_image.resizeNN(8, 8);
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
    }
}

fn convertToGrayscale(images: []Image) void {
    for (images) |*image| {
        image.rl_image.grayscale();
        image.texture = rl.loadTextureFromImage(image.rl_image) catch |err|
            fatal(.bad_file, "Failed to load texture from image {s}: {s}", .{ image.path, @errorName(err) });
    }
}

fn makeHashImages(grayscale_images: []Image) void {
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

fn computeHashes(grayscale_images: []Image, hashes: []u64) []u64 {
    const bit: u64 = 1;
    const num_pixels = 64;
    for (grayscale_images, 0..) |*grayscale_image, i| {
        std.debug.assert(grayscale_image.rl_image.width * grayscale_image.rl_image.height == num_pixels);
        const data: []u8 = @as([*]u8, @ptrCast(grayscale_image.rl_image.data))[0..num_pixels];

        var sum: u32 = 0;
        for (data) |byte| sum += byte;
        const mean: f32 = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(num_pixels));

        hashes[i] = 0;
        for (data, 0..num_pixels) |byte, j|
            hashes[i] |= if (@as(f32, @floatFromInt(byte)) > mean) bit << @as(u6, @truncate(j)) else 0;
    }

    return hashes;
}

fn printMetadata(images: []Image) void {
    for (images) |image| {
        std.debug.print("width: {d}, height: {d}\ntexture_width: {d}, texture_height: {d}\nformat: {s}\n", .{ image.rl_image.width, image.rl_image.height, image.texture.width, image.texture.height, @tagName(image.rl_image.format) });
    }
}

fn supportedFormat(path: []u8) bool {
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

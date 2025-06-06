const std = @import("std");
const rl = @import("raylib");
const image = @import("image.zig");
const ui = @import("ui.zig");

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
        \\  img-similarity --fast --dir ./photos    # Fast image similarity detection
        \\  img-similarity --show-steps             # GUI showing image transforms for hashing
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
    std.log.info("showing results for directory: {s}\n", .{directory});

    rl.initWindow(width, height, "Similar images");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const paths = image.pathsFromDir(allocator, directory);
    const images = image.imageSetFromPaths(allocator, paths);

    var image_sets = std.ArrayListUnmanaged([]image.Image).empty;
    try image_sets.append(allocator, images);
    try image_sets.append(
        allocator,
        image.applyStep(allocator, image_sets.items[0], image.reduceTo8x8),
    );
    try image_sets.append(
        allocator,
        image.applyStep(allocator, image_sets.items[1], image.convertToGrayscale),
    );
    try image_sets.append(
        allocator,
        image.applyStep(allocator, image_sets.items[2], image.makeHashImages),
    );

    var state = ui.State.init(image_sets.items);

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

        ui.drawImageSet(state.images[state.set_idx], state.images[state.set_idx][state.image_idx].x);
    }
}

fn runShowStepsMode(allocator: std.mem.Allocator, directory: []const u8) !void {
    // Same as GUI mode - shows transformations with Raylib
    try runGuiMode(allocator, directory);
}

fn runFastMode(allocator: std.mem.Allocator, directory: []const u8) !void {
    const paths = image.pathsFromDir(allocator, directory);
    if (paths.len == 0) {
        fatal(.bad_file, "No valid paths in {s}", .{directory});
    }

    const hashes = try image.computeImageHashes(allocator, paths);

    for (paths, hashes) |path, hash| {
        std.debug.print("{s}: {x:0>16}\n", .{ path, hash });
    }
}

pub const FatalReason = enum(u8) {
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

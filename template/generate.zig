const problem_num = build_options.problem_num;
const max_size = 100_000_000;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const hashes_file = "template/hashes.bin";

fn instantiateTemplate(template: []const u8, problem: u32) ![]const u8 {
    var list = std.ArrayList(u8).init(gpa.allocator());
    errdefer list.deinit();

    try list.ensureTotalCapacity(template.len + 100);
    var rest: []const u8 = template;
    while (std.mem.indexOfScalar(u8, rest, '$')) |index| {
        try list.appendSlice(rest[0..index]);
        try std.fmt.format(list.writer(), "{d:0>3}", .{problem});
        rest = rest[index + 1 ..];
    }
    try list.appendSlice(rest);
    return list.toOwnedSlice();
}

fn readHashes() !*[problem_num][Hash.digest_length]u8 {
    const hash_bytes = std.fs.cwd().readFileAlloc(gpa.allocator(), hashes_file, problem_num * Hash.digest_length) catch |err| switch (err) {
        error.FileTooBig => return error.InvalidFormat,
        else => |e| return e,
    };
    errdefer gpa.allocator().free(hash_bytes);

    if (hash_bytes.len != problem_num * Hash.digest_length)
        return error.InvalidFormat;

    return @ptrCast(hash_bytes.ptr);
}

pub fn main() !void {
    const template = try std.fs.cwd().readFileAlloc(gpa.allocator(), "template/template.zig", max_size);

    const hashes: *[problem_num][Hash.digest_length]u8 = readHashes() catch |err| switch (err) {
        error.FileNotFound => blk: {
            std.debug.print("{s} doesn't exist, will assume all files have been modified.\nDelete src/problemXX.zig and rerun `zig build generate` to regenerate it.\n", .{hashes_file});
            const mem = try gpa.allocator().create([problem_num][Hash.digest_length]u8);
            @memset(std.mem.sliceAsBytes(mem), 0);
            break :blk mem;
        },
        error.InvalidFormat => {
            std.debug.print("{s} is corrupted, delete it to silence this warning and assume all problems have been modified.\n", .{hashes_file});
            std.os.exit(1);
        },
        else => |e| {
            std.debug.print("Failed to open {s}: {}\n", .{ hashes_file, e });
            return e;
        },
    };

    var skipped_any = false;
    var updated_hashes = false;
    var problem: u32 = 1;
    while (problem <= problem_num) : (problem += 1) {
        const filename = try std.fmt.allocPrint(gpa.allocator(), "src/problem{d:0>3}.zig", .{problem});
        defer gpa.allocator().free(filename);

        var new_file = false;
        const file = std.fs.cwd().openFile(filename, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => blk: {
                new_file = true;
                break :blk try std.fs.cwd().createFile(filename, .{});
            },
            else => |e| return e,
        };
        defer file.close();

        var regenerate = false;
        if (!new_file) {
            const contents = file.readToEndAlloc(gpa.allocator(), max_size) catch |err| switch (err) {
                error.FileTooBig => {
                    std.debug.print("Skipping modified problem {s}\n", .{filename});
                    skipped_any = true;
                    continue;
                },
                else => |e| return e,
            };
            defer gpa.allocator().free(contents);

            var hash: [Hash.digest_length]u8 = undefined;
            Hash.hash(contents, &hash, .{});

            regenerate = std.mem.eql(u8, &hash, &hashes[problem - 1]);
        } else {
            regenerate = true;
        }

        if (regenerate) {
            if (!new_file) {
                try file.seekTo(0);
                try file.setEndPos(0);
            }

            const text = try instantiateTemplate(template, problem);
            defer gpa.allocator().free(text);

            Hash.hash(text, &hashes[problem - 1], .{});
            updated_hashes = true;

            try file.writeAll(text);
            if (new_file) {
                std.debug.print("Creating new file {s} from template.\n", .{filename});
            } else {
                std.debug.print("Updated {s}\n", .{filename});
            }
        } else {
            std.debug.print("Skipping modified problem {s}\n", .{filename});
            skipped_any = true;
        }
    }

    if (updated_hashes) {
        try std.fs.cwd().writeFile(hashes_file, std.mem.asBytes(hashes));
        if (skipped_any) {
            std.debug.print("Some problems were skipped. Delete them to force regeneration.\n", .{});
        }
    } else {
        std.debug.print("No updates made, all problems were modified. Delete src/problemXX.zig to force regeneration.\n", .{});
    }
}

const std = @import("std");
const build_options = @import("build_options");

const Hash = std.crypto.hash.Md5;

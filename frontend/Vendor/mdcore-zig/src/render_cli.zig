const std = @import("std");
const api = @import("api.zig");
const t = @import("types.zig");

fn extensionFlag(name: []const u8) ?u32 {
    if (std.mem.eql(u8, name, "table")) return t.extension_table;
    if (std.mem.eql(u8, name, "strikethrough")) return t.extension_strikethrough;
    if (std.mem.eql(u8, name, "autolink")) return t.extension_autolink;
    if (std.mem.eql(u8, name, "tagfilter")) return t.extension_tagfilter;
    if (std.mem.eql(u8, name, "tasklist")) return t.extension_tasklist;
    return null;
}

fn readAllFrom(io: std.Io, arena: std.mem.Allocator, file: std.Io.File) ![]u8 {
    var buf: [64 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    return file_reader.interface.allocRemaining(arena, .limited(64 * 1024 * 1024));
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var format: t.RenderFormat = .html;
    var unsafe = false;
    var explicit_extensions = false;
    var extension_flags: u32 = 0;
    var input_path: ?[]const u8 = null;

    var index: usize = 1;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--plaintext")) {
            format = .plaintext;
        } else if (std.mem.eql(u8, arg, "--unsafe")) {
            unsafe = true;
        } else if (std.mem.eql(u8, arg, "--commonmark")) {
            explicit_extensions = true;
            extension_flags = 0;
        } else if (std.mem.eql(u8, arg, "--extension") or std.mem.eql(u8, arg, "-e")) {
            index += 1;
            if (index >= args.len) return error.MissingExtensionName;
            const flag = extensionFlag(args[index]) orelse return error.UnknownExtension;
            explicit_extensions = true;
            extension_flags |= flag;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try std.Io.File.stdout().writeStreamingAll(io,
                \\Usage: mdcore-render [OPTIONS] [FILE]
                \\  --plaintext          Render plain text instead of HTML
                \\  --unsafe             Preserve raw HTML and unsafe URLs
                \\  --commonmark         Disable all GFM extensions
                \\  -e, --extension NAME Enable one extension (repeatable)
                \\Reads FILE or stdin and writes rendered output to stdout.
                \\
            );
            return;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else if (input_path != null) {
            return error.TooManyInputFiles;
        } else {
            input_path = arg;
        }
        index += 1;
    }

    const input = if (input_path) |path| blk: {
        var file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);
        break :blk try readAllFrom(io, arena, file);
    } else try readAllFrom(io, arena, std.Io.File.stdin());

    const document_options: t.DocumentOptions = .{
        .struct_size = @sizeOf(t.DocumentOptions),
        .flags = if (explicit_extensions) t.document_explicit_extensions else 0,
        .max_document_bytes = 0,
        .extension_flags = extension_flags,
        .reserved = 0,
    };
    var document: ?*api.MdDocument = null;
    const create_status = api.md_document_create(
        .{ .ptr = if (input.len == 0) null else input.ptr, .len = input.len },
        &document_options,
        &document,
    );
    if (create_status != .ok) return error.CreateFailed;
    defer api.md_document_destroy(document);

    const options: t.RenderOptions = .{
        .struct_size = @sizeOf(t.RenderOptions),
        .flags = if (unsafe) t.render_unsafe else 0,
        .format = @intFromEnum(format),
        .reserved = 0,
    };
    var buffer: ?*api.MdBuffer = null;
    const render_status = api.md_document_render(
        document,
        api.md_document_revision(document),
        &options,
        &buffer,
    );
    if (render_status != .ok) return error.RenderFailed;
    defer api.md_buffer_release(buffer);

    const bytes = api.md_buffer_bytes(buffer).slice() orelse "";
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

const std = @import("std");
const utf = @import("utf.zig");
const parser = @import("parser.zig");
const t = @import("types.zig");

pub const default_max_bytes: u64 = 64 * 1024 * 1024;

pub const Document = struct {
    allocator: std.mem.Allocator,
    revision: u64,
    text: []u8,
    utf16_length: u64,
    max_document_bytes: u64,
    extension_flags: u32,

    pub fn create(allocator: std.mem.Allocator, initial: []const u8, options: ?*const t.DocumentOptions) !*Document {
        if (!utf.validate(initial)) return error.InvalidUtf8;

        const max_bytes = if (options) |opts|
            if (opts.max_document_bytes == 0) default_max_bytes else opts.max_document_bytes
        else
            default_max_bytes;

        if (options) |opts| {
            if (opts.struct_size < @sizeOf(t.DocumentOptions)) return error.InvalidArgument;
            if ((opts.flags & ~t.document_explicit_extensions) != 0 or opts.reserved != 0) return error.InvalidArgument;
            if ((opts.extension_flags & ~t.extension_all) != 0) return error.InvalidArgument;
        }

        const extension_flags = if (options) |opts|
            if ((opts.flags & t.document_explicit_extensions) != 0) opts.extension_flags else t.extension_all
        else
            t.extension_all;

        if ((extension_flags & ~t.extension_all) != 0) return error.InvalidArgument;
        if (@as(u64, @intCast(initial.len)) > max_bytes) return error.DocumentTooLarge;

        const document = try allocator.create(Document);
        errdefer allocator.destroy(document);
        const text = try allocator.dupe(u8, initial);
        errdefer allocator.free(text);
        document.* = .{
            .allocator = allocator,
            .revision = 1,
            .text = text,
            .utf16_length = try utf.utf16Length(text),
            .max_document_bytes = max_bytes,
            .extension_flags = extension_flags,
        };
        return document;
    }

    pub fn destroy(self: *Document) void {
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }

    pub fn applyEdit(self: *Document, edit: t.Edit) !t.ByteRange {
        if (edit.expected_revision != self.revision) return error.StaleRevision;
        if (edit.start_byte > edit.old_end_byte) return error.InvalidArgument;
        if (edit.start_byte > std.math.maxInt(usize) or edit.old_end_byte > std.math.maxInt(usize)) return error.InvalidArgument;

        const start: usize = @intCast(edit.start_byte);
        const old_end: usize = @intCast(edit.old_end_byte);
        if (old_end > self.text.len) return error.InvalidArgument;
        if (!utf.isBoundary(self.text, start) or !utf.isBoundary(self.text, old_end)) return error.InvalidBoundary;

        const replacement = edit.replacement.slice() orelse return error.InvalidArgument;
        if (!utf.validate(replacement)) return error.InvalidUtf8;

        const removed = old_end - start;
        const base_len = self.text.len - removed;
        const sum = @addWithOverflow(base_len, replacement.len);
        if (sum[1] != 0) return error.DocumentTooLarge;
        const new_len = sum[0];
        if (@as(u64, @intCast(new_len)) > self.max_document_bytes) return error.DocumentTooLarge;

        const revision_sum = @addWithOverflow(self.revision, 1);
        if (revision_sum[1] != 0) return error.Overflow;

        const next = try self.allocator.alloc(u8, new_len);
        errdefer self.allocator.free(next);
        @memcpy(next[0..start], self.text[0..start]);
        @memcpy(next[start .. start + replacement.len], replacement);
        @memcpy(next[start + replacement.len ..], self.text[old_end..]);

        const next_utf16_length = try utf.utf16Length(next);
        self.allocator.free(self.text);
        self.text = next;
        self.utf16_length = next_utf16_length;
        self.revision = revision_sum[0];

        var invalid_start = start;
        while (invalid_start > 0 and next[invalid_start - 1] != '\n') invalid_start -= 1;
        var invalid_end = start + replacement.len;
        while (invalid_end < next.len and next[invalid_end] != '\n') invalid_end += 1;
        if (invalid_end < next.len) invalid_end += 1;
        return .{ .start = @intCast(invalid_start), .end = @intCast(invalid_end) };
    }

    pub fn parse(self: *const Document) !parser.Parsed {
        return parser.parse(self.allocator, self.text, self.extension_flags);
    }
};

test "document edits validate revisions, UTF-8 boundaries, and limits" {
    const allocator = std.testing.allocator;
    const opts: t.DocumentOptions = .{
        .struct_size = @sizeOf(t.DocumentOptions),
        .flags = 0,
        .max_document_bytes = 32,
        .extension_flags = 0,
        .reserved = 0,
    };
    const doc = try Document.create(allocator, "a😀b\n", &opts);
    defer doc.destroy();
    try std.testing.expectEqual(@as(u64, 1), doc.revision);
    try std.testing.expectEqual(@as(u64, 5), doc.utf16_length);
    try std.testing.expectEqual(t.extension_all, doc.extension_flags);

    const replacement = "X";
    const range = try doc.applyEdit(.{
        .expected_revision = 1,
        .start_byte = 1,
        .old_end_byte = 5,
        .replacement = .{ .ptr = replacement.ptr, .len = replacement.len },
    });
    try std.testing.expectEqualStrings("aXb\n", doc.text);
    try std.testing.expectEqual(@as(u64, 2), doc.revision);
    try std.testing.expectEqual(@as(u64, 0), range.start);
    try std.testing.expectEqual(@as(u64, 4), range.end);

    try std.testing.expectError(error.StaleRevision, doc.applyEdit(.{
        .expected_revision = 1,
        .start_byte = 0,
        .old_end_byte = 0,
        .replacement = .{ .ptr = null, .len = 0 },
    }));
}

test "explicit extension selection can disable GFM extensions" {
    const opts: t.DocumentOptions = .{
        .struct_size = @sizeOf(t.DocumentOptions),
        .flags = t.document_explicit_extensions,
        .max_document_bytes = 0,
        .extension_flags = 0,
        .reserved = 0,
    };
    const doc = try Document.create(std.testing.allocator, "~~text~~", &opts);
    defer doc.destroy();
    try std.testing.expectEqual(@as(u32, 0), doc.extension_flags);
}

test "edit sequences preserve UTF-8 and UTF-16 model state" {
    const doc = try Document.create(std.testing.allocator, "α beta\nline two\n", null);
    defer doc.destroy();

    const cases = [_]struct { start: u64, end: u64, replacement: []const u8, expected: []const u8 }{
        .{ .start = 2, .end = 2, .replacement = "😀", .expected = "α😀 beta\nline two\n" },
        .{ .start = 7, .end = 11, .replacement = "B", .expected = "α😀 B\nline two\n" },
        .{ .start = 9, .end = 17, .replacement = "二", .expected = "α😀 B\n二\n" },
    };

    for (cases) |case| {
        const revision = doc.revision;
        _ = try doc.applyEdit(.{
            .expected_revision = revision,
            .start_byte = case.start,
            .old_end_byte = case.end,
            .replacement = .{ .ptr = case.replacement.ptr, .len = case.replacement.len },
        });
        try std.testing.expectEqualStrings(case.expected, doc.text);
        try std.testing.expectEqual(try utf.utf16Length(case.expected), doc.utf16_length);
    }
}

test "deterministic randomized edit model stays equivalent" {
    const options: t.DocumentOptions = .{
        .struct_size = @sizeOf(t.DocumentOptions),
        .flags = 0,
        .max_document_bytes = 4096,
        .extension_flags = 0,
        .reserved = 0,
    };
    const doc = try Document.create(std.testing.allocator, "seed 😀\n", &options);
    defer doc.destroy();

    var model_storage: [4096]u8 = undefined;
    @memcpy(model_storage[0..doc.text.len], doc.text);
    var model_len = doc.text.len;
    var state: u64 = 0x4d_64_43_6f_72_65;
    const replacements = [_][]const u8{ "", "a", "é", "😀", "\n", "**", "[x]" };

    for (0..500) |_| {
        var boundaries: [4097]usize = undefined;
        var boundary_count: usize = 0;
        for (0..model_len + 1) |offset| {
            if (utf.isBoundary(model_storage[0..model_len], offset)) {
                boundaries[boundary_count] = offset;
                boundary_count += 1;
            }
        }

        state = state *% 6364136223846793005 +% 1442695040888963407;
        var first_index: usize = @intCast(state % @as(u64, @intCast(boundary_count)));
        state = state *% 6364136223846793005 +% 1442695040888963407;
        var second_index: usize = @intCast(state % @as(u64, @intCast(boundary_count)));
        if (first_index > second_index) std.mem.swap(usize, &first_index, &second_index);
        const start = boundaries[first_index];
        const end = boundaries[second_index];

        state = state *% 6364136223846793005 +% 1442695040888963407;
        var replacement = replacements[@intCast(state % @as(u64, @intCast(replacements.len)))];
        const candidate_len = model_len - (end - start) + replacement.len;
        if (candidate_len > model_storage.len) replacement = "";
        const new_len = model_len - (end - start) + replacement.len;

        var next_storage: [4096]u8 = undefined;
        @memcpy(next_storage[0..start], model_storage[0..start]);
        @memcpy(next_storage[start .. start + replacement.len], replacement);
        @memcpy(next_storage[start + replacement.len .. new_len], model_storage[end..model_len]);

        _ = try doc.applyEdit(.{
            .expected_revision = doc.revision,
            .start_byte = @intCast(start),
            .old_end_byte = @intCast(end),
            .replacement = .{ .ptr = if (replacement.len == 0) null else replacement.ptr, .len = replacement.len },
        });

        @memcpy(model_storage[0..new_len], next_storage[0..new_len]);
        model_len = new_len;
        try std.testing.expectEqualStrings(model_storage[0..model_len], doc.text);
        try std.testing.expectEqual(try utf.utf16Length(model_storage[0..model_len]), doc.utf16_length);
    }
}

test "failed edits are transactional" {
    const doc = try Document.create(std.testing.allocator, "a😀b", null);
    defer doc.destroy();

    const original_revision = doc.revision;
    const original_utf16_length = doc.utf16_length;
    const original = try std.testing.allocator.dupe(u8, doc.text);
    defer std.testing.allocator.free(original);

    try std.testing.expectError(error.InvalidBoundary, doc.applyEdit(.{
        .expected_revision = original_revision,
        .start_byte = 2,
        .old_end_byte = 2,
        .replacement = .{ .ptr = null, .len = 0 },
    }));
    try std.testing.expectEqual(original_revision, doc.revision);
    try std.testing.expectEqual(original_utf16_length, doc.utf16_length);
    try std.testing.expectEqualStrings(original, doc.text);

    const invalid_utf8 = [_]u8{ 0xc0, 0x80 };
    try std.testing.expectError(error.InvalidUtf8, doc.applyEdit(.{
        .expected_revision = original_revision,
        .start_byte = 1,
        .old_end_byte = 1,
        .replacement = .{ .ptr = invalid_utf8[0..].ptr, .len = invalid_utf8.len },
    }));
    try std.testing.expectEqual(original_revision, doc.revision);
    try std.testing.expectEqual(original_utf16_length, doc.utf16_length);
    try std.testing.expectEqualStrings(original, doc.text);
}

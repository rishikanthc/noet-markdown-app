const std = @import("std");
const cmark = @import("cmark.zig");
const commands = @import("commands.zig");
const doc_mod = @import("document.zig");
const patch_mod = @import("patch.zig");
const parser = @import("parser.zig");
const utf = @import("utf.zig");
const t = @import("types.zig");

const allocator = std.heap.c_allocator;

pub const MdDocument = doc_mod.Document;
pub const MdPatch = patch_mod.Patch;
pub const MdEditList = commands.EditList;
pub const MdBuffer = struct {
    bytes: []u8,
};

fn statusFromError(err: anyerror) t.Status {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.InvalidUtf8 => .invalid_utf8,
        error.StaleRevision => .stale_revision,
        error.ParseFailed => .parse_failed,
        error.Unsupported => .unsupported,
        error.InvalidArgument, error.InvalidBoundary, error.DocumentTooLarge, error.Overflow => .invalid_argument,
        else => .internal_error,
    };
}

fn toUsize(value: u64) ?usize {
    if (value > std.math.maxInt(usize)) return null;
    return @intCast(value);
}

pub export fn mdcore_abi_version() callconv(.c) u32 {
    return t.abi_version;
}

pub export fn mdcore_version_string() callconv(.c) [*:0]const u8 {
    return t.version_string.ptr;
}

pub export fn mdcore_cmark_version_string() callconv(.c) [*:0]const u8 {
    return cmark.cmark_version_string();
}

pub export fn md_document_create(initial_utf8: t.Bytes, options: ?*const t.DocumentOptions, out_document: ?*?*MdDocument) callconv(.c) t.Status {
    const out = out_document orelse return .invalid_argument;
    out.* = null;

    const initial = initial_utf8.slice() orelse return .invalid_argument;
    if (options) |opts| {
        if (opts.struct_size < @sizeOf(t.DocumentOptions)) return .invalid_argument;
        if ((opts.flags & ~t.document_explicit_extensions) != 0 or opts.reserved != 0) return .invalid_argument;
    }

    const document = doc_mod.Document.create(allocator, initial, options) catch |err| return statusFromError(err);
    out.* = document;
    return .ok;
}

pub export fn md_document_destroy(document: ?*MdDocument) callconv(.c) void {
    if (document) |doc| doc.destroy();
}

pub export fn md_document_revision(document: ?*const MdDocument) callconv(.c) u64 {
    return if (document) |doc| doc.revision else 0;
}

pub export fn md_document_utf8_length(document: ?*const MdDocument) callconv(.c) u64 {
    return if (document) |doc| @intCast(doc.text.len) else 0;
}

pub export fn md_document_utf16_length(document: ?*const MdDocument) callconv(.c) u64 {
    return if (document) |doc| doc.utf16_length else 0;
}

pub export fn md_document_apply_edit(document: ?*MdDocument, edit: ?*const t.Edit, out_fast_patch: ?*?*MdPatch) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    const value = edit orelse return .invalid_argument;
    const out = out_fast_patch orelse return .invalid_argument;
    out.* = null;

    const base_revision = doc.revision;
    const patch = patch_mod.Patch.fast(
        allocator,
        base_revision,
        base_revision,
        .{ .start = 0, .end = 0 },
    ) catch |err| return statusFromError(err);
    const range = doc.applyEdit(value.*) catch |err| {
        patch.destroy();
        return statusFromError(err);
    };
    patch.result_revision = doc.revision;
    patch.ranges[0] = range;
    out.* = patch;
    return .ok;
}

pub export fn md_document_build_canonical_patch(document: ?*const MdDocument, revision: u64, out_patch: ?*?*MdPatch) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    const out = out_patch orelse return .invalid_argument;
    out.* = null;
    if (revision != doc.revision) return .stale_revision;

    var parsed = doc.parse() catch |err| return statusFromError(err);
    defer parsed.deinit();
    const patch = patch_mod.Patch.canonical(allocator, revision, doc.text.len, &parsed) catch |err| return statusFromError(err);
    out.* = patch;
    return .ok;
}

pub export fn md_patch_base_revision(patch: ?*const MdPatch) callconv(.c) u64 {
    return if (patch) |value| value.base_revision else 0;
}

pub export fn md_patch_result_revision(patch: ?*const MdPatch) callconv(.c) u64 {
    return if (patch) |value| value.result_revision else 0;
}

pub export fn md_patch_invalidated_ranges(patch: ?*const MdPatch) callconv(.c) t.RangeView {
    const value = patch orelse return t.emptyRangeView();
    return .{ .ptr = if (value.ranges.len == 0) null else value.ranges.ptr, .len = value.ranges.len };
}

pub export fn md_patch_semantic_nodes(patch: ?*const MdPatch) callconv(.c) t.NodeView {
    const value = patch orelse return t.emptyNodeView();
    return .{ .ptr = if (value.nodes.len == 0) null else value.nodes.ptr, .len = value.nodes.len };
}

pub export fn md_patch_decoration_spans(patch: ?*const MdPatch) callconv(.c) t.SpanView {
    const value = patch orelse return t.emptySpanView();
    return .{ .ptr = if (value.spans.len == 0) null else value.spans.ptr, .len = value.spans.len };
}

pub export fn md_patch_release(patch: ?*MdPatch) callconv(.c) void {
    if (patch) |value| value.destroy();
}

pub export fn md_document_plan_command(
    document: ?*const MdDocument,
    revision: u64,
    command_raw: c_int,
    selection: t.ByteRange,
    options: ?*const t.CommandOptions,
    out_edits: ?*?*MdEditList,
) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    const out = out_edits orelse return .invalid_argument;
    out.* = null;
    if (revision != doc.revision) return .stale_revision;

    const command: t.CommandKind = switch (command_raw) {
        1 => .toggle_emphasis,
        2 => .toggle_strong,
        3 => .toggle_strikethrough,
        4 => .inline_code,
        5 => .insert_link,
        6 => .set_heading,
        7 => .toggle_block_quote,
        8 => .toggle_task_item,
        9 => .indent_list_item,
        10 => .outdent_list_item,
        else => return .invalid_argument,
    };
    var command_plan = commands.plan(allocator, doc.text, command, selection, options) catch |err| return statusFromError(err);
    const edit_list = commands.EditList.fromPlan(allocator, &command_plan) catch |err| {
        command_plan.deinit();
        return statusFromError(err);
    };
    out.* = edit_list;
    return .ok;
}

pub export fn md_edit_list_edits(edit_list: ?*const MdEditList) callconv(.c) t.PlannedEditView {
    const value = edit_list orelse return t.emptyPlannedEditView();
    return .{ .ptr = if (value.edits.len == 0) null else value.edits.ptr, .len = value.edits.len };
}

pub export fn md_edit_list_result_selection(edit_list: ?*const MdEditList) callconv(.c) t.ByteRange {
    const value = edit_list orelse return .{ .start = 0, .end = 0 };
    return value.result_selection;
}

pub export fn md_edit_list_release(edit_list: ?*MdEditList) callconv(.c) void {
    if (edit_list) |value| value.destroy();
}

pub export fn md_document_copy_source(document: ?*const MdDocument, revision: u64, out_buffer: ?*?*MdBuffer) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    const out = out_buffer orelse return .invalid_argument;
    out.* = null;
    if (revision != doc.revision) return .stale_revision;

    const bytes = allocator.dupe(u8, doc.text) catch return .out_of_memory;
    const buffer = allocator.create(MdBuffer) catch {
        allocator.free(bytes);
        return .out_of_memory;
    };
    buffer.* = .{ .bytes = bytes };
    out.* = buffer;
    return .ok;
}

pub export fn md_document_byte_to_utf16(document: ?*const MdDocument, byte_offset: u64, out_utf16_offset: ?*u64) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    const out = out_utf16_offset orelse return .invalid_argument;
    const offset = toUsize(byte_offset) orelse return .invalid_argument;
    out.* = utf.byteToUtf16(doc.text, offset) catch |err| return statusFromError(err);
    return .ok;
}

pub export fn md_document_utf16_to_byte(document: ?*const MdDocument, utf16_offset: u64, out_byte_offset: ?*u64) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    const out = out_byte_offset orelse return .invalid_argument;
    out.* = utf.utf16ToByte(doc.text, utf16_offset) catch |err| return statusFromError(err);
    return .ok;
}

pub export fn md_document_byte_range_to_utf16(document: ?*const MdDocument, byte_range: t.ByteRange, out_range: ?*t.Utf16Range) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    const out = out_range orelse return .invalid_argument;
    if (byte_range.start > byte_range.end) return .invalid_argument;

    const start = toUsize(byte_range.start) orelse return .invalid_argument;
    const end = toUsize(byte_range.end) orelse return .invalid_argument;
    const start16 = utf.byteToUtf16(doc.text, start) catch |err| return statusFromError(err);
    const end16 = utf.byteToUtf16(doc.text, end) catch |err| return statusFromError(err);
    out.* = .{ .location = start16, .length = end16 - start16 };
    return .ok;
}

pub export fn md_document_byte_offsets_to_utf16(
    document: ?*const MdDocument,
    byte_offsets: ?[*]const u64,
    count: usize,
    out_utf16_offsets: ?[*]u64,
) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    if (count == 0) return .ok;
    const input = byte_offsets orelse return .invalid_argument;
    const output = out_utf16_offsets orelse return .invalid_argument;

    // Convert into a scratch buffer first so a failure leaves the caller's output
    // untouched (all-or-nothing).
    const scratch = allocator.alloc(u64, count) catch return .out_of_memory;
    defer allocator.free(scratch);
    utf.byteToUtf16Batch(allocator, doc.text, input[0..count], scratch) catch |err| return statusFromError(err);
    @memcpy(output[0..count], scratch);
    return .ok;
}

pub export fn md_document_byte_ranges_to_utf16(
    document: ?*const MdDocument,
    byte_ranges: ?[*]const t.ByteRange,
    count: usize,
    out_ranges: ?[*]t.Utf16Range,
) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    if (count == 0) return .ok;
    const input = byte_ranges orelse return .invalid_argument;
    const output = out_ranges orelse return .invalid_argument;

    // Flatten the range endpoints into one array and convert them all in a single
    // scan, then reassemble. Avoids an O(bytes) rescan per endpoint.
    const endpoints = allocator.alloc(u64, count * 2) catch return .out_of_memory;
    defer allocator.free(endpoints);
    for (0..count) |index| {
        const byte_range = input[index];
        if (byte_range.start > byte_range.end) return .invalid_argument;
        endpoints[index * 2] = byte_range.start;
        endpoints[index * 2 + 1] = byte_range.end;
    }

    const converted = allocator.alloc(u64, count * 2) catch return .out_of_memory;
    defer allocator.free(converted);
    utf.byteToUtf16Batch(allocator, doc.text, endpoints, converted) catch |err| return statusFromError(err);

    for (0..count) |index| {
        const start16 = converted[index * 2];
        const end16 = converted[index * 2 + 1];
        output[index] = .{ .location = start16, .length = end16 - start16 };
    }
    return .ok;
}

pub export fn md_document_render(document: ?*const MdDocument, revision: u64, options: ?*const t.RenderOptions, out_buffer: ?*?*MdBuffer) callconv(.c) t.Status {
    const doc = document orelse return .invalid_argument;
    const opts = options orelse return .invalid_argument;
    const out = out_buffer orelse return .invalid_argument;
    out.* = null;

    if (opts.struct_size < @sizeOf(t.RenderOptions)) return .invalid_argument;
    if ((opts.flags & ~t.render_all) != 0 or opts.reserved != 0) return .invalid_argument;
    if (revision != doc.revision) return .stale_revision;

    const format: t.RenderFormat = switch (opts.format) {
        @intFromEnum(t.RenderFormat.html) => .html,
        @intFromEnum(t.RenderFormat.plaintext) => .plaintext,
        else => return .unsupported,
    };

    var parsed = doc.parse() catch |err| return statusFromError(err);
    defer parsed.deinit();
    const bytes = parser.render(&parsed, format, opts.flags) catch |err| return statusFromError(err);
    const buffer = allocator.create(MdBuffer) catch {
        allocator.free(bytes);
        return .out_of_memory;
    };
    buffer.* = .{ .bytes = bytes };
    out.* = buffer;
    return .ok;
}

pub export fn md_buffer_bytes(buffer: ?*const MdBuffer) callconv(.c) t.Bytes {
    const value = buffer orelse return .{ .ptr = null, .len = 0 };
    return .{ .ptr = if (value.bytes.len == 0) null else value.bytes.ptr, .len = value.bytes.len };
}

pub export fn md_buffer_release(buffer: ?*MdBuffer) callconv(.c) void {
    if (buffer) |value| {
        allocator.free(value.bytes);
        allocator.destroy(value);
    }
}

test "C ABI functions preserve null output on failure" {
    var document: ?*MdDocument = null;
    const invalid = [_]u8{ 0xc0, 0x80 };
    const status = md_document_create(.{ .ptr = invalid[0..].ptr, .len = invalid.len }, null, &document);
    try std.testing.expectEqual(t.Status.invalid_utf8, status);
    try std.testing.expectEqual(@as(?*MdDocument, null), document);
}

test {
    _ = @import("utf.zig");
    _ = @import("source_map.zig");
    _ = @import("source_locator.zig");
    _ = @import("commands.zig");
    _ = @import("document.zig");
    _ = @import("parser.zig");
}

test "C ABI supports source copies, batch coordinates, and command plans" {
    const source = "a😀b";
    var document: ?*MdDocument = null;
    try std.testing.expectEqual(t.Status.ok, md_document_create(
        .{ .ptr = source.ptr, .len = source.len },
        null,
        &document,
    ));
    defer md_document_destroy(document);

    const offsets = [_]u64{ 0, 1, 5, 6 };
    var converted = [_]u64{ 99, 99, 99, 99 };
    try std.testing.expectEqual(t.Status.ok, md_document_byte_offsets_to_utf16(document, &offsets, offsets.len, &converted));
    try std.testing.expectEqualSlices(u64, &[_]u64{ 0, 1, 3, 4 }, &converted);

    var copied: ?*MdBuffer = null;
    try std.testing.expectEqual(t.Status.ok, md_document_copy_source(document, 1, &copied));
    defer md_buffer_release(copied);
    try std.testing.expectEqualStrings(source, md_buffer_bytes(copied).slice().?);

    var edits: ?*MdEditList = null;
    try std.testing.expectEqual(t.Status.ok, md_document_plan_command(
        document,
        1,
        2,
        .{ .start = 0, .end = 1 },
        null,
        &edits,
    ));
    defer md_edit_list_release(edits);
    const view = md_edit_list_edits(edits);
    try std.testing.expectEqual(@as(usize, 1), view.len);
    try std.testing.expectEqualStrings("**a**", view.ptr.?[0].replacement.slice().?);

    var invalid_edits: ?*MdEditList = @ptrFromInt(@alignOf(MdEditList));
    try std.testing.expectEqual(t.Status.invalid_argument, md_document_plan_command(
        document,
        1,
        999,
        .{ .start = 0, .end = 0 },
        null,
        &invalid_edits,
    ));
    try std.testing.expectEqual(@as(?*MdEditList, null), invalid_edits);
}

test "batch coordinate conversion is all-or-nothing" {
    const source = "a😀b";
    var document: ?*MdDocument = null;
    try std.testing.expectEqual(t.Status.ok, md_document_create(
        .{ .ptr = source.ptr, .len = source.len },
        null,
        &document,
    ));
    defer md_document_destroy(document);

    const offsets = [_]u64{ 0, 2, 6 };
    var output = [_]u64{ 77, 77, 77 };
    try std.testing.expectEqual(
        t.Status.invalid_argument,
        md_document_byte_offsets_to_utf16(document, &offsets, offsets.len, &output),
    );
    try std.testing.expectEqualSlices(u64, &[_]u64{ 77, 77, 77 }, &output);

    const ranges = [_]t.ByteRange{
        .{ .start = 0, .end = 1 },
        .{ .start = 1, .end = 2 },
    };
    var converted = [_]t.Utf16Range{
        .{ .location = 88, .length = 88 },
        .{ .location = 88, .length = 88 },
    };
    try std.testing.expectEqual(
        t.Status.invalid_argument,
        md_document_byte_ranges_to_utf16(document, &ranges, ranges.len, &converted),
    );
    try std.testing.expectEqual(@as(u64, 88), converted[0].location);
    try std.testing.expectEqual(@as(u64, 88), converted[1].location);
}

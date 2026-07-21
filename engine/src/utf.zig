const std = @import("std");

pub const UtfError = error{ InvalidUtf8, InvalidBoundary };

pub const Decode = struct {
    scalar: u21,
    length: u3,
};

fn isContinuation(byte: u8) bool {
    return (byte & 0xC0) == 0x80;
}

pub fn decodeOne(bytes: []const u8, index: usize) UtfError!Decode {
    if (index >= bytes.len) return error.InvalidBoundary;
    const b0 = bytes[index];
    if (b0 <= 0x7F) return .{ .scalar = b0, .length = 1 };

    if (b0 >= 0xC2 and b0 <= 0xDF) {
        if (index + 1 >= bytes.len) return error.InvalidUtf8;
        const b1 = bytes[index + 1];
        if (!isContinuation(b1)) return error.InvalidUtf8;
        const scalar: u21 = (@as(u21, b0 & 0x1F) << 6) | @as(u21, b1 & 0x3F);
        return .{ .scalar = scalar, .length = 2 };
    }

    if (b0 >= 0xE0 and b0 <= 0xEF) {
        if (index + 2 >= bytes.len) return error.InvalidUtf8;
        const b1 = bytes[index + 1];
        const b2 = bytes[index + 2];
        if (!isContinuation(b1) or !isContinuation(b2)) return error.InvalidUtf8;
        if (b0 == 0xE0 and b1 < 0xA0) return error.InvalidUtf8;
        if (b0 == 0xED and b1 >= 0xA0) return error.InvalidUtf8;
        const scalar: u21 = (@as(u21, b0 & 0x0F) << 12) |
            (@as(u21, b1 & 0x3F) << 6) |
            @as(u21, b2 & 0x3F);
        return .{ .scalar = scalar, .length = 3 };
    }

    if (b0 >= 0xF0 and b0 <= 0xF4) {
        if (index + 3 >= bytes.len) return error.InvalidUtf8;
        const b1 = bytes[index + 1];
        const b2 = bytes[index + 2];
        const b3 = bytes[index + 3];
        if (!isContinuation(b1) or !isContinuation(b2) or !isContinuation(b3)) return error.InvalidUtf8;
        if (b0 == 0xF0 and b1 < 0x90) return error.InvalidUtf8;
        if (b0 == 0xF4 and b1 >= 0x90) return error.InvalidUtf8;
        const scalar: u21 = (@as(u21, b0 & 0x07) << 18) |
            (@as(u21, b1 & 0x3F) << 12) |
            (@as(u21, b2 & 0x3F) << 6) |
            @as(u21, b3 & 0x3F);
        return .{ .scalar = scalar, .length = 4 };
    }

    return error.InvalidUtf8;
}

pub fn validate(bytes: []const u8) bool {
    var index: usize = 0;
    while (index < bytes.len) {
        const decoded = decodeOne(bytes, index) catch return false;
        index += decoded.length;
    }
    return true;
}

pub fn isBoundary(bytes: []const u8, offset: usize) bool {
    if (offset > bytes.len) return false;
    if (offset == 0 or offset == bytes.len) return true;
    return !isContinuation(bytes[offset]);
}

pub fn utf16Length(bytes: []const u8) UtfError!u64 {
    var index: usize = 0;
    var units: u64 = 0;
    while (index < bytes.len) {
        const decoded = try decodeOne(bytes, index);
        units += if (decoded.scalar > 0xFFFF) 2 else 1;
        index += decoded.length;
    }
    return units;
}

pub fn byteToUtf16(bytes: []const u8, byte_offset: usize) UtfError!u64 {
    if (byte_offset > bytes.len or !isBoundary(bytes, byte_offset)) return error.InvalidBoundary;
    var index: usize = 0;
    var units: u64 = 0;
    while (index < byte_offset) {
        const decoded = try decodeOne(bytes, index);
        if (index + decoded.length > byte_offset) return error.InvalidBoundary;
        units += if (decoded.scalar > 0xFFFF) 2 else 1;
        index += decoded.length;
    }
    return units;
}

/// Converts many byte offsets to UTF-16 offsets in a single O(n log n + bytes)
/// pass instead of one O(bytes) scan per offset. `offsets` need not be sorted;
/// results are written to `out` at matching indices.
pub fn byteToUtf16Batch(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    offsets: []const u64,
    out: []u64,
) (UtfError || std.mem.Allocator.Error)!void {
    std.debug.assert(offsets.len == out.len);
    if (offsets.len == 0) return;

    const order = try allocator.alloc(usize, offsets.len);
    defer allocator.free(order);
    for (order, 0..) |*slot, i| slot.* = i;
    std.sort.pdq(usize, order, offsets, struct {
        fn lessThan(offs: []const u64, a: usize, b: usize) bool {
            return offs[a] < offs[b];
        }
    }.lessThan);

    var scan: usize = 0;
    var units: u64 = 0;
    for (order) |original_index| {
        const target_u64 = offsets[original_index];
        if (target_u64 > bytes.len) return error.InvalidBoundary;
        const target: usize = @intCast(target_u64);
        while (scan < target) {
            const decoded = try decodeOne(bytes, scan);
            if (scan + decoded.length > target) return error.InvalidBoundary;
            units += if (decoded.scalar > 0xFFFF) 2 else 1;
            scan += decoded.length;
        }
        out[original_index] = units;
    }
}

pub fn utf16ToByte(bytes: []const u8, utf16_offset: u64) UtfError!u64 {
    var index: usize = 0;
    var units: u64 = 0;
    while (index < bytes.len) {
        if (units == utf16_offset) return @intCast(index);
        const decoded = try decodeOne(bytes, index);
        const width: u64 = if (decoded.scalar > 0xFFFF) 2 else 1;
        if (units + width > utf16_offset) return error.InvalidBoundary;
        units += width;
        index += decoded.length;
    }
    if (units == utf16_offset) return @intCast(bytes.len);
    return error.InvalidBoundary;
}

test "UTF-8 validation rejects malformed and overlong sequences" {
    try std.testing.expect(validate("hello"));
    try std.testing.expect(validate("A\xF0\x9F\x98\x80Z"));
    try std.testing.expect(!validate(&[_]u8{ 0xC0, 0x80 }));
    try std.testing.expect(!validate(&[_]u8{ 0xED, 0xA0, 0x80 }));
    try std.testing.expect(!validate(&[_]u8{ 0xF4, 0x90, 0x80, 0x80 }));
}

test "UTF-8 byte and UTF-16 conversions are exact" {
    const value = "aé😀z";
    try std.testing.expectEqual(@as(u64, 5), try utf16Length(value));
    try std.testing.expectEqual(@as(u64, 1), try byteToUtf16(value, 1));
    try std.testing.expectEqual(@as(u64, 2), try byteToUtf16(value, 3));
    try std.testing.expectEqual(@as(u64, 4), try byteToUtf16(value, 7));
    try std.testing.expectEqual(@as(u64, 3), try utf16ToByte(value, 2));
    try std.testing.expectEqual(@as(u64, 7), try utf16ToByte(value, 4));
    try std.testing.expectError(error.InvalidBoundary, byteToUtf16(value, 2));
    try std.testing.expectError(error.InvalidBoundary, utf16ToByte(value, 3));
}

test "batch byte-to-UTF-16 matches scalar conversion regardless of order" {
    // Bytes: a(0) é(1..2) 😀(3..6) z(7); total length 8, UTF-16 length 5.
    const value = "aé😀z";
    // Deliberately unsorted, with duplicates and both bounds.
    const offsets = [_]u64{ 7, 0, 3, 1, 7, 8 };
    var out = [_]u64{ 0, 0, 0, 0, 0, 0 };
    try byteToUtf16Batch(std.testing.allocator, value, &offsets, &out);
    try std.testing.expectEqual(@as(u64, 4), out[0]);
    try std.testing.expectEqual(@as(u64, 0), out[1]);
    try std.testing.expectEqual(@as(u64, 2), out[2]);
    try std.testing.expectEqual(@as(u64, 1), out[3]);
    try std.testing.expectEqual(@as(u64, 4), out[4]);
    try std.testing.expectEqual(@as(u64, 5), out[5]);

    var bad = [_]u64{0};
    try std.testing.expectError(error.InvalidBoundary, byteToUtf16Batch(std.testing.allocator, value, &[_]u64{2}, &bad));
}

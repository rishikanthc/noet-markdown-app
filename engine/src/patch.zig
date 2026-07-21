const std = @import("std");
const t = @import("types.zig");
const parser = @import("parser.zig");

pub const Patch = struct {
    allocator: std.mem.Allocator,
    base_revision: u64,
    result_revision: u64,
    ranges: []t.ByteRange,
    nodes: []t.SemanticNode,
    spans: []t.DecorationSpan,

    pub fn fast(allocator: std.mem.Allocator, base_revision: u64, result_revision: u64, range: t.ByteRange) !*Patch {
        const patch = try allocator.create(Patch);
        errdefer allocator.destroy(patch);

        const ranges = try allocator.alloc(t.ByteRange, 1);
        errdefer allocator.free(ranges);
        ranges[0] = range;

        const nodes = try allocator.alloc(t.SemanticNode, 0);
        errdefer allocator.free(nodes);
        const spans = try allocator.alloc(t.DecorationSpan, 0);
        errdefer allocator.free(spans);

        patch.* = .{
            .allocator = allocator,
            .base_revision = base_revision,
            .result_revision = result_revision,
            .ranges = ranges,
            .nodes = nodes,
            .spans = spans,
        };
        return patch;
    }

    pub fn canonical(allocator: std.mem.Allocator, revision: u64, source_len: usize, parsed: *const parser.Parsed) !*Patch {
        const patch = try allocator.create(Patch);
        errdefer allocator.destroy(patch);

        const ranges = try allocator.alloc(t.ByteRange, 1);
        errdefer allocator.free(ranges);
        ranges[0] = .{ .start = 0, .end = @intCast(source_len) };

        const nodes = try allocator.dupe(t.SemanticNode, parsed.nodes);
        errdefer allocator.free(nodes);
        const spans = try allocator.dupe(t.DecorationSpan, parsed.spans);
        errdefer allocator.free(spans);

        patch.* = .{
            .allocator = allocator,
            .base_revision = revision,
            .result_revision = revision,
            .ranges = ranges,
            .nodes = nodes,
            .spans = spans,
        };
        return patch;
    }

    pub fn destroy(self: *Patch) void {
        self.allocator.free(self.ranges);
        self.allocator.free(self.nodes);
        self.allocator.free(self.spans);
        self.allocator.destroy(self);
    }
};

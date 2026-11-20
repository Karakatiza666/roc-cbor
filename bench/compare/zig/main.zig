//! The Zig side of bench/compare. Usage: cbor-bench <case> <loops> <fixture_dir>
//! Library: zbor (comptime-derived parse and stringify of Zig types). The contract of each case is in
//! bench/compare/README.md. Each loop parses into an arena on the C allocator, freed after the loop
//! (the usual Zig pattern: zbor has no free function for a parsed value).
//! Not supported by zbor, exit 3 (the runner records n/a): a dynamic value tree (records_value,
//! map_value, deep_*: zbor's DataItem is a checked view, not a tree), and nesting deeper than 128.
//! dict_parse uses zbor's map iterator into a std.StringHashMap (parse has no hash map target).
const std = @import("std");
const zbor = @import("zbor");

const Rec = struct {
    id: u64,
    name: []const u8,
    ok: bool,
    score: f64,
    tags: []const []const u8,
};

fn fixtureOf(case: []const u8) ?[]const u8 {
    const pairs = .{
        .{ "bytes_encode", "bytes" },   .{ "bytes_parse", "bytes" },
        .{ "records_encode", "records" }, .{ "records_parse", "records" },
        .{ "records_value", "records" }, .{ "unknown_parse", "wide" },
        .{ "dict_parse", "dict" },       .{ "map_value", "dict" },
        .{ "text_parse", "texts" },      .{ "deep_encode", "deep" },
        .{ "deep_parse", "deep" },
    };
    inline for (pairs) |p| if (std.mem.eql(u8, case, p[0])) return p[1];
    return null;
}

var sink: u64 = 0;

fn encodeLen(gpa: std.mem.Allocator, value: anytype, options: zbor.Options) !u64 {
    var w = std.Io.Writer.Allocating.init(gpa);
    defer w.deinit();
    try zbor.stringify(value, options, &w.writer);
    return w.written().len;
}

fn parseLen(comptime T: type, data: []const u8, gpa: std.mem.Allocator) u64 {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const di = zbor.DataItem.new(data) catch return 1_000_000;
    const v = zbor.parse(T, di, .{ .allocator = arena.allocator() }) catch return 1_000_000;
    return v.len;
}

fn dictLen(data: []const u8, gpa: std.mem.Allocator) u64 {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const di = zbor.DataItem.new(data) catch return 1_000_000;
    var it = di.map() orelse return 1_000_000;
    var map = std.StringHashMap(u64).init(a);
    map.ensureTotalCapacity(@intCast(it.len)) catch return 1_000_000;
    while (it.next()) |pair| {
        const k = zbor.parse([]const u8, pair.key, .{ .allocator = a }) catch return 1_000_000;
        const v = zbor.parse(u64, pair.value, .{}) catch return 1_000_000;
        const gop = map.getOrPut(k) catch return 1_000_000;
        if (gop.found_existing) return 1_000_000; // a duplicate key
        gop.value_ptr.* = v;
    }
    return map.count();
}

pub fn main(init: std.process.Init) !void {
    const gpa = std.heap.c_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) {
        std.debug.print("usage: cbor-bench <case> <loops> <fixture_dir>\n", .{});
        std.process.exit(2);
    }
    const case = args[1];
    const loops = try std.fmt.parseInt(u64, args[2], 10);
    const fx = fixtureOf(case) orelse {
        std.debug.print("unknown case: {s}\n", .{case});
        std.process.exit(2);
    };
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}.cbor", .{ args[3], fx });
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, path, gpa, .unlimited);

    var sum: u64 = 0;
    if (std.mem.eql(u8, case, "bytes_encode")) {
        const blob = try zbor.parse([]const u8, try zbor.DataItem.new(data), .{ .allocator = gpa });
        for (0..loops) |_| sum +%= try encodeLen(gpa, blob, .{});
    } else if (std.mem.eql(u8, case, "bytes_parse")) {
        for (0..loops) |_| sum +%= parseLen([]const u8, data, gpa);
    } else if (std.mem.eql(u8, case, "records_encode")) {
        const rs = try zbor.parse([]const Rec, try zbor.DataItem.new(data), .{ .allocator = gpa });
        for (0..loops) |_| sum +%= try encodeLen(gpa, rs, .{ .slice_serialization_type = .TextString });
    } else if (std.mem.eql(u8, case, "records_parse") or std.mem.eql(u8, case, "unknown_parse")) {
        for (0..loops) |_| sum +%= parseLen([]const Rec, data, gpa);
    } else if (std.mem.eql(u8, case, "text_parse")) {
        for (0..loops) |_| sum +%= parseLen([]const []const u8, data, gpa);
    } else if (std.mem.eql(u8, case, "dict_parse")) {
        for (0..loops) |_| sum +%= dictLen(data, gpa);
    } else {
        std.debug.print("unsupported: {s}\n", .{case});
        std.process.exit(3);
    }
    @as(*volatile u64, &sink).* = sum;

    var buf: [256]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buf);
    try out.interface.print("{s} {d} {d}\n", .{ case, loops, sum });
    try out.interface.flush();
}

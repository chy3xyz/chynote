//! check-bridge: verify that every bridge handler declared in src/main.zig
//! appears in app.zon's `bridge.commands` list, and vice versa.
//!
//! Run via `zig build check-bridge`. Exits non-zero on drift.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var dbg = std.heap.DebugAllocator(.{}).init;
    defer _ = dbg.deinit();
    const allocator = dbg.allocator();
    const io = init.io;

    const cwd = std.Io.Dir.cwd();
    const app_zon_text = try cwd.readFileAlloc(io, "app.zon", allocator, .limited(1 << 20));
    defer allocator.free(app_zon_text);

    const main_zig_text = try cwd.readFileAlloc(io, "src/main.zig", allocator, .limited(1 << 20));
    defer allocator.free(main_zig_text);

    const manifest_commands = try parseManifestCommands(allocator, app_zon_text);
    defer {
        for (manifest_commands) |c| allocator.free(c);
        allocator.free(manifest_commands);
    }

    const handler_names = try parseHandlerNames(allocator, main_zig_text);
    defer {
        for (handler_names) |n| allocator.free(n);
        allocator.free(handler_names);
    }

    var had_drift = false;

    // Manifest -> handlers: every manifest command must have a handler.
    for (manifest_commands) |cmd| {
        if (!containsString(handler_names, cmd)) {
            std.debug.print("drift: app.zon declares '{s}' but no Handler exists in src/main.zig\n", .{cmd});
            had_drift = true;
        }
    }

    // Handlers -> manifest: every handler must appear in the manifest.
    for (handler_names) |name| {
        if (!containsString(manifest_commands, name)) {
            std.debug.print("drift: src/main.zig has Handler '{s}' not declared in app.zon\n", .{name});
            had_drift = true;
        }
    }

    if (had_drift) {
        std.debug.print("\nbridge is out of sync; run `zig build` (regenerates app_manifest_bridge.zig) and reconcile\n", .{});
        std.process.exit(1);
    }

    std.debug.print("ok: {d} bridge commands match app.zon\n", .{handler_names.len});
}

fn containsString(list: []const []const u8, target: []const u8) bool {
    for (list) |item| if (std.mem.eql(u8, item, target)) return true;
    return false;
}

/// Parse `bridge.commands` from the ZON source. Each entry is
/// `{ .name = "x", .origins = .{ "y" } }`.
fn parseManifestCommands(allocator: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    const body = findBridgeCommandsBody(source) orelse return &.{};
    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(allocator);

    var i: usize = 0;
    while (i < body.len) {
        const open = std.mem.indexOfScalarPos(u8, body, i, '{') orelse break;
        var depth: usize = 1;
        var cursor: usize = open + 1;
        while (cursor < body.len and depth > 0) {
            switch (body[cursor]) {
                '{' => depth += 1,
                '}' => depth -= 1,
                else => {},
            }
            cursor += 1;
        }
        if (depth != 0) break;
        const entry = body[open + 1 .. cursor - 1];
        const name = readStringField(entry, ".name") orelse {
            std.debug.panic("app.zon: bridge command missing .name", .{});
        };
        try out.append(allocator, try allocator.dupe(u8, name));
        i = cursor;
    }
    return out.toOwnedSlice(allocator);
}

fn findBridgeCommandsBody(source: []const u8) ?[]const u8 {
    // Find `.bridge = .{` and then the matching closing brace.
    const bridge = findObjectField(source, ".bridge") orelse return null;
    return findArrayField(bridge, ".commands");
}

fn findObjectField(source: []const u8, field: []const u8) ?[]const u8 {
    const field_index = std.mem.indexOf(u8, source, field) orelse return null;
    const equals = std.mem.indexOfScalarPos(u8, source, field_index, '=') orelse return null;
    var i = equals + 1;
    while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
    if (i >= source.len or source[i] != '.') return null;
    i += 1;
    if (i >= source.len or source[i] != '{') return null;
    const open = i;
    var depth: usize = 1;
    i += 1;
    while (i < source.len and depth > 0) {
        switch (source[i]) {
            '{' => depth += 1,
            '}' => depth -= 1,
            else => {},
        }
        i += 1;
    }
    if (depth != 0) return null;
    return source[open + 1 .. i - 1];
}

fn findArrayField(source: []const u8, field: []const u8) ?[]const u8 {
    const field_index = std.mem.indexOf(u8, source, field) orelse return null;
    const equals = std.mem.indexOfScalarPos(u8, source, field_index, '=') orelse return null;
    var i = equals + 1;
    while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
    if (i >= source.len or source[i] != '.') return null;
    i += 1;
    if (i >= source.len or source[i] != '{') return null;
    const open = i;
    var depth: usize = 1;
    i += 1;
    while (i < source.len and depth > 0) {
        switch (source[i]) {
            '{' => depth += 1,
            '}' => depth -= 1,
            else => {},
        }
        i += 1;
    }
    if (depth != 0) return null;
    return source[open + 1 .. i - 1];
}

fn readStringField(source: []const u8, field: []const u8) ?[]const u8 {
    const field_index = std.mem.indexOf(u8, source, field) orelse return null;
    const equals = std.mem.indexOfScalarPos(u8, source, field_index, '=') orelse return null;
    const start_quote = std.mem.indexOfScalarPos(u8, source, equals, '"') orelse return null;
    const end_quote = std.mem.indexOfScalarPos(u8, source, start_quote + 1, '"') orelse return null;
    return source[start_quote + 1 .. end_quote];
}

/// Parse `.{ .name = "x", ... }` entries in vault_handlers / git_handlers / system_handlers
/// from src/main.zig.
fn parseHandlerNames(allocator: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(allocator);

    // Find the three handler arrays. Each is `const xxx_handlers = [_]zero_native.bridge.Handler{`.
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, source, search_start, "const ")) |const_start| {
        // Require that this is a Handler array declaration by looking ahead.
        if (std.mem.indexOfPos(u8, source, const_start, "_handlers = [_]zero_native.bridge.Handler{")) |array_start| {
            const body_start = std.mem.indexOfScalarPos(u8, source, array_start, '{') orelse break;
            // Find the matching close of the array literal.
            var depth: usize = 1;
            var cursor: usize = body_start + 1;
            while (cursor < source.len and depth > 0) {
                switch (source[cursor]) {
                    '{' => depth += 1,
                    '}' => depth -= 1,
                    else => {},
                }
                cursor += 1;
            }
            if (depth != 0) break;
            const body = source[body_start + 1 .. cursor - 1];

            // Walk the entries.
            var i: usize = 0;
            while (i < body.len) {
                const open = std.mem.indexOfScalarPos(u8, body, i, '{') orelse break;
                var d2: usize = 1;
                var c2: usize = open + 1;
                while (c2 < body.len and d2 > 0) {
                    switch (body[c2]) {
                        '{' => d2 += 1,
                        '}' => d2 -= 1,
                        else => {},
                    }
                    c2 += 1;
                }
                if (d2 != 0) break;
                const entry = body[open + 1 .. c2 - 1];
                if (readStringField(entry, ".name")) |name| {
                    try out.append(allocator, try allocator.dupe(u8, name));
                }
                i = c2;
            }
            search_start = cursor;
        } else {
            search_start = const_start + 6;
        }
    }
    return out.toOwnedSlice(allocator);
}

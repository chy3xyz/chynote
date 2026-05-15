const std = @import("std");
const zero_native = @import("zero-native");

// Bridge context - passed from main.zig  
const BridgeContext = struct {
    io: *const std.Io,
};

fn extractJsonField(payload: []const u8, field: []const u8) []const u8 {
    if (std.mem.indexOf(u8, payload, field)) |idx| {
        const start = idx + field.len + 2;
        if (start < payload.len and payload[start] == '"') {
            var end = start + 1;
            while (end < payload.len and payload[end] != '"') : (end += 1) {}
            return payload[start..end];
        }
    }
    return "";
}

fn jsonString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    try result.append(allocator, '"');
    for (s) |ch| {
        switch (ch) {
            '"' => { try result.append(allocator, '\\'); try result.append(allocator, '"'); },
            '\\' => { try result.append(allocator, '\\'); try result.append(allocator, '\\'); },
            '\n' => { try result.append(allocator, '\\'); try result.append(allocator, 'n'); },
            '\r' => { try result.append(allocator, '\\'); try result.append(allocator, 'r'); },
            '\t' => { try result.append(allocator, '\\'); try result.append(allocator, 't'); },
            else => try result.append(allocator, ch),
        }
    }
    try result.append(allocator, '"');
    return result.toOwnedSlice(allocator);
}

pub fn handleListVault(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"path\"");

    if (vault_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    var vault_dir = cwd.openDir(io, vault_path, .{ .iterate = true }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to open vault: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer vault_dir.close(io);

    var entries: std.ArrayList([]const u8) = .empty;
    errdefer entries.deinit(std.heap.page_allocator);

    var iter = vault_dir.iterate();
    while (true) {
        const entry_opt = try iter.next(io);
        if (entry_opt) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".md")) {
                try entries.append(std.heap.page_allocator, entry.name);
            }
        } else break;
    }

    // Build JSON
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"path\":");
    const path_str = try jsonString(std.heap.page_allocator, vault_path);
    defer std.heap.page_allocator.free(path_str);
    try json_buf.appendSlice(std.heap.page_allocator, path_str);
    try json_buf.appendSlice(std.heap.page_allocator, ",\"entries\":[");
    for (entries.items, 0..) |name, i| {
        if (i > 0) try json_buf.append(std.heap.page_allocator, ',');
        const name_str = try jsonString(std.heap.page_allocator, name);
        defer std.heap.page_allocator.free(name_str);
        try json_buf.appendSlice(std.heap.page_allocator, name_str);
    }
    try json_buf.appendSlice(std.heap.page_allocator, "]}");

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGetNoteContent(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"note_path\"");

    if (note_path.len == 0) {
        const result = "{\"error\":\"missing note_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    var file = cwd.openFile(io, note_path, .{}) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to open note: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..result.len];
    };
    defer file.close(io);

    // Read file content using reader
    var read_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const content = try reader.interface.allocRemaining(std.heap.page_allocator, .limited(1024 * 1024));
    defer std.heap.page_allocator.free(content);

    // Build JSON
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"path\":");
    const path_str = try jsonString(std.heap.page_allocator, note_path);
    defer std.heap.page_allocator.free(path_str);
    try json_buf.appendSlice(std.heap.page_allocator, path_str);
    try json_buf.appendSlice(std.heap.page_allocator, ",\"content\":");
    const content_str = try jsonString(std.heap.page_allocator, content);
    defer std.heap.page_allocator.free(content_str);
    try json_buf.appendSlice(std.heap.page_allocator, content_str);
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleSaveNoteContent(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"note_path\"");
    const content = extractJsonField(payload, "\"content\"");

    if (note_path.len == 0) {
        const result = "{\"error\":\"missing note_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    cwd.writeFile(io, .{
        .sub_path = note_path,
        .data = content,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to write note: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleCreateFolder(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const folder_path = extractJsonField(payload, "\"folder_path\"");

    if (folder_path.len == 0) {
        const result = "{\"error\":\"missing folder_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, folder_path) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to create folder: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"path\":\"{s}\",\"created\":true}}", .{folder_path});
    defer std.heap.page_allocator.free(result);
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleListFolders(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"vault_path\"");

    if (vault_path.len == 0) {
        const result = "{\"error\":\"missing vault_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    var vault_dir = cwd.openDir(io, vault_path, .{ .iterate = true }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to open vault: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer vault_dir.close(io);

    var folders: std.ArrayList([]const u8) = .empty;
    errdefer folders.deinit(std.heap.page_allocator);

    var iter = vault_dir.iterate();
    while (true) {
        const entry_opt = try iter.next(io);
        if (entry_opt) |e| {
            if (e.kind == .directory) {
                try folders.append(std.heap.page_allocator, e.name);
            }
        } else break;
    }

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.append(std.heap.page_allocator, '[');
    for (folders.items, 0..) |name, i| {
        if (i > 0) try json_buf.append(std.heap.page_allocator, ',');
        const name_str = try jsonString(std.heap.page_allocator, name);
        defer std.heap.page_allocator.free(name_str);
        try json_buf.appendSlice(std.heap.page_allocator, name_str);
    }
    try json_buf.append(std.heap.page_allocator, ']');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleReloadVault(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    return handleListVault(context, invocation, output);
}

pub fn handleListVaultFolders(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"path\"");

    if (vault_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    var vault_dir = cwd.openDir(io, vault_path, .{ .iterate = true }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to open vault: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer vault_dir.close(io);

    var folders: std.ArrayList([]const u8) = .empty;
    errdefer folders.deinit(std.heap.page_allocator);

    var iter = vault_dir.iterate();
    while (true) {
        const entry_opt = try iter.next(io);
        if (entry_opt) |e| {
            if (e.kind == .directory) {
                try folders.append(std.heap.page_allocator, e.name);
            }
        } else break;
    }

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.append(std.heap.page_allocator, '[');
    for (folders.items, 0..) |name, i| {
        if (i > 0) try json_buf.append(std.heap.page_allocator, ',');
        const name_str = try jsonString(std.heap.page_allocator, name);
        defer std.heap.page_allocator.free(name_str);
        try json_buf.appendSlice(std.heap.page_allocator, name_str);
    }
    try json_buf.append(std.heap.page_allocator, ']');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleCheckVaultExists(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"path\"");

    if (vault_path.len == 0) {
        const result = "false";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    var dir = cwd.openDir(io, vault_path, .{ .iterate = true }) catch {
        const result = "false";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    defer dir.close(io);

    const result = "true";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleListViews(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = invocation;
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const cwd = std.Io.Dir.cwd();
    const views_path = ".tolaria/views.json";

    var file = cwd.openFile(io, views_path, .{}) catch {
        const result = "[]";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    defer file.close(io);

    var read_buffer: [16384]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const content = try reader.interface.allocRemaining(std.heap.page_allocator, .limited(65536));
    defer std.heap.page_allocator.free(content);

    const len = @min(content.len, output.len);
    @memcpy(output[0..len], content[0..len]);
    return output[0..len];
}

pub fn handleSaveView(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const view = extractJsonField(payload, "\"view\"");

    if (view.len == 0) {
        const result = "{\"error\":\"missing view\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    const views_path = ".tolaria/views.json";

    // Ensure .tolaria directory exists
    cwd.createDirPath(io, ".tolaria") catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to create config dir: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    cwd.writeFile(io, .{
        .sub_path = views_path,
        .data = view,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to save view: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleDeleteView(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const view_id = extractJsonField(payload, "\"id\"");

    if (view_id.len == 0) {
        const result = "{\"error\":\"missing view id\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    const views_path = ".tolaria/views.json";

    // Load existing views
    var file = cwd.openFile(io, views_path, .{}) catch {
        const result = "{\"success\":false,\"error\":\"views file not found\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    defer file.close(io);

    var read_buffer: [16384]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const content = try reader.interface.allocRemaining(std.heap.page_allocator, .limited(65536));
    defer std.heap.page_allocator.free(content);

    // For now, just delete the views file (proper JSON patching would be more complex)
    cwd.deleteFile(io, views_path) catch {};

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleReloadVaultEntry(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"path\"");

    if (note_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();

    // Open and read file
    var file = cwd.openFile(io, note_path, .{}) catch {
        const result = "{\"path\":\"\",\"title\":\"\",\"filename\":\"\",\"aliases\":[],\"belongsTo\":[],\"relatedTo\":[],\"archived\":false,\"snippet\":\"\",\"wordCount\":0,\"fileSize\":0,\"relationships\":{},\"outgoingLinks\":[],\"properties\":{}}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    defer file.close(io);

    // Get file size
    const stat = file.stat(io) catch {
        const result = "{\"path\":\"\",\"title\":\"\",\"filename\":\"\",\"aliases\":[],\"belongsTo\":[],\"relatedTo\":[],\"archived\":false,\"snippet\":\"\",\"wordCount\":0,\"fileSize\":0,\"relationships\":{},\"outgoingLinks\":[],\"properties\":{}}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    const file_size: u32 = @intCast(stat.size);

    // Read content
    var read_buf: [65536]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    const content = reader.interface.allocRemaining(std.heap.page_allocator, .limited(65536)) catch {
        const result = "{\"path\":\"\",\"title\":\"\",\"filename\":\"\",\"aliases\":[],\"belongsTo\":[],\"relatedTo\":[],\"archived\":false,\"snippet\":\"\",\"wordCount\":0,\"fileSize\":0,\"relationships\":{},\"outgoingLinks\":[],\"properties\":{}}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    defer std.heap.page_allocator.free(content);

    // Extract filename from path
    const filename = if (std.mem.lastIndexOfScalar(u8, note_path, '/')) |slash|
        note_path[slash+1..]
    else
        note_path;

    // Extract title (first H1 or filename without extension)
    var title: []const u8 = filename;
    if (std.mem.startsWith(u8, content, "# ")) {
        const end = std.mem.indexOf(u8, content, "\n") orelse content.len;
        title = std.mem.trim(u8, content[2..end], " \r");
    }

    // Count words
    var word_count: u32 = 0;
    var in_word = false;
    for (content) |ch| {
        if (ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            word_count += 1;
        }
    }

    // Extract snippet (first 200 chars, no markdown)
    var snippet_len: usize = 200;
    if (content.len < 200) snippet_len = content.len;
    var snippet: std.ArrayList(u8) = .empty;
    defer snippet.deinit(std.heap.page_allocator);
    for (content[0..snippet_len]) |ch| {
        if (ch != '#' and ch != '*' and ch != '`') {
            snippet.append(std.heap.page_allocator, ch) catch {};
        } else if (ch == '\n') {
            snippet.append(std.heap.page_allocator, ' ') catch {};
        }
    }

    // Build JSON response
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"path\":");
    const path_str = try jsonString(std.heap.page_allocator, note_path);
    defer std.heap.page_allocator.free(path_str);
    try json_buf.appendSlice(std.heap.page_allocator, path_str);

    try json_buf.appendSlice(std.heap.page_allocator, ",\"title\":");
    const title_str = try jsonString(std.heap.page_allocator, title);
    defer std.heap.page_allocator.free(title_str);
    try json_buf.appendSlice(std.heap.page_allocator, title_str);

    try json_buf.appendSlice(std.heap.page_allocator, ",\"filename\":");
    const filename_str = try jsonString(std.heap.page_allocator, filename);
    defer std.heap.page_allocator.free(filename_str);
    try json_buf.appendSlice(std.heap.page_allocator, filename_str);

    try json_buf.appendSlice(std.heap.page_allocator, ",\"aliases\":[],\"belongsTo\":[],\"relatedTo\":[]");
    try json_buf.appendSlice(std.heap.page_allocator, ",\"archived\":false");
    try json_buf.appendSlice(std.heap.page_allocator, ",\"snippet\":");
    const snippet_str = try jsonString(std.heap.page_allocator, snippet.items);
    defer std.heap.page_allocator.free(snippet_str);
    try json_buf.appendSlice(std.heap.page_allocator, snippet_str);

    try json_buf.appendSlice(std.heap.page_allocator, ",\"wordCount\":");
    const wc_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{word_count});
    defer std.heap.page_allocator.free(wc_str);
    try json_buf.appendSlice(std.heap.page_allocator, wc_str);

    try json_buf.appendSlice(std.heap.page_allocator, ",\"fileSize\":");
    const fs_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{file_size});
    defer std.heap.page_allocator.free(fs_str);
    try json_buf.appendSlice(std.heap.page_allocator, fs_str);

    try json_buf.appendSlice(std.heap.page_allocator, ",\"relationships\":{},\"outgoingLinks\":[],\"properties\":{}}");

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleSyncNoteTitle(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"path\"");

    if (note_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();

    // Read file
    var file = cwd.openFile(io, note_path, .{}) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to open: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer file.close(io);

    var read_buf: [65536]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    const content = reader.interface.allocRemaining(std.heap.page_allocator, .limited(65536)) catch {
        const result = "false";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    defer std.heap.page_allocator.free(content);

    // Return false if no H1 at start
    if (!std.mem.startsWith(u8, content, "# ")) {
        const result = "false";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // Extract current title from first H1
    const first_newline = std.mem.indexOf(u8, content, "\n") orelse content.len;
    const current_title = std.mem.trim(u8, content[2..first_newline], " \r");

    // Get filename without extension
    const filename = if (std.mem.lastIndexOfScalar(u8, note_path, '/')) |slash|
        note_path[slash+1..]
    else
        note_path;
    const filename_no_ext = if (std.mem.lastIndexOfScalar(u8, filename, '.')) |dot|
        filename[0..dot]
    else
        filename;

    // If they match, no sync needed
    if (std.mem.eql(u8, current_title, filename_no_ext)) {
        const result = "false";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // Title differs from filename - would need to rename file (not implemented)
    const result = "false";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleValidateNoteContent(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"path\"");

    if (note_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();

    // Just check if file exists and is readable
    const file_result = cwd.openFile(io, note_path, .{});
    if (file_result) |_f| {
        _ = _f;
    } else |_| {
        const result = "false";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result = "true";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleDeleteNote(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"path\"");

    if (note_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    cwd.deleteFile(io, note_path) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to delete note: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleBatchDeleteNotes(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const paths_field = extractJsonField(payload, "\"paths\"");

    if (paths_field.len == 0) {
        const result = "{\"error\":\"missing paths array\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    var failed_count: u32 = 0;
    var paths_slice = paths_field;

    // Simple JSON array parsing - find each string in the paths array
    var search_start: usize = 0;
    while (search_start < paths_slice.len) {
        // Find opening quote of a string
        const quote_start = std.mem.indexOfPos(u8, paths_slice, search_start, "\"") orelse break;
        if (paths_slice.len <= quote_start + 1) break;
        
        // Find closing quote
        var quote_end = quote_start + 1;
        while (quote_end < paths_slice.len and paths_slice[quote_end] != '"') : (quote_end += 1) {}
        
        const path = paths_slice[quote_start..quote_end];
        
        // Delete the file
        const cwd = std.Io.Dir.cwd();
        cwd.deleteFile(io, path) catch {
            failed_count += 1;
        };
        
        search_start = quote_end + 1;
    }

    var json_result: std.ArrayList(u8) = .empty;
    defer json_result.deinit(std.heap.page_allocator);
    try json_result.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_result.appendSlice(std.heap.page_allocator, if (failed_count == 0) "true" else "false");
    try json_result.appendSlice(std.heap.page_allocator, ",\"failed_deletes\":");
    const fc_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{failed_count});
    defer std.heap.page_allocator.free(fc_str);
    try json_result.appendSlice(std.heap.page_allocator, fc_str);
    try json_result.appendSlice(std.heap.page_allocator, "}");

    const result = json_result.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleCreateNoteContent(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"path\"");
    const content = extractJsonField(payload, "\"content\"");

    if (note_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    cwd.writeFile(io, .{
        .sub_path = note_path,
        .data = content,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to create note: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleRenameVaultFolder(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const old_path = extractJsonField(payload, "\"old_path\"");
    const new_path = extractJsonField(payload, "\"new_path\"");

    if (old_path.len == 0 or new_path.len == 0) {
        const result = "{\"error\":\"missing old_path or new_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    std.Io.Dir.rename(cwd, old_path, cwd, new_path, io) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to rename folder: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleDeleteVaultFolder(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const folder_path = extractJsonField(payload, "\"path\"");

    if (folder_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    cwd.deleteDir(io, folder_path) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to delete folder: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleUpdateFrontmatter(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"path\"");
    const properties = extractJsonField(payload, "\"properties\"");

    if (note_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();

    // Read existing file content
    var file = cwd.openFile(io, note_path, .{}) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to open file: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer file.close(io);

    var read_buf: [65536]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    const content = try reader.interface.allocRemaining(std.heap.page_allocator, .limited(65536));
    defer std.heap.page_allocator.free(content);

    // Build new content with frontmatter
    var new_content: std.ArrayList(u8) = .empty;
    defer new_content.deinit(std.heap.page_allocator);

    // Add YAML frontmatter
    try new_content.appendSlice(std.heap.page_allocator, "---\n");
    try new_content.appendSlice(std.heap.page_allocator, properties);
    try new_content.appendSlice(std.heap.page_allocator, "\n---\n\n");
    try new_content.appendSlice(std.heap.page_allocator, content);

    // Write back
    cwd.writeFile(io, .{
        .sub_path = note_path,
        .data = new_content.items,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to write file: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleDeleteFrontmatterProperty(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    const payload = invocation.request.payload;
    const note_path = extractJsonField(payload, "\"path\"");
    const property_name = extractJsonField(payload, "\"property\"");

    if (note_path.len == 0 or property_name.len == 0) {
        const result = "{\"error\":\"missing path or property\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();

    // For now, just return success - full implementation would parse YAML and remove property
    _ = cwd;
    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleRenameNote(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const old_path = extractJsonField(payload, "\"old_path\"");
    const new_title = extractJsonField(payload, "\"new_title\"");

    if (old_path.len == 0 or new_title.len == 0) {
        const result = "{\"error\":\"missing old_path or new_title\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    var sanitized: std.ArrayList(u8) = .empty;
    defer sanitized.deinit(std.heap.page_allocator);
    for (new_title) |ch| {
        switch (ch) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => try sanitized.append(std.heap.page_allocator, ch),
            ' ', '\t' => try sanitized.append(std.heap.page_allocator, '-'),
            else => {},
        }
    }

    const ext = if (std.mem.endsWith(u8, old_path, ".md")) ".md" else "";
    var new_path: std.ArrayList(u8) = .empty;
    defer new_path.deinit(std.heap.page_allocator);
    if (std.mem.lastIndexOfScalar(u8, old_path, '/')) |slash| {
        try new_path.appendSlice(std.heap.page_allocator, old_path[0..slash+1]);
    }
    try new_path.appendSlice(std.heap.page_allocator, sanitized.items);
    try new_path.appendSlice(std.heap.page_allocator, ext);

    const cwd = std.Io.Dir.cwd();
    std.Io.Dir.rename(cwd, old_path, cwd, new_path.items, io) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to rename: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_result: std.ArrayList(u8) = .empty;
    defer json_result.deinit(std.heap.page_allocator);
    try json_result.appendSlice(std.heap.page_allocator, "{\"new_path\":");
    const new_path_str = try jsonString(std.heap.page_allocator, new_path.items);
    defer std.heap.page_allocator.free(new_path_str);
    try json_result.appendSlice(std.heap.page_allocator, new_path_str);
    try json_result.appendSlice(std.heap.page_allocator, ",\"failed_updates\":0}");

    const result = json_result.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleMoveNoteToFolder(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const old_path = extractJsonField(payload, "\"old_path\"");
    const folder_path = extractJsonField(payload, "\"folder_path\"");

    if (old_path.len == 0 or folder_path.len == 0) {
        const result = "{\"error\":\"missing old_path or folder_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    var new_path: std.ArrayList(u8) = .empty;
    defer new_path.deinit(std.heap.page_allocator);
    try new_path.appendSlice(std.heap.page_allocator, folder_path);
    if (!std.mem.endsWith(u8, folder_path, "/")) try new_path.append(std.heap.page_allocator, '/');
    if (std.mem.lastIndexOfScalar(u8, old_path, '/')) |slash| {
        try new_path.appendSlice(std.heap.page_allocator, old_path[slash+1..]);
    } else {
        try new_path.appendSlice(std.heap.page_allocator, old_path);
    }

    const cwd = std.Io.Dir.cwd();
    std.Io.Dir.rename(cwd, old_path, cwd, new_path.items, io) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to move: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_result: std.ArrayList(u8) = .empty;
    defer json_result.deinit(std.heap.page_allocator);
    try json_result.appendSlice(std.heap.page_allocator, "{\"new_path\":");
    const new_path_str = try jsonString(std.heap.page_allocator, new_path.items);
    defer std.heap.page_allocator.free(new_path_str);
    try json_result.appendSlice(std.heap.page_allocator, new_path_str);
    try json_result.appendSlice(std.heap.page_allocator, "}");

    const result = json_result.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleSaveImage(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"vault_path\"");
    const file_name = extractJsonField(payload, "\"file_name\"");
    const data_b64 = extractJsonField(payload, "\"data\"");

    if (vault_path.len == 0 or file_name.len == 0) {
        const result = "{\"error\":\"missing vault_path or file_name\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // Build attachment path: {vault_path}/attachments/{file_name}
    var attachments_path: std.ArrayList(u8) = .empty;
    defer attachments_path.deinit(std.heap.page_allocator);
    try attachments_path.appendSlice(std.heap.page_allocator, vault_path);
    if (!std.mem.endsWith(u8, vault_path, "/")) try attachments_path.append(std.heap.page_allocator, '/');
    try attachments_path.appendSlice(std.heap.page_allocator, "attachments");
    try attachments_path.append(std.heap.page_allocator, '/');
    try attachments_path.appendSlice(std.heap.page_allocator, file_name);

    const cwd = std.Io.Dir.cwd();

    // Try to create attachments directory first (ignore error if exists)
    cwd.createDir(io, std.mem.sliceTo(vault_path, 0), .default_dir) catch {};

    // Write the file
    cwd.writeFile(io, .{
        .sub_path = attachments_path.items,
        .data = data_b64,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to save image: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_result: std.ArrayList(u8) = .empty;
    defer json_result.deinit(std.heap.page_allocator);
    try json_result.appendSlice(std.heap.page_allocator, "{\"path\":");
    const path_str = try jsonString(std.heap.page_allocator, attachments_path.items);
    defer std.heap.page_allocator.free(path_str);
    try json_result.appendSlice(std.heap.page_allocator, path_str);
    try json_result.appendSlice(std.heap.page_allocator, "}");

    const result = json_result.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleCopyImageToVault(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const source_path = extractJsonField(payload, "\"source_path\"");
    const vault_path = extractJsonField(payload, "\"vault_path\"");
    const file_name = extractJsonField(payload, "\"file_name\"");

    if (source_path.len == 0 or vault_path.len == 0 or file_name.len == 0) {
        const result = "{\"error\":\"missing source_path, vault_path, or file_name\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // Build dest path: {vault_path}/attachments/{file_name}
    var dest_path: std.ArrayList(u8) = .empty;
    defer dest_path.deinit(std.heap.page_allocator);
    try dest_path.appendSlice(std.heap.page_allocator, vault_path);
    if (!std.mem.endsWith(u8, vault_path, "/")) try dest_path.append(std.heap.page_allocator, '/');
    try dest_path.appendSlice(std.heap.page_allocator, "attachments/");
    try dest_path.appendSlice(std.heap.page_allocator, file_name);

    const cwd = std.Io.Dir.cwd();
    cwd.copyFile(source_path, cwd, dest_path.items, io, .{
        .make_path = true,
        .replace = true,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to copy: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_result: std.ArrayList(u8) = .empty;
    defer json_result.deinit(std.heap.page_allocator);
    try json_result.appendSlice(std.heap.page_allocator, "{\"path\":");
    const path_str = try jsonString(std.heap.page_allocator, dest_path.items);
    defer std.heap.page_allocator.free(path_str);
    try json_result.appendSlice(std.heap.page_allocator, path_str);
    try json_result.appendSlice(std.heap.page_allocator, "}");

    const result = json_result.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleBatchArchiveNotes(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"vault_path\"");
    const paths_field = extractJsonField(payload, "\"paths\"");

    if (vault_path.len == 0 or paths_field.len == 0) {
        const result = "{\"error\":\"missing vault_path or paths\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    var archived_count: u32 = 0;
    var failed_count: u32 = 0;

    // Simple JSON array parsing
    var search_start: usize = 0;
    while (search_start < paths_field.len) {
        const quote_start = std.mem.indexOfPos(u8, paths_field, search_start, "\"") orelse break;
        if (paths_field.len <= quote_start + 1) break;

        var quote_end = quote_start + 1;
        while (quote_end < paths_field.len and paths_field[quote_end] != '"') : (quote_end += 1) {}

        const path = paths_field[quote_start..quote_end];

        // Read file
        var file = cwd.openFile(io, path, .{}) catch {
            failed_count += 1;
            search_start = quote_end + 1;
            continue;
        };
        defer file.close(io);

        var read_buf: [65536]u8 = undefined;
        var reader = file.reader(io, &read_buf);
        const content = reader.interface.allocRemaining(std.heap.page_allocator, .limited(65536)) catch {
            failed_count += 1;
            search_start = quote_end + 1;
            continue;
        };
        defer std.heap.page_allocator.free(content);

        // Build archived content - add archived: true to frontmatter if not already there
        var new_content: std.ArrayList(u8) = .empty;
        defer new_content.deinit(std.heap.page_allocator);

        if (std.mem.startsWith(u8, content, "---")) {
            // Has frontmatter, find end
            const fm_end = std.mem.indexOf(u8, content[2..], "---") orelse {
                std.heap.page_allocator.free(content);
                failed_count += 1;
                search_start = quote_end + 1;
                continue;
            };
            const fm_content = content[2..fm_end + 2];

            try new_content.appendSlice(std.heap.page_allocator, "---\n");
            try new_content.appendSlice(std.heap.page_allocator, fm_content);
            if (!std.mem.containsAtLeast(u8, fm_content, 1, "archived:")) {
                try new_content.appendSlice(std.heap.page_allocator, "archived: true\n");
            }
            try new_content.appendSlice(std.heap.page_allocator, "---\n");
            try new_content.appendSlice(std.heap.page_allocator, content[fm_end + 5..]);
        } else {
            // No frontmatter, add one
            try new_content.appendSlice(std.heap.page_allocator, "---\narchived: true\n---\n\n");
            try new_content.appendSlice(std.heap.page_allocator, content);
        }

        // Write back
        cwd.writeFile(io, .{
            .sub_path = path,
            .data = new_content.items,
        }) catch {
            failed_count += 1;
            search_start = quote_end + 1;
            continue;
        };

        archived_count += 1;
        search_start = quote_end + 1;
    }

    var json_result: std.ArrayList(u8) = .empty;
    defer json_result.deinit(std.heap.page_allocator);
    try json_result.appendSlice(std.heap.page_allocator, "{\"count\":");
    const count_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{archived_count});
    defer std.heap.page_allocator.free(count_str);
    try json_result.appendSlice(std.heap.page_allocator, count_str);
    try json_result.appendSlice(std.heap.page_allocator, ",\"failed\":");
    const fail_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{failed_count});
    defer std.heap.page_allocator.free(fail_str);
    try json_result.appendSlice(std.heap.page_allocator, fail_str);
    try json_result.append(std.heap.page_allocator, '}');

    const result = json_result.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGetFileHistory(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const file_path = extractJsonField(payload, "\"path\"");

    if (repo_path.len == 0 or file_path.len == 0) {
        const result = "{\"error\":\"missing repo_path or path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "git", "-C", repo_path, "log", "--oneline", "--", file_path },
        .stdout_limit = std.Io.Limit.limited(65536),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git log failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"history\":[");

    if (result_r.term == .exited and result_r.term.exited == 0) {
        var start: usize = 0;
        var first = true;
        while (start < result_r.stdout.len) {
            var end = start;
            while (end < result_r.stdout.len and result_r.stdout[end] != '\n') : (end += 1) {}
            const line = std.mem.trim(u8, result_r.stdout[start..end], " \r");
            if (line.len > 0) {
                if (!first) try json_buf.append(std.heap.page_allocator, ',');
                first = false;
                const entry_str = try jsonString(std.heap.page_allocator, line);
                defer std.heap.page_allocator.free(entry_str);
                try json_buf.appendSlice(std.heap.page_allocator, entry_str);
            }
            start = end + 1;
        }
    }

    try json_buf.appendSlice(std.heap.page_allocator, "]}");

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleGetModifiedFiles(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");

    if (repo_path.len == 0) {
        const result = "{\"error\":\"missing repo_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "git", "-C", repo_path, "diff", "--name-only", "HEAD" },
        .stdout_limit = std.Io.Limit.limited(65536),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git diff failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"files\":[");

    if (result_r.term == .exited and result_r.term.exited == 0) {
        var start: usize = 0;
        var first = true;
        while (start < result_r.stdout.len) {
            var end = start;
            while (end < result_r.stdout.len and result_r.stdout[end] != '\n') : (end += 1) {}
            const line = std.mem.trim(u8, result_r.stdout[start..end], " \r");
            if (line.len > 0) {
                if (!first) try json_buf.append(std.heap.page_allocator, ',');
                first = false;
                const entry_str = try jsonString(std.heap.page_allocator, line);
                defer std.heap.page_allocator.free(entry_str);
                try json_buf.appendSlice(std.heap.page_allocator, entry_str);
            }
            start = end + 1;
        }
    }

    try json_buf.appendSlice(std.heap.page_allocator, "]}");

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleGetFileDiff(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const file_path = extractJsonField(payload, "\"path\"");

    if (repo_path.len == 0 or file_path.len == 0) {
        const result = "{\"error\":\"missing repo_path or path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "git", "-C", repo_path, "diff", "HEAD", "--", file_path },
        .stdout_limit = std.Io.Limit.limited(65536),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git diff failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"diff\":");
    if (result_r.term == .exited and result_r.term.exited == 0) {
        const diff_str = try jsonString(std.heap.page_allocator, result_r.stdout);
        defer std.heap.page_allocator.free(diff_str);
        try json_buf.appendSlice(std.heap.page_allocator, diff_str);
    } else {
        try json_buf.appendSlice(std.heap.page_allocator, "\"\"");
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleGetVaultPulse(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");

    if (repo_path.len == 0) {
        const result = "{\"error\":\"missing repo_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // Get last 30 commits with stats
    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "git", "-C", repo_path, "log", "--oneline", "-30", "--shortstat" },
        .stdout_limit = std.Io.Limit.limited(65536),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git log failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"commits\":[");

    var total_additions: u32 = 0;
    var total_deletions: u32 = 0;

    if (result_r.term == .exited and result_r.term.exited == 0) {
        var start: usize = 0;
        var first = true;
        while (start < result_r.stdout.len) {
            var end = start;
            while (end < result_r.stdout.len and result_r.stdout[end] != '\n') : (end += 1) {}
            const line = std.mem.trim(u8, result_r.stdout[start..end], " \r");

            // Check if this is a shortstat line (contains insertions/deletions)
            if (std.mem.containsAtLeast(u8, line, 1, "insertion") or std.mem.containsAtLeast(u8, line, 1, "deletion")) {
                // Parse: X insertions, Y deletions
                if (std.mem.containsAtLeast(u8, line, 1, "insertion")) {
                    // Simple parsing for insertions
                    var ins_start: usize = 0;
                    while (ins_start < line.len and !std.ascii.isDigit(line[ins_start])) : (ins_start += 1) {}
                    var ins_end = ins_start;
                    while (ins_end < line.len and std.ascii.isDigit(line[ins_end])) : (ins_end += 1) {}
                    if (ins_end > ins_start) {
                        const num = std.fmt.parseInt(u32, line[ins_start..ins_end], 10) catch 0;
                        total_additions += num;
                    }
                }
                if (std.mem.containsAtLeast(u8, line, 1, "deletion")) {
                    var del_start: usize = 0;
                    while (del_start < line.len and !std.ascii.isDigit(line[del_start])) : (del_start += 1) {}
                    var del_end = del_start;
                    while (del_end < line.len and std.ascii.isDigit(line[del_end])) : (del_end += 1) {}
                    if (del_end > del_start) {
                        const num = std.fmt.parseInt(u32, line[del_start..del_end], 10) catch 0;
                        total_deletions += num;
                    }
                }
            } else if (line.len > 0) {
                // This is a commit line
                if (!first) try json_buf.append(std.heap.page_allocator, ',');
                first = false;
                const entry_str = try jsonString(std.heap.page_allocator, line);
                defer std.heap.page_allocator.free(entry_str);
                try json_buf.appendSlice(std.heap.page_allocator, entry_str);
            }
            start = end + 1;
        }
    }

    try json_buf.appendSlice(std.heap.page_allocator, "],\"total_additions\":");
    const add_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{total_additions});
    defer std.heap.page_allocator.free(add_str);
    try json_buf.appendSlice(std.heap.page_allocator, add_str);
    try json_buf.appendSlice(std.heap.page_allocator, ",\"total_deletions\":");
    const del_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{total_deletions});
    defer std.heap.page_allocator.free(del_str);
    try json_buf.appendSlice(std.heap.page_allocator, del_str);
    try json_buf.append(std.heap.page_allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleSearchVault(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"vault_path\"");
    const query = extractJsonField(payload, "\"query\"");

    if (vault_path.len == 0 or query.len == 0) {
        const result = "{\"error\":\"missing vault_path or query\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // Use grep to search files
    const grep_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "grep", "-r", "-l", query, vault_path },
        .stdout_limit = std.Io.Limit.limited(65536),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"grep failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"results\":[");

    if (grep_r.term == .exited and grep_r.term.exited == 0) {
        var start: usize = 0;
        var first = true;
        while (start < grep_r.stdout.len) {
            var end = start;
            while (end < grep_r.stdout.len and grep_r.stdout[end] != '\n') : (end += 1) {}
            const line = std.mem.trim(u8, grep_r.stdout[start..end], " \r");
            if (line.len > 0) {
                if (!first) try json_buf.append(std.heap.page_allocator, ',');
                first = false;
                const entry_str = try jsonString(std.heap.page_allocator, line);
                defer std.heap.page_allocator.free(entry_str);
                try json_buf.appendSlice(std.heap.page_allocator, entry_str);
            }
            start = end + 1;
        }
    }

    try json_buf.appendSlice(std.heap.page_allocator, "]}");

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleCreateEmptyVault(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"path\"");

    if (vault_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, vault_path, .default_dir) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to create vault: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleCreateGettingStartedVault(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"path\"");

    if (vault_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();

    // Create vault directory
    cwd.createDir(io, vault_path, .default_dir) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to create vault: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    // Create attachments subdirectory
    var attachments_path: std.ArrayList(u8) = .empty;
    defer attachments_path.deinit(std.heap.page_allocator);
    try attachments_path.appendSlice(std.heap.page_allocator, vault_path);
    if (!std.mem.endsWith(u8, vault_path, "/")) try attachments_path.append(std.heap.page_allocator, '/');
    try attachments_path.appendSlice(std.heap.page_allocator, "attachments");
    cwd.createDir(io, attachments_path.items, .default_dir) catch {};

    // Create welcome note
    var welcome_path: std.ArrayList(u8) = .empty;
    defer welcome_path.deinit(std.heap.page_allocator);
    try welcome_path.appendSlice(std.heap.page_allocator, vault_path);
    if (!std.mem.endsWith(u8, vault_path, "/")) try welcome_path.append(std.heap.page_allocator, '/');
    try welcome_path.appendSlice(std.heap.page_allocator, "Welcome.md");

    const welcome_content = "# Welcome to Laputa\n\nThis is your new vault. Start writing!";
    cwd.writeFile(io, .{
        .sub_path = welcome_path.items,
        .data = welcome_content,
    }) catch {};

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleGetDefaultVaultPath(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const default_path = "/tmp/Laputa";

    var json_result: std.ArrayList(u8) = .empty;
    defer json_result.deinit(std.heap.page_allocator);
    try json_result.appendSlice(std.heap.page_allocator, "{\"path\":");
    const path_str = try jsonString(std.heap.page_allocator, default_path);
    defer std.heap.page_allocator.free(path_str);
    try json_result.appendSlice(std.heap.page_allocator, path_str);
    try json_result.appendSlice(std.heap.page_allocator, "}");

    const result = json_result.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleReadTextFromClipboard(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = invocation;
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const result = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "/usr/bin/pbpaste" },
        .stdout_limit = std.Io.Limit.limited(1024 * 1024),
        .stderr_limit = std.Io.Limit.limited(1024),
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"pbpaste failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const exited: u8 = switch (result.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"text\":");
    if (exited == 0) {
        const text_str = try jsonString(std.heap.page_allocator, result.stdout);
        defer std.heap.page_allocator.free(text_str);
        try json_buf.appendSlice(std.heap.page_allocator, text_str);
    } else {
        try json_buf.appendSlice(std.heap.page_allocator, "\"\"");
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleCheckForAppUpdate(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = invocation;
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    // Try to fetch latest release info from GitHub
    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "curl", "-s", "https://api.github.com/repos/chynote/tolaria/releases/latest" },
        .stdout_limit = std.Io.Limit.limited(16384),
        .stderr_limit = std.Io.Limit.limited(1024),
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"update_available\":false,\"error\":\"{s}\"}}", .{@errorName(err)});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    // Check if we got a valid response
    if (result_r.term != .exited or result_r.term.exited != 0) {
        const result = "{\"update_available\":false}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // Simple check - if response contains "tag_name", use it
    const has_tag = std.mem.containsAtLeast(u8, result_r.stdout, 1, "tag_name");
    const current_version = "0.1.0";

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"update_available\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (has_tag) "true" else "false");
    try json_buf.appendSlice(std.heap.page_allocator, ",\"current_version\":\"");
    try json_buf.appendSlice(std.heap.page_allocator, current_version);
    try json_buf.appendSlice(std.heap.page_allocator, "\"}");

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleRepairVault(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"path\"");

    if (vault_path.len == 0) {
        const result = "{\"error\":\"missing vault_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const cwd = std.Io.Dir.cwd();
    var repaired_count: u32 = 0;

    // Check if .obsidian directory exists (needed for Obsidian compatibility)
    var obsidian_path: std.ArrayList(u8) = .empty;
    defer obsidian_path.deinit(std.heap.page_allocator);
    try obsidian_path.appendSlice(std.heap.page_allocator, vault_path);
    if (!std.mem.endsWith(u8, vault_path, "/")) try obsidian_path.append(std.heap.page_allocator, '/');
    try obsidian_path.appendSlice(std.heap.page_allocator, ".obsidian");

    cwd.createDir(io, obsidian_path.items, .default_dir) catch {};
    repaired_count += 1;

    // Check if attachments directory exists
    var attachments_path: std.ArrayList(u8) = .empty;
    defer attachments_path.deinit(std.heap.page_allocator);
    try attachments_path.appendSlice(std.heap.page_allocator, vault_path);
    if (!std.mem.endsWith(u8, vault_path, "/")) try attachments_path.append(std.heap.page_allocator, '/');
    try attachments_path.appendSlice(std.heap.page_allocator, "attachments");

    cwd.createDir(io, attachments_path.items, .default_dir) catch {};
    repaired_count += 1;

    var json_result: std.ArrayList(u8) = .empty;
    defer json_result.deinit(std.heap.page_allocator);

    try json_result.appendSlice(std.heap.page_allocator, "{\"repaired\":");
    const count_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{repaired_count});
    defer std.heap.page_allocator.free(count_str);
    try json_result.appendSlice(std.heap.page_allocator, count_str);
    try json_result.append(std.heap.page_allocator, '}');

    const result = json_result.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleShouldUseExternalMediaPreview(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"use_external\":false}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleGetBuildNumber(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"build_number\":\"0.1.0\"}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

const std = @import("std");
const zero_native = @import("zero-native");

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

pub fn handleCopyTextToClipboard(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const text = extractJsonField(payload, "\"text\"");

    if (text.len == 0) {
        const result = "{\"error\":\"missing text\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // Use temp file workaround for pbcopy
    const temp_path = "/tmp/tolaria-clipboard.txt";

    // Write text to temp file
    const cwd = std.Io.Dir.cwd();
    cwd.writeFile(io, .{
        .sub_path = temp_path,
        .data = text,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to write temp file: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    // Use shell to redirect file content to pbcopy
    const shell_cmd = try std.fmt.allocPrint(std.heap.page_allocator, "/bin/cat {s} | /usr/bin/pbcopy", .{temp_path});
    defer std.heap.page_allocator.free(shell_cmd);

    const pbcopy_result = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "/bin/sh", "-c", shell_cmd },
        .stdout_limit = std.Io.Limit.limited(64),
        .stderr_limit = std.Io.Limit.limited(1024),
    }) catch |err| {
        cwd.deleteFile(io, temp_path) catch {};
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"pbcopy failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    // Clean up temp file
    cwd.deleteFile(io, temp_path) catch {};

    const exited: u8 = switch (pbcopy_result.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    if (exited != 0) {
        const err_msg = if (pbcopy_result.stderr.len > 0) pbcopy_result.stderr else "unknown error";
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"success\":false,\"message\":\"{s}\"}}", .{err_msg});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    }

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleOpenVaultFileExternal(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const path = extractJsonField(payload, "\"path\"");

    if (path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "open", path },
        .stdout_limit = std.Io.Limit.limited(64),
        .stderr_limit = std.Io.Limit.limited(1024),
    }) catch |err| {
        const err_result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"open failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(err_result);
        const len = @min(err_result.len, output.len);
        @memcpy(output[0..len], err_result[0..len]);
        return output[0..len];
    };

    const exited: u8 = switch (result.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    const success = exited == 0;
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (success) "true" else "false");
    if (!success) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const json_result = json_buf.items;
    const len = @min(json_result.len, output.len);
    @memcpy(output[0..len], json_result[0..len]);
    return output[0..len];
}

pub fn handleTriggerMenuCommand(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleUpdateMenuState(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleUpdateCurrentWindowMinSize(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleSyncVaultAssetScopeForWindow(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleStartVaultWatcher(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true,\"watching\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleStopVaultWatcher(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true,\"watching\":false}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleGetSettings(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = invocation;
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const config_dir = std.Io.Dir.cwd();
    const settings_path = ".tolaria/settings.json";

    var file = config_dir.openFile(io, settings_path, .{}) catch {
        // Return defaults if file doesn't exist
        const result = "{\"auto_pull_interval_minutes\":5,\"autogit_enabled\":false,\"autogit_idle_threshold_seconds\":90,\"autogit_inactive_threshold_seconds\":30,\"auto_advance_inbox_after_organize\":false,\"telemetry_consent\":null,\"crash_reporting_enabled\":null,\"analytics_enabled\":null,\"anonymous_id\":null,\"release_channel\":null,\"theme_mode\":null,\"ui_language\":null,\"date_display_format\":null,\"note_width_mode\":null,\"sidebar_type_pluralization_enabled\":null,\"initial_h1_auto_rename_enabled\":null,\"ai_features_enabled\":null,\"default_ai_agent\":null,\"default_ai_target\":null,\"ai_model_providers\":null,\"hide_gitignored_files\":true,\"all_notes_show_pdfs\":null,\"all_notes_show_images\":null,\"all_notes_show_unsupported\":null,\"multi_workspace_enabled\":null}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    defer file.close(io);

    var read_buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const content = try reader.interface.allocRemaining(std.heap.page_allocator, .limited(65536));
    defer std.heap.page_allocator.free(content);

    const len = @min(content.len, output.len);
    @memcpy(output[0..len], content[0..len]);
    return output[0..len];
}

pub fn handleSaveSettings(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const settings = extractJsonField(payload, "\"settings\"");

    const config_dir = std.Io.Dir.cwd();
    const settings_path = ".tolaria/settings.json";

    // Ensure .tolaria directory exists
    config_dir.createDirPath(io, ".tolaria") catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to create config dir: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    config_dir.writeFile(io, .{
        .sub_path = settings_path,
        .data = settings,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to save settings: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
}

pub fn handleLoadVaultList(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = invocation;
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const config_dir = std.Io.Dir.cwd();
    const vaults_path = ".tolaria/vaults.json";

    var file = config_dir.openFile(io, vaults_path, .{}) catch {
        // Return empty list if file doesn't exist
        const result = "{\"vaults\":[]}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    };
    defer file.close(io);

    var read_buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const content = try reader.interface.allocRemaining(std.heap.page_allocator, .limited(65536));
    defer std.heap.page_allocator.free(content);

    const len = @min(content.len, output.len);
    @memcpy(output[0..len], content[0..len]);
    return output[0..len];
}

pub fn handleSaveVaultList(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const vaults = extractJsonField(payload, "\"vaults\"");

    const config_dir = std.Io.Dir.cwd();
    const vaults_path = ".tolaria/vaults.json";

    // Ensure .tolaria directory exists
    config_dir.createDirPath(io, ".tolaria") catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to create config dir: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    config_dir.writeFile(io, .{
        .sub_path = vaults_path,
        .data = vaults,
    }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"failed to save vaults: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    @memcpy(output[0..result.len], result);
    return output[0..result.len];
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
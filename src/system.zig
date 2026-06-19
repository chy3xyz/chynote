const std = @import("std");
const zero_native = @import("zero-native");
const globals = @import("globals");

const BridgeContext = struct {
    io: *const std.Io,
    env_map: *const std.process.Environ.Map,
    config_path: [512]u8,
    config_path_len: usize,
};

fn configDir(ctx: *BridgeContext) []const u8 {
    return ctx.config_path[0..ctx.config_path_len];
}

fn configSubPath(allocator: std.mem.Allocator, ctx: *BridgeContext, sub: []const u8) ![]const u8 {
    const dir = configDir(ctx);
    if (dir.len == 0) return allocator.dupe(u8, sub);
    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, sub });
}

fn isExecutablePath(io: std.Io, path: []const u8) bool {
    if (!std.fs.path.isAbsolute(path)) return false;
    std.Io.Dir.accessAbsolute(io, path, .{ .execute = true }) catch return false;
    return true;
}

/// Locate an executable named `name` by searching the PATH from `env_map`, plus
/// common fallback directories. Caller owns the returned path (allocated with
/// `allocator`).
fn resolveExecutablePath(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    name: []const u8,
) ?[]const u8 {
    const path_env = env_map.get("PATH") orelse "";

    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const full_path = std.fs.path.join(allocator, &.{ dir, name }) catch continue;
        if (isExecutablePath(io, full_path)) return full_path;
        allocator.free(full_path);
    }

    const fallback_dirs = [_][]const u8{
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/opt/local/bin",
        "/usr/bin",
        "/bin",
    };
    for (fallback_dirs) |dir| {
        const full_path = std.fs.path.join(allocator, &.{ dir, name }) catch continue;
        if (isExecutablePath(io, full_path)) return full_path;
        allocator.free(full_path);
    }

    if (env_map.get("HOME")) |home| {
        if (home.len > 0) {
            const full_path = std.fs.path.join(allocator, &.{ home, ".local/bin", name }) catch return null;
            if (isExecutablePath(io, full_path)) return full_path;
            allocator.free(full_path);
        }
    }

    return null;
}

fn extractJsonField(payload: []const u8, field: []const u8) []const u8 {
    if (std.mem.indexOf(u8, payload, field)) |idx| {
        var start = idx + field.len;
        while (start < payload.len and (payload[start] == ':' or payload[start] == ' ')) : (start += 1) {}
        if (start < payload.len and payload[start] == '"') {
            start += 1;
            var end = start;
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
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
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
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
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
        .argv = &.{"pbpaste"},
        .stdout_limit = std.Io.Limit.limited(65536),
        .stderr_limit = std.Io.Limit.limited(1024),
    }) catch |err| {
        const err_result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"pbpaste failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(err_result);
        const len = @min(err_result.len, output.len);
        @memcpy(output[0..len], err_result[0..len]);
        return output[0..len];
    };

    const exited: u8 = switch (result.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    if (exited != 0) {
        const err_msg = if (result.stderr.len > 0) result.stderr else "clipboard empty or unavailable";
        const err_result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"{s}\"}}", .{err_msg});
        defer std.heap.page_allocator.free(err_result);
        const len = @min(err_result.len, output.len);
        @memcpy(output[0..len], err_result[0..len]);
        return output[0..len];
    }

    const text = std.mem.trim(u8, result.stdout, " \r\n");
    const json_str = try jsonString(std.heap.page_allocator, text);
    defer std.heap.page_allocator.free(json_str);

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    try json_buf.appendSlice(std.heap.page_allocator, "{\"text\":");
    try json_buf.appendSlice(std.heap.page_allocator, json_str);
    try json_buf.appendSlice(std.heap.page_allocator, "}");

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
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
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
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
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleUpdateMenuState(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true}";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleUpdateCurrentWindowMinSize(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true}";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleSyncVaultAssetScopeForWindow(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    const result = "{\"success\":true}";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

const WatcherState = struct {
    running: std.atomic.Value(bool) = .{ .raw = false },
    vault_path: [512]u8 = undefined,
    vault_path_len: usize = 0,
    thread: ?std.Thread = null,
};

var g_watcher: WatcherState = .{};
var g_watcher_prev_hash: u64 = 0;

fn isMarkdownFile(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".md") or std.mem.endsWith(u8, name, ".markdown");
}

fn shouldSkipFile(name: []const u8) bool {
    if (name.len == 0) return true;
    if (name[0] == '.') return true;
    if (std.mem.eql(u8, name, "node_modules")) return true;
    return false;
}

fn scanForHash(allocator: std.mem.Allocator, io: std.Io, dir_path: []const u8, hash: *u64) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var iter = dir.iterate();
    while (true) {
        const entry_opt = try iter.next(io);
        if (entry_opt) |entry| {
            if (shouldSkipFile(entry.name)) continue;
            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer allocator.free(full_path);

            if (entry.kind == .directory) {
                try scanForHash(allocator, io, full_path, hash);
            } else {
                hash.* = hash.* ^ @as(u64, @intCast(full_path.len));
                hash.* = hash.* *% 0x100000001b3;
                for (full_path) |ch| {
                    hash.* = hash.* ^ ch;
                    hash.* = hash.* *% 0x100000001b3;
                }
                const stat = std.Io.Dir.cwd().statFile(io, full_path, .{}) catch continue;
                const mtime: u64 = @intCast(stat.mtime.toSeconds());
                hash.* = hash.* ^ mtime;
                hash.* = hash.* *% 0x100000001b3;
            }
        } else break;
    }
}

fn computeVaultHash(allocator: std.mem.Allocator, io: std.Io, vault_path: []const u8) !u64 {
    var hash: u64 = 0xcbf29ce484222325;
    try scanForHash(allocator, io, vault_path, &hash);
    return hash;
}

fn watcherThreadFn() void {
    const allocator = std.heap.page_allocator;
    const io = globals.g_io orelse return;
    const vault_path = g_watcher.vault_path[0..g_watcher.vault_path_len];

    g_watcher_prev_hash = 0;

    while (g_watcher.running.load(.monotonic)) {
        var req: std.c.timespec = .{ .sec = 3, .nsec = 0 };
        _ = std.c.nanosleep(&req, null);

        const curr_hash = computeVaultHash(allocator, io.*, vault_path) catch continue;
        if (g_watcher_prev_hash != 0 and g_watcher_prev_hash != curr_hash) {
            globals.emitVaultChanged(vault_path, &[_][]const u8{});
        }
        g_watcher_prev_hash = curr_hash;
    }
}

pub fn handleStartVaultWatcher(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;

    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"path\"");

    if (vault_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    }

    // Stop existing watcher if running
    if (g_watcher.running.load(.monotonic)) {
        g_watcher.running.store(false, .monotonic);
        if (g_watcher.thread) |t| {
            t.join();
            g_watcher.thread = null;
        }
    }

    @memcpy(g_watcher.vault_path[0..vault_path.len], vault_path);
    g_watcher.vault_path_len = vault_path.len;
    g_watcher_prev_hash = 0;
    g_watcher.running.store(true, .monotonic);
    g_watcher.thread = std.Thread.spawn(.{}, watcherThreadFn, .{}) catch {
        g_watcher.running.store(false, .monotonic);
        const result = "{\"success\":false,\"error\":\"failed to spawn watcher thread\"}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true,\"watching\":true}";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleStopVaultWatcher(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;

    if (g_watcher.running.load(.monotonic)) {
        g_watcher.running.store(false, .monotonic);
        if (g_watcher.thread) |t| {
            t.join();
            g_watcher.thread = null;
        }
    }

    const result = "{\"success\":true,\"watching\":false}";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGetSettings(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = invocation;
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    const allocator = std.heap.page_allocator;

    const settings_path = configSubPath(allocator, ctx, "settings.json") catch {
        const result = "{\"auto_pull_interval_minutes\":5,\"autogit_enabled\":false,\"autogit_idle_threshold_seconds\":90,\"autogit_inactive_threshold_seconds\":30,\"auto_advance_inbox_after_organize\":false,\"telemetry_consent\":null,\"crash_reporting_enabled\":null,\"analytics_enabled\":null,\"anonymous_id\":null,\"release_channel\":null,\"theme_mode\":null,\"ui_language\":null,\"date_display_format\":null,\"note_width_mode\":null,\"sidebar_type_pluralization_enabled\":null,\"initial_h1_auto_rename_enabled\":null,\"ai_features_enabled\":null,\"default_ai_agent\":null,\"default_ai_target\":null,\"ai_model_providers\":null,\"hide_gitignored_files\":true,\"all_notes_show_pdfs\":null,\"all_notes_show_images\":null,\"all_notes_show_unsupported\":null,\"multi_workspace_enabled\":null}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer allocator.free(settings_path);

    var file = std.Io.Dir.openFileAbsolute(io, settings_path, .{}) catch {
        // Return defaults if file doesn't exist
        const result = "{\"auto_pull_interval_minutes\":5,\"autogit_enabled\":false,\"autogit_idle_threshold_seconds\":90,\"autogit_inactive_threshold_seconds\":30,\"auto_advance_inbox_after_organize\":false,\"telemetry_consent\":null,\"crash_reporting_enabled\":null,\"analytics_enabled\":null,\"anonymous_id\":null,\"release_channel\":null,\"theme_mode\":null,\"ui_language\":null,\"date_display_format\":null,\"note_width_mode\":null,\"sidebar_type_pluralization_enabled\":null,\"initial_h1_auto_rename_enabled\":null,\"ai_features_enabled\":null,\"default_ai_agent\":null,\"default_ai_target\":null,\"ai_model_providers\":null,\"hide_gitignored_files\":true,\"all_notes_show_pdfs\":null,\"all_notes_show_images\":null,\"all_notes_show_unsupported\":null,\"multi_workspace_enabled\":null}";
        const out_len = @min(result.len, output.len);
        @memcpy(output[0..out_len], result[0..out_len]);
        return output[0..out_len];
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
    const allocator = std.heap.page_allocator;

    const payload = invocation.request.payload;
    const settings = extractJsonField(payload, "\"settings\"");

    const settings_path = configSubPath(allocator, ctx, "settings.json") catch {
        const result = try std.fmt.allocPrint(allocator, "{{\"error\":\"failed to resolve config path\"}}", .{});
        defer allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer allocator.free(settings_path);

    // Ensure config directory exists
    const dir_slash = std.mem.lastIndexOfScalar(u8, settings_path, '/');
    if (dir_slash) |slash| {
        const dir_path = settings_path[0..slash];
        std.Io.Dir.cwd().createDirPath(io, dir_path) catch {};
    }

    std.Io.Dir.cwd().writeFile(io, .{
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
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleLoadVaultList(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = invocation;
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    const allocator = std.heap.page_allocator;

    const vaults_path = configSubPath(allocator, ctx, "vaults.json") catch {
        const result = "{\"vaults\":[]}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer allocator.free(vaults_path);

    var file = std.Io.Dir.openFileAbsolute(io, vaults_path, .{}) catch {
        // Return empty list if file doesn't exist
        const result = "{\"vaults\":[]}";
        const out_len = @min(result.len, output.len);
        @memcpy(output[0..out_len], result[0..out_len]);
        return output[0..out_len];
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
    const allocator = std.heap.page_allocator;

    const payload = invocation.request.payload;
    const vaults = extractJsonField(payload, "\"vaults\"");

    const vaults_path = configSubPath(allocator, ctx, "vaults.json") catch {
        const result = try std.fmt.allocPrint(allocator, "{{\"error\":\"failed to resolve config path\"}}", .{});
        defer allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer allocator.free(vaults_path);

    // Ensure config directory exists
    const dir_slash = std.mem.lastIndexOfScalar(u8, vaults_path, '/');
    if (dir_slash) |slash| {
        const dir_path = vaults_path[0..slash];
        std.Io.Dir.cwd().createDirPath(io, dir_path) catch {};
    }

    std.Io.Dir.cwd().writeFile(io, .{
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
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
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
            0x08 => { try result.append(allocator, '\\'); try result.append(allocator, 'b'); },
            0x0c => { try result.append(allocator, '\\'); try result.append(allocator, 'f'); },
            else => if (ch < 0x20) {
                const hex = try std.fmt.allocPrint(allocator, "\\u{X:0>4}", .{ch});
                defer allocator.free(hex);
                try result.appendSlice(allocator, hex);
            } else {
                try result.append(allocator, ch);
            },
        }
    }
    try result.append(allocator, '"');
    return result.toOwnedSlice(allocator);
}

// ── AI / MCP stub handlers ──

pub fn handleCheckClaudeCli(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    const allocator = std.heap.page_allocator;

    _ = invocation;

    const claude_path = resolveExecutablePath(allocator, io, ctx.env_map, "claude") orelse {
        const result = "{\"installed\":false,\"version\":null}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer allocator.free(claude_path);

    // The executable exists and is executable. We treat it as installed; do not
    // run `claude --version` here because the app process may have a stripped
    // PATH that prevents the Node shebang from resolving and can crash.
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\"installed\":true,\"version\":null}");

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleGetAiAgentsStatus(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    const allocator = std.heap.page_allocator;

    _ = invocation;

    const agents = [_]struct { id: []const u8, argv0: []const u8 }{
        .{ .id = "claude_code", .argv0 = "claude" },
        .{ .id = "codex", .argv0 = "codex" },
        .{ .id = "opencode", .argv0 = "opencode" },
        .{ .id = "pi", .argv0 = "pi" },
        .{ .id = "gemini", .argv0 = "gemini" },
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);
    try json_buf.append(allocator, '{');

    var first = true;
    for (agents) |agent| {
        if (!first) try json_buf.appendSlice(allocator, ",");
        first = false;

        try json_buf.appendSlice(allocator, "\"");
        try json_buf.appendSlice(allocator, agent.id);
        try json_buf.appendSlice(allocator, "\":{\"installed\":");

        const agent_path = resolveExecutablePath(allocator, io, ctx.env_map, agent.argv0);
        if (agent_path == null) {
            try json_buf.appendSlice(allocator, "false,\"version\":null}");
            continue;
        }
        defer allocator.free(agent_path.?);

        // The executable exists and is executable. We treat it as installed; do
        // not run `--version` here because the app process may have a stripped
        // PATH that prevents the executable's runtime from resolving.
        try json_buf.appendSlice(allocator, "true,\"version\":null}");
    }

    try json_buf.append(allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

// TODO(refactor): these are currently stub mocks. Real streaming requires
// moving to AsyncHandler with AsyncResponder, which would let the renderer
// receive token-by-token chunks via responder.respond(). See
// zero-native/src/bridge/root.zig:117 (AsyncHandlerFn) and lines 222–228
// (dispatcher routing). Deferred from A4 in docs/PACKAGING.md.
//
// To convert: change the signature to `fn (*anyopaque, Invocation, AsyncResponder) anyerror!void`,
// move the entries from system_handlers to a new async_system_handlers array,
// and pass it as `dispatcher.async_registry.handlers`.

pub fn handleStreamClaudeChat(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "\"mock-session\"";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleStreamAiAgent(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "null";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleRegisterMcpTools(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "\"registered\"";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleCheckMcpStatus(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "\"installed\"";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleGetMcpConfigSnippet(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "{\"mcpServers\":{\"chynote\":{\"type\":\"stdio\",\"command\":\"node\",\"args\":[\"/usr/local/lib/node_modules/chynote/mcp-server/index.js\"],\"env\":{\"WS_UI_PORT\":\"9711\"}}}}";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleSyncMcpBridgeVault(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    const payload = invocation.request.payload;
    const vault_path = extractJsonField(payload, "\"vaultPath\"");
    const result = if (vault_path.len > 0) "\"started\"" else "\"stopped\"";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleGetAgentDocsPath(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "\"/usr/local/share/chynote/agent-docs\"";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGetVaultAiGuidanceStatus(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "{\"agents_state\":\"managed\",\"claude_state\":\"managed\",\"gemini_state\":\"managed\",\"can_restore\":false}";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleRestoreVaultAiGuidance(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "{\"agents_state\":\"managed\",\"claude_state\":\"managed\",\"gemini_state\":\"managed\",\"can_restore\":false}";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleReinitTelemetry(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "null";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handlePerformCurrentWindowTitlebarDoubleClick(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "null";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

fn extractJsonStringValue(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ?[]const u8 {
    const key_quoted = std.fmt.allocPrint(allocator, "\"{s}\"", .{key}) catch return null;
    defer allocator.free(key_quoted);
    const idx = std.mem.indexOf(u8, json, key_quoted) orelse return null;
    const start = idx + key_quoted.len;
    var i = start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t' or json[i] == '\n' or json[i] == '\r' or json[i] == ':')) : (i += 1) {}
    if (i >= json.len or json[i] != '"') return null;
    i += 1;
    var end = i;
    while (end < json.len and json[end] != '"') : (end += 1) {
        if (json[end] == '\\' and end + 1 < json.len) {
            end += 1;
        }
    }
    if (end > i) {
        return allocator.dupe(u8, json[i..end]) catch null;
    }
    return null;
}

pub fn handleDownloadAndInstallAppUpdate(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    const allocator = std.heap.page_allocator;

    const payload = invocation.request.payload;
    const release_channel = extractJsonField(payload, "\"releaseChannel\"");
    const expected_version = extractJsonField(payload, "\"expectedVersion\"");
    _ = release_channel;
    _ = expected_version;

    // Fetch latest release to get download URL
    const result_r = std.process.run(allocator, io, .{
        .argv = &.{ "curl", "-s", "-L", "https://api.github.com/repos/chynote/tolaria/releases/latest" },
        .stdout_limit = std.Io.Limit.limited(32768),
        .stderr_limit = std.Io.Limit.limited(1024),
    }) catch |err| {
        const result = try std.fmt.allocPrint(allocator, "{{\"error\":\"failed to fetch release info: {}\"}}", .{err});
        defer allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        allocator.free(result_r.stdout);
        allocator.free(result_r.stderr);
    }

    if (result_r.term != .exited or result_r.term.exited != 0) {
        const result = "{\"error\":\"failed to fetch release info\"}";
        const out_len = @min(result.len, output.len);
        @memcpy(output[0..out_len], result[0..out_len]);
        return output[0..out_len];
    }

    // Find macOS asset download URL in assets array
    var download_url: ?[]const u8 = null;
    defer if (download_url) |u| allocator.free(u);

    const assets_idx = std.mem.indexOf(u8, result_r.stdout, "\"assets\"") orelse null;
    if (assets_idx) |idx| {
        const assets_section = result_r.stdout[idx..];
        // Find first browser_download_url that looks like macOS
        var search_start: usize = 0;
        while (search_start < assets_section.len) {
            const url_key = std.mem.indexOfPos(u8, assets_section, search_start, "\"browser_download_url\"") orelse break;
            const url_val = extractJsonStringValue(allocator, assets_section[url_key..], "browser_download_url") orelse break;
            if (std.mem.endsWith(u8, url_val, ".dmg") or std.mem.endsWith(u8, url_val, ".zip")) {
                download_url = url_val;
                break;
            }
            allocator.free(url_val);
            search_start = url_key + 1;
        }
    }

    // If no direct asset found, open the release page
    const tag_name = extractJsonStringValue(allocator, result_r.stdout, "tag_name");
    defer if (tag_name) |t| allocator.free(t);

    const open_url = if (download_url) |u|
        try allocator.dupe(u8, u)
    else if (tag_name) |t|
        try std.fmt.allocPrint(allocator, "https://github.com/chynote/tolaria/releases/tag/{s}", .{t})
    else
        try allocator.dupe(u8, "https://github.com/chynote/tolaria/releases/latest");
    defer allocator.free(open_url);

    // Open download URL in browser (non-blocking)
    const open_r = std.process.run(allocator, io, .{
        .argv = &.{ "open", open_url },
        .stdout_limit = std.Io.Limit.limited(1024),
        .stderr_limit = std.Io.Limit.limited(1024),
    }) catch null;
    if (open_r) |r| {
        allocator.free(r.stdout);
        allocator.free(r.stderr);
    }

    const result = "{\"success\":true,\"message\":\"Download started in browser\"}";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result);
    return output[0..len];
}

fn getAiKeysPath(allocator: std.mem.Allocator, ctx: *BridgeContext) ![]const u8 {
    return configSubPath(allocator, ctx, "ai-keys.json");
}

fn readAiKeysJson(allocator: std.mem.Allocator, io: std.Io, ctx: *BridgeContext) ![]u8 {
    const path = getAiKeysPath(allocator, ctx) catch return "";
    defer allocator.free(path);
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch return "";
    return data;
}

pub fn handleSaveAiModelProviderApiKey(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    const allocator = std.heap.page_allocator;

    const payload = invocation.request.payload;
    const provider_id = extractJsonField(payload, "\"providerId\"");
    const api_key = extractJsonField(payload, "\"apiKey\"");

    if (provider_id.len == 0) {
        const result = "{\"error\":\"missing providerId\"}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    }

    const keys_path = getAiKeysPath(allocator, ctx) catch {
        const result = "{\"error\":\"failed to resolve keys path\"}";
        const out_len = @min(result.len, output.len);
        @memcpy(output[0..out_len], result[0..out_len]);
        return output[0..out_len];
    };
    defer allocator.free(keys_path);

    const keys_json = readAiKeysJson(allocator, io, ctx) catch "";
    defer allocator.free(keys_json);

    var new_json: std.ArrayList(u8) = .empty;
    defer new_json.deinit(allocator);

    if (keys_json.len > 0) {
        try new_json.appendSlice(allocator, keys_json);
    } else {
        try new_json.appendSlice(allocator, "{}");
    }

    const provider_key = try std.fmt.allocPrint(allocator, "\"{s}\"", .{provider_id});
    defer allocator.free(provider_key);

    const has_provider = std.mem.indexOf(u8, new_json.items, provider_key);
    const api_key_str = try jsonString(allocator, api_key);
    defer allocator.free(api_key_str);

    if (has_provider) |idx| {
        // Replace existing key value
        const colon_idx = std.mem.indexOfPos(u8, new_json.items, idx + provider_key.len, ":") orelse new_json.items.len;
        var value_start = colon_idx + 1;
        while (value_start < new_json.items.len and (new_json.items[value_start] == ' ' or new_json.items[value_start] == '\n' or new_json.items[value_start] == '\t' or new_json.items[value_start] == '\r')) : (value_start += 1) {}
        const quote_start = value_start;
        var value_end = quote_start + 1;
        while (value_end < new_json.items.len and new_json.items[value_end] != '"') : (value_end += 1) {}
        // Actually find the closing quote, accounting for escapes
        var j: usize = quote_start + 1;
        while (j < new_json.items.len) : (j += 1) {
            if (new_json.items[j] == '\\') {
                j += 1;
                continue;
            }
            if (new_json.items[j] == '"') {
                value_end = j + 1;
                break;
            }
        }
        const before = new_json.items[0..value_start];
        const after = if (value_end < new_json.items.len) new_json.items[value_end..] else "";
        var replacement: std.ArrayList(u8) = .empty;
        defer replacement.deinit(allocator);
        try replacement.appendSlice(allocator, before);
        try replacement.appendSlice(allocator, api_key_str);
        try replacement.appendSlice(allocator, after);
        new_json.deinit(allocator);
        new_json = replacement;
    } else {
        // Append new key
        const insert_pos = if (new_json.items.len > 1) new_json.items.len - 1 else 1;
        var replacement: std.ArrayList(u8) = .empty;
        defer replacement.deinit(allocator);
        try replacement.appendSlice(allocator, new_json.items[0..insert_pos]);
        if (new_json.items.len > 2) try replacement.appendSlice(allocator, ",");
        try replacement.appendSlice(allocator, provider_key);
        try replacement.appendSlice(allocator, ":");
        try replacement.appendSlice(allocator, api_key_str);
        try replacement.appendSlice(allocator, "}");
        new_json.deinit(allocator);
        new_json = replacement;
    }

    const dir_slash = std.mem.lastIndexOfScalar(u8, keys_path, '/');
    if (dir_slash) |slash| {
        const dir_path = keys_path[0..slash];
        std.Io.Dir.cwd().createDirPath(io, dir_path) catch {};
    }

    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = keys_path,
        .data = new_json.items,
    }) catch |err| {
        const result = try std.fmt.allocPrint(allocator, "{{\"error\":\"failed to save key: {}\"}}", .{err});
        defer allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleDeleteAiModelProviderApiKey(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    const allocator = std.heap.page_allocator;

    const payload = invocation.request.payload;
    const provider_id = extractJsonField(payload, "\"providerId\"");

    if (provider_id.len == 0) {
        const result = "{\"error\":\"missing providerId\"}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    }

    const keys_path = getAiKeysPath(allocator, ctx) catch {
        const result = "{\"error\":\"failed to resolve keys path\"}";
        const out_len = @min(result.len, output.len);
        @memcpy(output[0..out_len], result[0..out_len]);
        return output[0..out_len];
    };
    defer allocator.free(keys_path);

    const keys_json = readAiKeysJson(allocator, io, ctx) catch "";
    defer allocator.free(keys_json);

    if (keys_json.len == 0) {
        const result = "{\"success\":true}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    }

    const provider_key = try std.fmt.allocPrint(allocator, "\"{s}\"", .{provider_id});
    defer allocator.free(provider_key);

    const idx = std.mem.indexOf(u8, keys_json, provider_key) orelse {
        const result = "{\"success\":true}";
        const out_len = @min(result.len, output.len);
        @memcpy(output[0..out_len], result[0..out_len]);
        return output[0..out_len];
    };

    const colon_idx = std.mem.indexOfPos(u8, keys_json, idx + provider_key.len, ":") orelse keys_json.len;
    var value_start = colon_idx + 1;
    while (value_start < keys_json.len and (keys_json[value_start] == ' ' or keys_json[value_start] == '\n' or keys_json[value_start] == '\t' or keys_json[value_start] == '\r')) : (value_start += 1) {}
    var value_end = value_start + 1;
    while (value_end < keys_json.len and keys_json[value_end] != '"') : (value_end += 1) {}
    var j: usize = value_start + 1;
    while (j < keys_json.len) : (j += 1) {
        if (keys_json[j] == '\\') {
            j += 1;
            continue;
        }
        if (keys_json[j] == '"') {
            value_end = j + 1;
            break;
        }
    }

    var before_end = idx;
    while (before_end > 0 and (keys_json[before_end - 1] == ' ' or keys_json[before_end - 1] == '\n' or keys_json[before_end - 1] == '\t' or keys_json[before_end - 1] == '\r')) : (before_end -= 1) {}
    var after_start = value_end;
    while (after_start < keys_json.len and (keys_json[after_start] == ' ' or keys_json[after_start] == '\n' or keys_json[after_start] == '\t' or keys_json[after_start] == '\r')) : (after_start += 1) {}
    if (after_start < keys_json.len and keys_json[after_start] == ',') {
        after_start += 1;
    } else if (before_end > 0 and keys_json[before_end - 1] == ',') {
        before_end -= 1;
    }

    var new_json: std.ArrayList(u8) = .empty;
    defer new_json.deinit(allocator);
    try new_json.appendSlice(allocator, keys_json[0..before_end]);
    try new_json.appendSlice(allocator, keys_json[after_start..]);

    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = keys_path,
        .data = new_json.items,
    }) catch |err| {
        const result = try std.fmt.allocPrint(allocator, "{{\"error\":\"failed to delete key: {}\"}}", .{err});
        defer allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    const result = "{\"success\":true}";
    const out_len = @min(result.len, output.len);
    @memcpy(output[0..out_len], result[0..out_len]);
    return output[0..out_len];
}

pub fn handleRemoveMcpTools(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    _ = invocation;
    const result = "{\"success\":true}";
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handlePickFolder(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    _ = context;
    const payload = invocation.request.payload;
    const title = extractJsonField(payload, "\"title\"");
    const services = globals.g_platform_services orelse {
        const result = "{\"error\":\"platform services unavailable\"}";
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var dialog_buffer: [zero_native.platform.max_dialog_paths_bytes]u8 = undefined;
    const dialog_result = services.showOpenDialog(.{
        .title = if (title.len > 0) title else "Select folder",
        .allow_directories = true,
        .allow_multiple = false,
    }, &dialog_buffer) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };

    var writer = std.Io.Writer.fixed(output);
    if (dialog_result.count == 0) {
        try writer.writeAll("null");
        return writer.buffered();
    }

    try writer.writeByte('[');
    var start: usize = 0;
    var i: usize = 0;
    for (dialog_result.paths, 0..) |ch, pos| {
        if (ch == '\n') {
            if (i > 0) try writer.writeByte(',');
            try writeJsonString(&writer, dialog_result.paths[start..pos]);
            start = pos + 1;
            i += 1;
        }
    }
    if (start < dialog_result.paths.len) {
        if (i > 0) try writer.writeByte(',');
        try writeJsonString(&writer, dialog_result.paths[start..]);
    }
    try writer.writeByte(']');
    return writer.buffered();
}

fn writeJsonString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"', '\\' => {
                try writer.writeByte('\\');
                try writer.writeByte(ch);
            },
            '\n' => {
                try writer.writeByte('\\');
                try writer.writeByte('n');
            },
            '\r' => {
                try writer.writeByte('\\');
                try writer.writeByte('r');
            },
            '\t' => {
                try writer.writeByte('\\');
                try writer.writeByte('t');
            },
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
}

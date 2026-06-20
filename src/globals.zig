const std = @import("std");
const zero_native = @import("zero-native");

/// Global platform services reference — set by runner after platform init.
/// Valid for the lifetime of the application.
pub var g_platform_services: ?zero_native.platform.PlatformServices = null;
pub var g_io: ?*const std.Io = null;
pub var g_main_window_id: u64 = 1;
pub var g_vault_cache_invalid: std.atomic.Value(bool) = .{ .raw = false };

/// Emit a vault-changed event to the frontend.
pub fn emitVaultChanged(vault_path: []const u8, paths: []const []const u8) void {
    g_vault_cache_invalid.store(true, .monotonic);
    const services = g_platform_services orelse return;
    const allocator = std.heap.page_allocator;

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    json_buf.appendSlice(allocator, "{\"vaultPath\":") catch return;
    const vp_str = jsonString(allocator, vault_path) catch return;
    defer allocator.free(vp_str);
    json_buf.appendSlice(allocator, vp_str) catch return;

    json_buf.appendSlice(allocator, ",\"paths\":[") catch return;
    for (paths, 0..) |path, i| {
        if (i > 0) json_buf.append(allocator, ',') catch return;
        const p_str = jsonString(allocator, path) catch return;
        defer allocator.free(p_str);
        json_buf.appendSlice(allocator, p_str) catch return;
    }
    json_buf.appendSlice(allocator, "]}") catch return;

    services.emitWindowEvent(g_main_window_id, "vault-changed", json_buf.items) catch {};
}

/// Emit a stub `claude-stream` event sequence. The streaming handlers
/// (handleStreamClaudeChat, handleStreamAiAgent) are still sync stubs
/// that return a session ID; this emits a single Done event so the
/// frontend's `listen('claude-stream', ...)` callback fires and the
/// chat panel doesn't hang. The actual CLI streaming is the deferred
/// A4 work — converting these to AsyncHandler with a real process
/// reader. Until then, the chat panel receives a Done event and the
/// renderer's onDone callback runs.
pub fn emitClaudeStreamDoneFromStub(source: zero_native.bridge.Source) void {
    const services = g_platform_services orelse return;
    services.emitWindowEvent(source.window_id, "claude-stream", "{\"kind\":\"Done\"}") catch {};
}

pub fn emitAiAgentStreamDoneFromStub(source: zero_native.bridge.Source) void {
    const services = g_platform_services orelse return;
    services.emitWindowEvent(source.window_id, "ai-agent-stream", "{\"kind\":\"Done\"}") catch {};
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

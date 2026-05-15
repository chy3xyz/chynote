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

fn runGitCommand(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !struct { exited: u8, stdout: []u8, stderr: []u8 } {
    const result = try std.process.run(allocator, io, .{
        .argv = args,
        .stdout_limit = std.Io.Limit.limited(1024 * 1024),
        .stderr_limit = std.Io.Limit.limited(1024 * 1024),
    });
    
    const exited: u8 = switch (result.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };
    
    return .{ .exited = exited, .stdout = result.stdout, .stderr = result.stderr };
}

pub fn handleGitStatus(
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

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "-C", repo_path, "status", "--porcelain=v1" }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git status failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    const clean = result_r.stdout.len == 0;
    const file_count: u32 = if (clean) 0 else @as(u32, @truncate(std.mem.count(u8, result_r.stdout, &.{'\n'})));

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"clean\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (clean) "true" else "false");
    try json_buf.appendSlice(std.heap.page_allocator, ",\"files\":");
    if (!clean) {
        const count_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{file_count});
        defer std.heap.page_allocator.free(count_str);
        try json_buf.appendSlice(std.heap.page_allocator, count_str);
    } else {
        try json_buf.appendSlice(std.heap.page_allocator, "0");
    }
    try json_buf.appendSlice(std.heap.page_allocator, ",\"repo\":");
    const repo_str = try jsonString(std.heap.page_allocator, repo_path);
    defer std.heap.page_allocator.free(repo_str);
    try json_buf.appendSlice(std.heap.page_allocator, repo_str);
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitCommit(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const message = extractJsonField(payload, "\"message\"");

    if (repo_path.len == 0 or message.len == 0) {
        const result = "{\"error\":\"missing repo_path or message\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "-C", repo_path, "commit", "-m", message }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git commit failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    const success = result_r.exited == 0;
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (success) "true" else "false");
    if (!success) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitPush(
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

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "-C", repo_path, "push" }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git push failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    const success = result_r.exited == 0;
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (success) "true" else "false");
    if (!success) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitPull(
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

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "-C", repo_path, "pull" }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git pull failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    const success = result_r.exited == 0;
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (success) "true" else "false");
    if (!success) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitClone(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const url = extractJsonField(payload, "\"url\"");
    const dest_path = extractJsonField(payload, "\"dest_path\"");

    if (url.len == 0 or dest_path.len == 0) {
        const result = "{\"error\":\"missing url or dest_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "clone", url, dest_path }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git clone failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    const success = result_r.exited == 0;
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (success) "true" else "false");
    if (success) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"path\":");
        const path_str = try jsonString(std.heap.page_allocator, dest_path);
        defer std.heap.page_allocator.free(path_str);
        try json_buf.appendSlice(std.heap.page_allocator, path_str);
    } else {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitInit(
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

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "init", repo_path }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git init failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    const success = result_r.exited == 0;
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (success) "true" else "false");
    if (success) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"path\":");
        const path_str = try jsonString(std.heap.page_allocator, repo_path);
        defer std.heap.page_allocator.free(path_str);
        try json_buf.appendSlice(std.heap.page_allocator, path_str);
    } else {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitAdd(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const files = extractJsonField(payload, "\"files\"");

    if (repo_path.len == 0) {
        const result = "{\"error\":\"missing repo_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    // If files is empty or "*", add all
    const add_arg = if (files.len == 0) "." else files;
    
    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "-C", repo_path, "add", add_arg }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git add failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    const success = result_r.exited == 0;
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (success) "true" else "false");
    if (!success) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitLog(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const limit_str = extractJsonField(payload, "\"limit\"");
    const limit: u32 = if (limit_str.len > 0) std.fmt.parseInt(u32, limit_str, 10) catch 50 else 50;

    if (repo_path.len == 0) {
        const result = "{\"error\":\"missing repo_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const limit_arg = try std.fmt.allocPrint(std.heap.page_allocator, "-{d}", .{limit});
    defer std.heap.page_allocator.free(limit_arg);

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "-C", repo_path, "log", "--oneline", limit_arg }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git log failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"commits\":[");
    
    if (result_r.exited == 0) {
        // Parse each line manually
        var start: usize = 0;
        var first = true;
        while (start < result_r.stdout.len) {
            var end = start;
            while (end < result_r.stdout.len and result_r.stdout[end] != '\n') : (end += 1) {}
            var line_end = end;
            if (line_end > start and result_r.stdout[line_end - 1] == '\r') {
                line_end -= 1;
            }
            const line = result_r.stdout[start..line_end];
            if (line.len > 0) {
                if (!first) try json_buf.append(std.heap.page_allocator, ',');
                first = false;
                try json_buf.appendSlice(std.heap.page_allocator, "{\"message\":");
                const msg_str = try jsonString(std.heap.page_allocator, line);
                defer std.heap.page_allocator.free(msg_str);
                try json_buf.appendSlice(std.heap.page_allocator, msg_str);
                try json_buf.append(std.heap.page_allocator, '}');
            }
            start = end + 1;
        }
    }
    
    try json_buf.appendSlice(std.heap.page_allocator, "]}");

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitDiff(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const file = extractJsonField(payload, "\"file\"");

    if (repo_path.len == 0) {
        const result = "{\"error\":\"missing repo_path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    var git_args: [5][]const u8 = undefined;
    git_args[0] = "git";
    git_args[1] = "-C";
    git_args[2] = repo_path;
    git_args[3] = "diff";
    git_args[4] = file;
    
    const args = if (file.len > 0) git_args[0..5] else git_args[0..4];
    
    const result_r = runGitCommand(std.heap.page_allocator, io, args) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git diff failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (result_r.exited == 0) "true" else "false");
    try json_buf.appendSlice(std.heap.page_allocator, ",\"diff\":");
    const diff_str = try jsonString(std.heap.page_allocator, result_r.stdout);
    defer std.heap.page_allocator.free(diff_str);
    try json_buf.appendSlice(std.heap.page_allocator, diff_str);
    if (result_r.stderr.len > 0) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"stderr\":");
        const err_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(err_str);
        try json_buf.appendSlice(std.heap.page_allocator, err_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitBranch(
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

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "-C", repo_path, "branch", "-a" }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git branch failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"branches\":[");
    
    if (result_r.exited == 0) {
        // Parse each line manually
        var start: usize = 0;
        var first = true;
        while (start < result_r.stdout.len) {
            var end = start;
            while (end < result_r.stdout.len and result_r.stdout[end] != '\n') : (end += 1) {}
            const line = std.mem.trim(u8, result_r.stdout[start..end], " \r");
            if (line.len > 0) {
                // Remove leading * for current branch
                const branch_name = std.mem.trim(u8, line, " *");
                if (!first) try json_buf.append(std.heap.page_allocator, ',');
                first = false;
                const branch_str = try jsonString(std.heap.page_allocator, branch_name);
                defer std.heap.page_allocator.free(branch_str);
                try json_buf.appendSlice(std.heap.page_allocator, branch_str);
            }
            start = end + 1;
        }
    }
    
    try json_buf.appendSlice(std.heap.page_allocator, "]}");

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitCheckout(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    
    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const branch = extractJsonField(payload, "\"branch\"");

    if (repo_path.len == 0 or branch.len == 0) {
        const result = "{\"error\":\"missing repo_path or branch\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = runGitCommand(std.heap.page_allocator, io, &.{ "git", "-C", repo_path, "checkout", branch }) catch |err| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git checkout failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(result);
        const len = @min(result.len, output.len);
        @memcpy(output[0..len], result[0..len]);
        return output[0..len];
    };
    defer {
        std.heap.page_allocator.free(result_r.stdout);
        std.heap.page_allocator.free(result_r.stderr);
    }

    const success = result_r.exited == 0;
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);
    
    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (success) "true" else "false");
    if (!success) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    } else {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"branch\":");
        const branch_str = try jsonString(std.heap.page_allocator, branch);
        defer std.heap.page_allocator.free(branch_str);
        try json_buf.appendSlice(std.heap.page_allocator, branch_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const result = json_buf.items;
    const len = @min(result.len, output.len);
    @memcpy(output[0..len], result[0..len]);
    return output[0..len];
}

pub fn handleGitBlame(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const file_path = extractJsonField(payload, "\"path\"");

    if (file_path.len == 0) {
        const result = "{\"error\":\"missing path\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "git", "-C", repo_path, "blame", file_path },
        .stdout_limit = std.Io.Limit.limited(65536),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const err_result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git blame failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(err_result);
        const len = @min(err_result.len, output.len);
        @memcpy(output[0..len], err_result[0..len]);
        return output[0..len];
    };

    const exited: u8 = switch (result_r.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (exited == 0) "true" else "false");
    if (exited == 0) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"blame\":");
        const blame_str = try jsonString(std.heap.page_allocator, result_r.stdout);
        defer std.heap.page_allocator.free(blame_str);
        try json_buf.appendSlice(std.heap.page_allocator, blame_str);
    } else {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleGitStash(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");

    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "git", "-C", repo_path, "stash" },
        .stdout_limit = std.Io.Limit.limited(4096),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const err_result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git stash failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(err_result);
        const len = @min(err_result.len, output.len);
        @memcpy(output[0..len], err_result[0..len]);
        return output[0..len];
    };

    const exited: u8 = switch (result_r.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (exited == 0) "true" else "false");
    if (exited != 0) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleGitTag(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const tag_name = extractJsonField(payload, "\"tag\"");
    const message = extractJsonField(payload, "\"message\"");

    if (tag_name.len == 0) {
        const result = "{\"error\":\"missing tag name\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = if (message.len > 0)
            &.{ "git", "-C", repo_path, "tag", "-a", tag_name, "-m", message }
        else
            &.{ "git", "-C", repo_path, "tag", tag_name },
        .stdout_limit = std.Io.Limit.limited(1024),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const err_result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git tag failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(err_result);
        const len = @min(err_result.len, output.len);
        @memcpy(output[0..len], err_result[0..len]);
        return output[0..len];
    };

    const exited: u8 = switch (result_r.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (exited == 0) "true" else "false");
    if (exited != 0) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleGitFetch(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");

    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "git", "-C", repo_path, "fetch", "--all" },
        .stdout_limit = std.Io.Limit.limited(4096),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const err_result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git fetch failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(err_result);
        const len = @min(err_result.len, output.len);
        @memcpy(output[0..len], err_result[0..len]);
        return output[0..len];
    };

    const exited: u8 = switch (result_r.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (exited == 0) "true" else "false");
    if (exited != 0) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

pub fn handleGitMerge(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;

    const payload = invocation.request.payload;
    const repo_path = extractJsonField(payload, "\"repo_path\"");
    const branch = extractJsonField(payload, "\"branch\"");

    if (branch.len == 0) {
        const result = "{\"error\":\"missing branch\"}";
        @memcpy(output[0..result.len], result);
        return output[0..result.len];
    }

    const result_r = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "git", "-C", repo_path, "merge", branch },
        .stdout_limit = std.Io.Limit.limited(4096),
        .stderr_limit = std.Io.Limit.limited(4096),
    }) catch |err| {
        const err_result = try std.fmt.allocPrint(std.heap.page_allocator, "{{\"error\":\"git merge failed: {}\"}}", .{err});
        defer std.heap.page_allocator.free(err_result);
        const len = @min(err_result.len, output.len);
        @memcpy(output[0..len], err_result[0..len]);
        return output[0..len];
    };

    const exited: u8 = switch (result_r.term) {
        .exited => |code| @intCast(code),
        else => 1,
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(std.heap.page_allocator);

    try json_buf.appendSlice(std.heap.page_allocator, "{\"success\":");
    try json_buf.appendSlice(std.heap.page_allocator, if (exited == 0) "true" else "false");
    if (exited != 0) {
        try json_buf.appendSlice(std.heap.page_allocator, ",\"message\":");
        const msg_str = try jsonString(std.heap.page_allocator, result_r.stderr);
        defer std.heap.page_allocator.free(msg_str);
        try json_buf.appendSlice(std.heap.page_allocator, msg_str);
    }
    try json_buf.append(std.heap.page_allocator, '}');

    const final_result = json_buf.items;
    const len = @min(final_result.len, output.len);
    @memcpy(output[0..len], final_result[0..len]);
    return output[0..len];
}

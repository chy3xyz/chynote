const std = @import("std");

const PlatformOption = enum {
    auto,
    null,
    macos,
    linux,
    windows,
};

const TraceOption = enum {
    off,
    events,
    runtime,
    all,
};

const WebEngineOption = enum {
    system,
    chromium,
};

const PackageTarget = enum {
    macos,
    windows,
    linux,
};

const default_zero_native_path = "zero-native";
const app_exe_name = "chynote-zn";

const generated_manifest_bridge_path = "src/generated/app_manifest_bridge.zig";

pub fn build(b: *std.Build) void {
    // Generate src/generated/app_manifest_bridge.zig from app.zon so that the
    // bridge command policies in src/main.zig are derived from the manifest.
    // This file is regenerated on every build and is gitignored.
    generateAppManifestBridge(b);

    const target = zeroNativeTarget(b);
    const optimize = b.standardOptimizeOption(.{});
    const platform_option = b.option(PlatformOption, "platform", "Desktop backend: auto, null, macos, linux, windows") orelse .auto;
    const trace_option = b.option(TraceOption, "trace", "Trace output: off, events, runtime, all") orelse .events;
    const debug_overlay = b.option(bool, "debug-overlay", "Enable debug overlay output") orelse false;
    const automation_enabled = b.option(bool, "automation", "Enable zero-native automation artifacts") orelse false;
    const js_bridge_enabled = b.option(bool, "js-bridge", "Enable optional JavaScript bridge stubs") orelse false;
    const web_engine_override = b.option(WebEngineOption, "web-engine", "Override app.zon web engine: system, chromium");
    const cef_dir_override = b.option([]const u8, "cef-dir", "Override CEF root directory for Chromium builds");
    const cef_auto_install_override = b.option(bool, "cef-auto-install", "Override app.zon CEF auto-install setting");
    const package_target = b.option(PackageTarget, "package-target", "Package target: macos, windows, linux") orelse .macos;
    const zero_native_path = b.option([]const u8, "zero-native-path", "Path to the zero-native framework checkout") orelse default_zero_native_path;
    const optimize_name = @tagName(optimize);
    const selected_platform: PlatformOption = switch (platform_option) {
        .auto => if (target.result.os.tag == .macos) .macos else if (target.result.os.tag == .linux) .linux else if (target.result.os.tag == .windows) .windows else .null,
        else => platform_option,
    };
    if (selected_platform == .macos and target.result.os.tag != .macos) {
        @panic("-Dplatform=macos requires a macOS target");
    }
    if (selected_platform == .linux and target.result.os.tag != .linux) {
        @panic("-Dplatform=linux requires a Linux target");
    }
    if (selected_platform == .windows and target.result.os.tag != .windows) {
        @panic("-Dplatform=windows requires a Windows target");
    }
    const app_web_engine = appWebEngineConfig();
    const web_engine = web_engine_override orelse app_web_engine.web_engine;
    const cef_dir = cef_dir_override orelse defaultCefDir(selected_platform, app_web_engine.cef_dir);
    const cef_auto_install = cef_auto_install_override orelse app_web_engine.cef_auto_install;
    if (web_engine == .chromium and selected_platform == .null) {
        @panic("-Dweb-engine=chromium requires -Dplatform=macos, linux, or windows");
    }

    const sdk_path: ?[]const u8 = if (target.result.os.tag == .macos) macosSdkPath(b, &target.result) else null;
    defer if (sdk_path) |path| b.allocator.free(path);

    const zero_native_mod = zeroNativeModule(b, target, optimize, zero_native_path);
    const options = b.addOptions();
    options.addOption([]const u8, "platform", switch (selected_platform) {
        .auto => unreachable,
        .null => "null",
        .macos => "macos",
        .linux => "linux",
        .windows => "windows",
    });
    options.addOption([]const u8, "trace", @tagName(trace_option));
    options.addOption([]const u8, "web_engine", @tagName(web_engine));
    options.addOption(bool, "debug_overlay", debug_overlay);
    options.addOption(bool, "automation", automation_enabled);
    options.addOption(bool, "js_bridge", js_bridge_enabled);
    const options_mod = options.createModule();

    const globals_mod = localModule(b, target, optimize, "src/globals.zig");
    globals_mod.addImport("zero-native", zero_native_mod);

    const runner_mod = localModule(b, target, optimize, "src/runner.zig");
    runner_mod.addImport("zero-native", zero_native_mod);
    runner_mod.addImport("build_options", options_mod);
    runner_mod.addImport("globals", globals_mod);

    const parsing_mod = localModule(b, target, optimize, "src/parsing.zig");
    parsing_mod.addImport("zero-native", zero_native_mod);

    const vault_mod = localModule(b, target, optimize, "src/vault.zig");
    vault_mod.addImport("zero-native", zero_native_mod);
    vault_mod.addImport("parsing", parsing_mod);
    vault_mod.addImport("globals", globals_mod);

    const git_mod = localModule(b, target, optimize, "src/git.zig");
    git_mod.addImport("zero-native", zero_native_mod);

    const system_mod = localModule(b, target, optimize, "src/system.zig");
    system_mod.addImport("zero-native", zero_native_mod);
    system_mod.addImport("globals", globals_mod);

    const app_mod = localModule(b, target, optimize, "src/main.zig");
    const app_manifest_bridge_mod = localModule(b, target, optimize, generated_manifest_bridge_path);
    app_manifest_bridge_mod.addImport("zero-native", zero_native_mod);
    app_mod.addImport("zero-native", zero_native_mod);
    app_mod.addImport("runner", runner_mod);
    app_mod.addImport("app_manifest_bridge", app_manifest_bridge_mod);
    app_mod.addImport("vault", vault_mod);
    app_mod.addImport("git", git_mod);
    app_mod.addImport("system", system_mod);
    const exe = b.addExecutable(.{
        .name = app_exe_name,
        .root_module = app_mod,
    });
    linkPlatform(b, target, app_mod, exe, selected_platform, web_engine, zero_native_path, cef_dir, cef_auto_install, sdk_path);
    b.installArtifact(exe);

    const frontend_install = b.addSystemCommand(&.{ "pnpm", "--dir", "frontend", "install" });
    const frontend_install_step = b.step("frontend-install", "Install frontend dependencies");
    frontend_install_step.dependOn(&frontend_install.step);

    const frontend_build = b.addSystemCommand(&.{ "pnpm", "--dir", "frontend", "run", "build" });
    frontend_build.step.dependOn(&frontend_install.step);
    const frontend_step = b.step("frontend-build", "Build the frontend");
    frontend_step.dependOn(&frontend_build.step);

    exe.step.dependOn(&frontend_build.step);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(&frontend_build.step);
    addCefRuntimeRunFiles(b, target, run, exe, web_engine, cef_dir);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.step);

    const dev = b.addSystemCommand(&.{ "pnpm", "--dir", "frontend", "exec", "zero-native", "dev" });
    dev.addArgs(&.{ "--manifest", "app.zon", "--binary" });
    dev.addFileArg(exe.getEmittedBin());
    dev.step.dependOn(&exe.step);
    dev.step.dependOn(&frontend_install.step);
    const dev_step = b.step("dev", "Run the frontend dev server and native shell");
    dev_step.dependOn(&dev.step);

    const package = b.addSystemCommand(&.{
        "zero-native",
        "package",
        "--target",
        @tagName(package_target),
        "--manifest",
        "app.zon",
        "--assets",
        "frontend/dist",
        "--optimize",
        optimize_name,
        "--output",
        b.fmt("zig-out/package/{s}-0.1.0-{s}-{s}{s}", .{ app_exe_name, @tagName(package_target), optimize_name, packageSuffix(package_target) }),
        "--binary",
    });
    package.addFileArg(exe.getEmittedBin());
    package.addArgs(&.{ "--web-engine", @tagName(web_engine), "--cef-dir", cef_dir });
    if (cef_auto_install) package.addArg("--cef-auto-install");
    package.step.dependOn(&exe.step);
    package.step.dependOn(&frontend_build.step);
    const package_step = b.step("package", "Create a local package artifact");
    package_step.dependOn(&package.step);

    const tests = b.addTest(.{ .root_module = app_mod });
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const check_bridge = b.addExecutable(.{
        .name = "check-bridge",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check-bridge.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const check_bridge_step = b.step("check-bridge", "Verify src/main.zig bridge handlers match app.zon");
    check_bridge_step.dependOn(&b.addRunArtifact(check_bridge).step);
}

fn zeroNativeTarget(b: *std.Build) std.Build.ResolvedTarget {
    const target = b.standardTargetOptions(.{});
    if (target.result.os.tag != .macos) return target;

    var query = target.query;
    query.os_tag = .macos;
    query.os_version_min = .{ .semver = .{ .major = 11, .minor = 0, .patch = 0 } };
    return b.resolveTargetQuery(query);
}

fn macosSdkPath(b: *std.Build, target: *const std.Target) ?[]const u8 {
    if (b.graph.environ_map.get("SDKROOT")) |sdkroot| {
        if (sdkroot.len > 0) return sdkroot;
    }
    return std.zig.system.darwin.getSdk(b.allocator, b.graph.io, target);
}

fn localModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, path: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
}

fn zeroNativePath(b: *std.Build, zero_native_path: []const u8, sub_path: []const u8) std.Build.LazyPath {
    return .{ .cwd_relative = b.pathJoin(&.{ zero_native_path, sub_path }) };
}

fn zeroNativeModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, zero_native_path: []const u8) *std.Build.Module {
    const geometry_mod = externalModule(b, target, optimize, zero_native_path, "src/primitives/geometry/root.zig");
    const assets_mod = externalModule(b, target, optimize, zero_native_path, "src/primitives/assets/root.zig");
    const app_dirs_mod = externalModule(b, target, optimize, zero_native_path, "src/primitives/app_dirs/root.zig");
    const trace_mod = externalModule(b, target, optimize, zero_native_path, "src/primitives/trace/root.zig");
    const app_manifest_mod = externalModule(b, target, optimize, zero_native_path, "src/primitives/app_manifest/root.zig");
    const diagnostics_mod = externalModule(b, target, optimize, zero_native_path, "src/primitives/diagnostics/root.zig");
    const platform_info_mod = externalModule(b, target, optimize, zero_native_path, "src/primitives/platform_info/root.zig");
    const json_mod = externalModule(b, target, optimize, zero_native_path, "src/primitives/json/root.zig");
    const debug_mod = externalModule(b, target, optimize, zero_native_path, "src/debug/root.zig");
    debug_mod.addImport("app_dirs", app_dirs_mod);
    debug_mod.addImport("trace", trace_mod);

    const zero_native_mod = externalModule(b, target, optimize, zero_native_path, "src/root.zig");
    zero_native_mod.addImport("geometry", geometry_mod);
    zero_native_mod.addImport("assets", assets_mod);
    zero_native_mod.addImport("app_dirs", app_dirs_mod);
    zero_native_mod.addImport("trace", trace_mod);
    zero_native_mod.addImport("app_manifest", app_manifest_mod);
    zero_native_mod.addImport("diagnostics", diagnostics_mod);
    zero_native_mod.addImport("platform_info", platform_info_mod);
    zero_native_mod.addImport("json", json_mod);
    return zero_native_mod;
}

fn externalModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, zero_native_path: []const u8, path: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = zeroNativePath(b, zero_native_path, path),
        .target = target,
        .optimize = optimize,
    });
}

fn linkPlatform(b: *std.Build, target: std.Build.ResolvedTarget, app_mod: *std.Build.Module, exe: *std.Build.Step.Compile, platform: PlatformOption, web_engine: WebEngineOption, zero_native_path: []const u8, cef_dir: []const u8, cef_auto_install: bool, sdk_path: ?[]const u8) void {
    if (platform == .macos) {
        switch (web_engine) {
            .system => {
                const sdk_include = if (sdk_path) |sdk| b.fmt("-I{s}/usr/include", .{sdk}) else "";
                const flags: []const []const u8 = if (sdk_path) |sdk| &.{ "-fobjc-arc", "-ObjC", "-mmacosx-version-min=11.0", "-isysroot", sdk, sdk_include } else &.{ "-fobjc-arc", "-ObjC", "-mmacosx-version-min=11.0" };
                app_mod.addCSourceFile(.{ .file = zeroNativePath(b, zero_native_path, "src/platform/macos/appkit_host.m"), .flags = flags });
                app_mod.linkFramework("WebKit", .{});
            },
            .chromium => {
                const cef_check = addCefCheck(b, target, cef_dir);
                if (cef_auto_install) {
                    const cef_auto = b.addSystemCommand(&.{ "zero-native", "cef", "install", "--dir", cef_dir });
                    cef_check.step.dependOn(&cef_auto.step);
                }
                exe.step.dependOn(&cef_check.step);
                const include_arg = b.fmt("-I{s}", .{cef_dir});
                const define_arg = b.fmt("-DZERO_NATIVE_CEF_DIR=\"{s}\"", .{cef_dir});
                const sdk_include = if (sdk_path) |sdk| b.fmt("-I{s}/usr/include", .{sdk}) else "";
                const flags: []const []const u8 = if (sdk_path) |sdk| &.{ "-fobjc-arc", "-ObjC++", "-std=c++17", "-stdlib=libc++", "-mmacosx-version-min=11.0", "-isysroot", sdk, sdk_include, include_arg, define_arg } else &.{ "-fobjc-arc", "-ObjC++", "-std=c++17", "-stdlib=libc++", "-mmacosx-version-min=11.0", include_arg, define_arg };
                app_mod.addCSourceFile(.{ .file = zeroNativePath(b, zero_native_path, "src/platform/macos/cef_host.mm"), .flags = flags });
                app_mod.addObjectFile(b.path(b.fmt("{s}/libcef_dll_wrapper/libcef_dll_wrapper.a", .{cef_dir})));
                app_mod.addFrameworkPath(b.path(b.fmt("{s}/Release", .{cef_dir})));
                app_mod.linkFramework("Chromium Embedded Framework", .{});
                app_mod.addRPath(.{ .cwd_relative = "@executable_path/Frameworks" });
            },
        }
        if (sdk_path) |sdk| {
            app_mod.addFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "System/Library/Frameworks" }) });
            app_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "usr/lib" }) });
        }
        app_mod.linkFramework("AppKit", .{});
        app_mod.linkFramework("Foundation", .{});
        app_mod.linkFramework("UniformTypeIdentifiers", .{});
        app_mod.linkSystemLibrary("c", .{});
        if (web_engine == .chromium) app_mod.linkSystemLibrary("c++", .{});
    } else if (platform == .linux) {
        switch (web_engine) {
            .system => {
                app_mod.addCSourceFile(.{ .file = zeroNativePath(b, zero_native_path, "src/platform/linux/gtk_host.c"), .flags = &.{} });
                app_mod.linkSystemLibrary("gtk4", .{});
                app_mod.linkSystemLibrary("webkitgtk-6.0", .{});
            },
            .chromium => {
                const cef_check = addCefCheck(b, target, cef_dir);
                if (cef_auto_install) {
                    const cef_auto = b.addSystemCommand(&.{ "zero-native", "cef", "install", "--dir", cef_dir });
                    cef_check.step.dependOn(&cef_auto.step);
                }
                exe.step.dependOn(&cef_check.step);
                const include_arg = b.fmt("-I{s}", .{cef_dir});
                const define_arg = b.fmt("-DZERO_NATIVE_CEF_DIR=\"{s}\"", .{cef_dir});
                app_mod.addCSourceFile(.{ .file = zeroNativePath(b, zero_native_path, "src/platform/linux/cef_host.cpp"), .flags = &.{ "-std=c++17", include_arg, define_arg } });
                app_mod.addObjectFile(b.path(b.fmt("{s}/libcef_dll_wrapper/libcef_dll_wrapper.a", .{cef_dir})));
                app_mod.addLibraryPath(b.path(b.fmt("{s}/Release", .{cef_dir})));
                app_mod.linkSystemLibrary("cef", .{});
                app_mod.addRPath(.{ .cwd_relative = "$ORIGIN" });
            },
        }
        app_mod.linkSystemLibrary("c", .{});
        if (web_engine == .chromium) app_mod.linkSystemLibrary("stdc++", .{});
    } else if (platform == .windows) {
        switch (web_engine) {
            .system => app_mod.addCSourceFile(.{ .file = zeroNativePath(b, zero_native_path, "src/platform/windows/webview2_host.cpp"), .flags = &.{"-std=c++17"} }),
            .chromium => {
                const cef_check = addCefCheck(b, target, cef_dir);
                if (cef_auto_install) {
                    const cef_auto = b.addSystemCommand(&.{ "zero-native", "cef", "install", "--dir", cef_dir });
                    cef_check.step.dependOn(&cef_auto.step);
                }
                exe.step.dependOn(&cef_check.step);
                const include_arg = b.fmt("-I{s}", .{cef_dir});
                const define_arg = b.fmt("-DZERO_NATIVE_CEF_DIR=\"{s}\"", .{cef_dir});
                app_mod.addCSourceFile(.{ .file = zeroNativePath(b, zero_native_path, "src/platform/windows/cef_host.cpp"), .flags = &.{ "-std=c++17", include_arg, define_arg } });
                app_mod.addObjectFile(b.path(b.fmt("{s}/libcef_dll_wrapper/libcef_dll_wrapper.lib", .{cef_dir})));
                app_mod.addLibraryPath(b.path(b.fmt("{s}/Release", .{cef_dir})));
            },
        }
        app_mod.linkSystemLibrary("c", .{});
        app_mod.linkSystemLibrary("c++", .{});
        app_mod.linkSystemLibrary("user32", .{});
        app_mod.linkSystemLibrary("ole32", .{});
        app_mod.linkSystemLibrary("shell32", .{});
        if (web_engine == .chromium) app_mod.linkSystemLibrary("libcef", .{});
    }
}

fn addCefRuntimeRunFiles(b: *std.Build, target: std.Build.ResolvedTarget, run: *std.Build.Step.Run, exe: *std.Build.Step.Compile, web_engine: WebEngineOption, cef_dir: []const u8) void {
    if (web_engine != .chromium) return;
    if (target.result.os.tag != .macos) return;
    const copy = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt(
            \\set -e
            \\exe="$0"
            \\exe_dir="$(dirname "$exe")"
            \\rm -rf "zig-out/Frameworks/Chromium Embedded Framework.framework" "zig-out/bin/Frameworks/Chromium Embedded Framework.framework" ".zig-cache/o/Frameworks/Chromium Embedded Framework.framework" &&
            \\mkdir -p "zig-out/Frameworks" "zig-out/bin/Frameworks" ".zig-cache/o/Frameworks" "$exe_dir" &&
            \\cp -R "{s}/Release/Chromium Embedded Framework.framework" "zig-out/Frameworks/" &&
            \\cp -R "{s}/Release/Chromium Embedded Framework.framework" "zig-out/bin/Frameworks/" &&
            \\cp -R "{s}/Release/Chromium Embedded Framework.framework" ".zig-cache/o/Frameworks/" &&
            \\cp "{s}/Release/Chromium Embedded Framework.framework/Libraries/libEGL.dylib" "$exe_dir/" &&
            \\cp "{s}/Release/Chromium Embedded Framework.framework/Libraries/libGLESv2.dylib" "$exe_dir/" &&
            \\cp "{s}/Release/Chromium Embedded Framework.framework/Libraries/libvk_swiftshader.dylib" "$exe_dir/" &&
            \\cp "{s}/Release/Chromium Embedded Framework.framework/Libraries/vk_swiftshader_icd.json" "$exe_dir/"
        , .{ cef_dir, cef_dir, cef_dir, cef_dir, cef_dir, cef_dir, cef_dir }),
    });
    copy.addFileArg(exe.getEmittedBin());
    run.step.dependOn(&copy.step);
}

fn addCefCheck(b: *std.Build, target: std.Build.ResolvedTarget, cef_dir: []const u8) *std.Build.Step.Run {
    const script = switch (target.result.os.tag) {
        .macos => b.fmt(
            \\test -f "{s}/include/cef_app.h" &&
            \\test -d "{s}/Release/Chromium Embedded Framework.framework" &&
            \\test -f "{s}/libcef_dll_wrapper/libcef_dll_wrapper.a" || {{
            \\  echo "missing CEF dependency for -Dweb-engine=chromium" >&2
            \\  echo "Expected:" >&2
            \\  echo "  {s}/include/cef_app.h" >&2
            \\  echo "  {s}/Release/Chromium Embedded Framework.framework" >&2
            \\  echo "  {s}/libcef_dll_wrapper/libcef_dll_wrapper.a" >&2
            \\  echo "Fix with: zero-native cef install --dir {s}" >&2
            \\  echo "Or rerun with: -Dcef-auto-install=true" >&2
            \\  echo "Pass -Dcef-dir=/path/to/cef if your bundle lives elsewhere." >&2
            \\  exit 1
            \\}}
        , .{ cef_dir, cef_dir, cef_dir, cef_dir, cef_dir, cef_dir, cef_dir }),
        .linux => b.fmt(
            \\test -f "{s}/include/cef_app.h" &&
            \\test -f "{s}/Release/libcef.so" &&
            \\test -f "{s}/libcef_dll_wrapper/libcef_dll_wrapper.a" || {{
            \\  echo "missing CEF dependency for -Dweb-engine=chromium" >&2
            \\  echo "Fix with: zero-native cef install --dir {s}" >&2
            \\  exit 1
            \\}}
        , .{ cef_dir, cef_dir, cef_dir, cef_dir }),
        .windows => b.fmt(
            \\test -f "{s}/include/cef_app.h" &&
            \\test -f "{s}/Release/libcef.dll" &&
            \\test -f "{s}/libcef_dll_wrapper/libcef_dll_wrapper.lib" || {{
            \\  echo "missing CEF dependency for -Dweb-engine=chromium" >&2
            \\  echo "Fix with: zero-native cef install --dir {s}" >&2
            \\  exit 1
            \\}}
        , .{ cef_dir, cef_dir, cef_dir, cef_dir }),
        else => "echo unsupported CEF target >&2; exit 1",
    };
    return b.addSystemCommand(&.{ "sh", "-c", script });
}

fn packageSuffix(target: PackageTarget) []const u8 {
    return switch (target) {
        .macos => ".app",
        .windows, .linux => "",
    };
}

const AppWebEngineConfig = struct {
    web_engine: WebEngineOption = .system,
    cef_dir: []const u8 = "third_party/cef/macos",
    cef_auto_install: bool = false,
};

fn defaultCefDir(platform: PlatformOption, configured: []const u8) []const u8 {
    if (!std.mem.eql(u8, configured, "third_party/cef/macos")) return configured;
    return switch (platform) {
        .linux => "third_party/cef/linux",
        .windows => "third_party/cef/windows",
        else => configured,
    };
}

fn appWebEngineConfig() AppWebEngineConfig {
    const source = @embedFile("app.zon");
    var config: AppWebEngineConfig = .{};
    if (stringField(source, ".web_engine")) |value| {
        config.web_engine = parseWebEngine(value) orelse .system;
    }
    if (objectSection(source, ".cef")) |cef| {
        if (stringField(cef, ".dir")) |value| config.cef_dir = value;
        if (boolField(cef, ".auto_install")) |value| config.cef_auto_install = value;
    }
    return config;
}

fn parseWebEngine(value: []const u8) ?WebEngineOption {
    if (std.mem.eql(u8, value, "system")) return .system;
    if (std.mem.eql(u8, value, "chromium")) return .chromium;
    return null;
}

fn stringField(source: []const u8, field: []const u8) ?[]const u8 {
    const field_index = std.mem.indexOf(u8, source, field) orelse return null;
    const equals = std.mem.indexOfScalarPos(u8, source, field_index, '=') orelse return null;
    const start_quote = std.mem.indexOfScalarPos(u8, source, equals, '"') orelse return null;
    const end_quote = std.mem.indexOfScalarPos(u8, source, start_quote + 1, '"') orelse return null;
    return source[start_quote + 1 .. end_quote];
}

fn objectSection(source: []const u8, field: []const u8) ?[]const u8 {
    const field_index = std.mem.indexOf(u8, source, field) orelse return null;
    const open = std.mem.indexOfScalarPos(u8, source, field_index, '{') orelse return null;
    var depth: usize = 0;
    var index = open;
    while (index < source.len) : (index += 1) {
        switch (source[index]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return source[open + 1 .. index];
            },
            else => {},
        }
    }
    return null;
}

fn boolField(source: []const u8, field: []const u8) ?bool {
    const field_index = std.mem.indexOf(u8, source, field) orelse return null;
    const equals = std.mem.indexOfScalarPos(u8, source, field_index, '=') orelse return null;
    var index = equals + 1;
    while (index < source.len and std.ascii.isWhitespace(source[index])) : (index += 1) {}
    if (std.mem.startsWith(u8, source[index..], "true")) return true;
    if (std.mem.startsWith(u8, source[index..], "false")) return false;
    return null;
}

const BridgeCommandEntry = struct {
    name: []const u8,
    origins: []const []const u8,
};

/// Read `app.zon`, extract the `bridge.commands` list, and emit
/// `src/generated/app_manifest_bridge.zig` containing a Zig const array
/// that `src/main.zig` imports. The generated file is rewritten on every
/// build, so editing `app.zon` is enough to change the bridge policies.
fn generateAppManifestBridge(b: *std.Build) void {
    const source = @embedFile("app.zon");
    const bridge = objectSection(source, ".bridge") orelse {
        std.debug.panic("app.zon is missing .bridge block; cannot generate app_manifest_bridge.zig", .{});
    };
    const commands_body = arraySection(bridge, ".commands") orelse &.{};

    var entries: std.ArrayList(BridgeCommandEntry) = .empty;
    defer {
        for (entries.items) |e| {
            for (e.origins) |o| b.allocator.free(o);
            b.allocator.free(e.origins);
        }
        entries.deinit(b.allocator);
    }

    // Walk the array body; each entry is `{ .name = "x", .origins = .{ "y" } }` or similar.
    var index: usize = 0;
    while (index < commands_body.len) {
        const open = std.mem.indexOfScalarPos(u8, commands_body, index, '{') orelse break;
        var depth: usize = 1;
        var cursor: usize = open + 1;
        while (cursor < commands_body.len and depth > 0) {
            switch (commands_body[cursor]) {
                '{' => depth += 1,
                '}' => depth -= 1,
                else => {},
            }
            cursor += 1;
        }
        if (depth != 0) break;
        const entry_body = commands_body[open + 1 .. cursor - 1];
        const name = stringField(entry_body, ".name") orelse {
            std.debug.panic("app.zon: bridge command missing .name", .{});
        };
        const origins = parseOriginsList(b.allocator, entry_body) catch @panic("OOM");
        entries.append(b.allocator, .{ .name = name, .origins = origins }) catch @panic("OOM");
        index = cursor;
    }

    // Emit the Zig file.
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(b.allocator);
    out.appendSlice(b.allocator,
        \\// Auto-generated from app.zon. Do not edit by hand.
        \\// Regenerated on every `zig build`.
        \\const std = @import("std");
        \\
        \\pub const dev_origins = [_][]const u8{
        \\    "zero://app",
        \\    "zero://inline",
        \\    "zero://local",
        \\    "http://127.0.0.1:5173",
        \\    "http://localhost:5173",
        \\};
        \\
        \\pub const app_command_policies = [_]@import("zero-native").bridge.CommandPolicy{
        \\
    ) catch @panic("OOM");

    for (entries.items) |entry| {
        if (entry.origins.len == 0) {
            out.print(b.allocator, "    .{{ .name = \"{s}\" }},\n", .{entry.name}) catch @panic("OOM");
        } else {
            out.print(b.allocator, "        .{{ .name = \"{s}\", .origins = &.{{ ", .{entry.name}) catch @panic("OOM");
            for (entry.origins, 0..) |o, i| {
                if (i > 0) out.appendSlice(b.allocator, ", ") catch @panic("OOM");
                out.print(b.allocator, "\"{s}\"", .{o}) catch @panic("OOM");
            }
            out.appendSlice(b.allocator, " } },\n") catch @panic("OOM");
        }
    }
    out.appendSlice(b.allocator, "};\n") catch @panic("OOM");

    // Write atomically: write to a temp file, then rename. Paths are
    // relative to the build root, where `b.pathJoin` resolves.
    const cwd = std.Io.Dir.cwd();
    const rel_path = b.pathJoin(&.{ "src", "generated", "app_manifest_bridge.zig" });
    defer b.allocator.free(rel_path);
    const tmp_path = b.fmt("{s}.tmp", .{rel_path});
    defer b.allocator.free(tmp_path);
    const io = b.graph.io;
    {
        const file = cwd.createFile(io, tmp_path, .{}) catch @panic("createFile failed");
        defer file.close(io);
        file.writeStreamingAll(io, out.items) catch @panic("write failed");
    }
    cwd.rename(tmp_path, cwd, rel_path, io) catch @panic("rename failed");
}

/// Find `.field = .{ "a", "b" }` (an array literal) and return the body.
fn arraySection(source: []const u8, field: []const u8) ?[]const u8 {
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

/// Parse `.origins = .{ "a", "b" }` and return heap-allocated strings.
fn parseOriginsList(allocator: std.mem.Allocator, entry_body: []const u8) ![]const []const u8 {
    const section = arraySection(entry_body, ".origins") orelse return &.{};
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(allocator);
    var i: usize = 0;
    while (i < section.len) {
        const q = std.mem.indexOfScalarPos(u8, section, i, '"') orelse break;
        const end = std.mem.indexOfScalarPos(u8, section, q + 1, '"') orelse break;
        try list.append(allocator, try allocator.dupe(u8, section[q + 1 .. end]));
        i = end + 1;
    }
    return list.toOwnedSlice(allocator);
}

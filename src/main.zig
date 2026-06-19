const std = @import("std");
const runner = @import("runner");
const zero_native = @import("zero-native");
const vault = @import("vault");
const git = @import("git");
const system = @import("system");
const app_manifest_bridge = @import("app_manifest_bridge");

pub const panic = std.debug.FullPanic(zero_native.debug.capturePanic);

// Context passed to all bridge handlers
const BridgeContext = struct {
    io: *const std.Io,
    env_map: *const std.process.Environ.Map,
    config_path: [512]u8,
    config_path_len: usize,
};

var bridge_ctx: BridgeContext = undefined;

fn resolveConfigPath(env_map: *std.process.Environ.Map, buffer: []u8) ![]const u8 {
    const platform = zero_native.app_dirs.currentPlatform();
    const env = zero_native.debug.envFromMap(env_map);
    return zero_native.app_dirs.resolveOne(.{ .name = "Chynote" }, platform, env, .config, buffer);
}

const App = struct {
    env_map: *std.process.Environ.Map,

    fn app(self: *@This()) zero_native.App {
        return .{
            .context = self,
            .name = "chynote",
            .source = zero_native.frontend.productionSource(.{ .dist = "frontend/dist" }),
            .source_fn = frontendSource,
        };
    }
};

fn frontendSource(context: *anyopaque) anyerror!zero_native.WebViewSource {
    const self: *App = @ptrCast(@alignCast(context));
    return zero_native.frontend.sourceFromEnv(self.env_map, .{
        .dist = "frontend/dist",
        .entry = "index.html",
    });
}

// zero-native denies built-in dialog commands unless explicitly allowed.
// Empty origins = allow from any WebView origin once enabled.
const builtin_bridge_policies = [_]zero_native.bridge.CommandPolicy{
    .{ .name = "zero-native.dialog.openFile" },
    .{ .name = "zero-native.dialog.saveFile" },
    .{ .name = "zero-native.dialog.showMessage" },
};

const command_policies = app_manifest_bridge.app_command_policies;
const dev_origins = app_manifest_bridge.dev_origins;

const vault_handlers = [_]zero_native.bridge.Handler{
    .{ .name = "vault.list_vault", .context = &bridge_ctx, .invoke_fn = vault.handleListVault },
    .{ .name = "vault.get_note_content", .context = &bridge_ctx, .invoke_fn = vault.handleGetNoteContent },
    .{ .name = "vault.save_note_content", .context = &bridge_ctx, .invoke_fn = vault.handleSaveNoteContent },
    .{ .name = "vault.create_folder", .context = &bridge_ctx, .invoke_fn = vault.handleCreateFolder },
    .{ .name = "vault.list_folders", .context = &bridge_ctx, .invoke_fn = vault.handleListFolders },
    .{ .name = "vault.reload_vault", .context = &bridge_ctx, .invoke_fn = vault.handleReloadVault },
    .{ .name = "vault.list_vault_folders", .context = &bridge_ctx, .invoke_fn = vault.handleListVaultFolders },
    .{ .name = "vault.check_vault_exists", .context = &bridge_ctx, .invoke_fn = vault.handleCheckVaultExists },
    .{ .name = "vault.list_views", .context = &bridge_ctx, .invoke_fn = vault.handleListViews },
    .{ .name = "vault.save_view", .context = &bridge_ctx, .invoke_fn = vault.handleSaveView },
    .{ .name = "vault.delete_view", .context = &bridge_ctx, .invoke_fn = vault.handleDeleteView },
    .{ .name = "vault.reload_vault_entry", .context = &bridge_ctx, .invoke_fn = vault.handleReloadVaultEntry },
    .{ .name = "vault.sync_note_title", .context = &bridge_ctx, .invoke_fn = vault.handleSyncNoteTitle },
    .{ .name = "vault.validate_note_content", .context = &bridge_ctx, .invoke_fn = vault.handleValidateNoteContent },
    .{ .name = "vault.delete_note", .context = &bridge_ctx, .invoke_fn = vault.handleDeleteNote },
    .{ .name = "vault.batch_delete_notes", .context = &bridge_ctx, .invoke_fn = vault.handleBatchDeleteNotes },
    .{ .name = "vault.create_note_content", .context = &bridge_ctx, .invoke_fn = vault.handleCreateNoteContent },
    .{ .name = "vault.rename_vault_folder", .context = &bridge_ctx, .invoke_fn = vault.handleRenameVaultFolder },
    .{ .name = "vault.delete_vault_folder", .context = &bridge_ctx, .invoke_fn = vault.handleDeleteVaultFolder },
    .{ .name = "vault.update_frontmatter", .context = &bridge_ctx, .invoke_fn = vault.handleUpdateFrontmatter },
    .{ .name = "vault.delete_frontmatter_property", .context = &bridge_ctx, .invoke_fn = vault.handleDeleteFrontmatterProperty },
    .{ .name = "vault.rename_note", .context = &bridge_ctx, .invoke_fn = vault.handleRenameNote },
    .{ .name = "vault.move_note_to_folder", .context = &bridge_ctx, .invoke_fn = vault.handleMoveNoteToFolder },
    .{ .name = "vault.save_image", .context = &bridge_ctx, .invoke_fn = vault.handleSaveImage },
    .{ .name = "vault.copy_image_to_vault", .context = &bridge_ctx, .invoke_fn = vault.handleCopyImageToVault },
    .{ .name = "vault.batch_archive_notes", .context = &bridge_ctx, .invoke_fn = vault.handleBatchArchiveNotes },
    .{ .name = "vault.get_file_history", .context = &bridge_ctx, .invoke_fn = vault.handleGetFileHistory },
    .{ .name = "vault.get_modified_files", .context = &bridge_ctx, .invoke_fn = vault.handleGetModifiedFiles },
    .{ .name = "vault.get_file_diff", .context = &bridge_ctx, .invoke_fn = vault.handleGetFileDiff },
    .{ .name = "vault.get_vault_pulse", .context = &bridge_ctx, .invoke_fn = vault.handleGetVaultPulse },
    .{ .name = "vault.search_vault", .context = &bridge_ctx, .invoke_fn = vault.handleSearchVault },
    .{ .name = "vault.create_empty_vault", .context = &bridge_ctx, .invoke_fn = vault.handleCreateEmptyVault },
    .{ .name = "vault.create_getting_started_vault", .context = &bridge_ctx, .invoke_fn = vault.handleCreateGettingStartedVault },
    .{ .name = "vault.get_default_vault_path", .context = &bridge_ctx, .invoke_fn = vault.handleGetDefaultVaultPath },
    .{ .name = "vault.check_for_app_update", .context = &bridge_ctx, .invoke_fn = vault.handleCheckForAppUpdate },
    .{ .name = "vault.repair_vault", .context = &bridge_ctx, .invoke_fn = vault.handleRepairVault },
    .{ .name = "vault.should_use_external_media_preview", .context = &bridge_ctx, .invoke_fn = vault.handleShouldUseExternalMediaPreview },
    .{ .name = "vault.get_build_number", .context = &bridge_ctx, .invoke_fn = vault.handleGetBuildNumber },
};

const git_handlers = [_]zero_native.bridge.Handler{
    .{ .name = "git.status", .context = &bridge_ctx, .invoke_fn = git.handleGitStatus },
    .{ .name = "git.commit", .context = &bridge_ctx, .invoke_fn = git.handleGitCommit },
    .{ .name = "git.push", .context = &bridge_ctx, .invoke_fn = git.handleGitPush },
    .{ .name = "git.pull", .context = &bridge_ctx, .invoke_fn = git.handleGitPull },
    .{ .name = "git.clone", .context = &bridge_ctx, .invoke_fn = git.handleGitClone },
    .{ .name = "git.init", .context = &bridge_ctx, .invoke_fn = git.handleGitInit },
    .{ .name = "git.add", .context = &bridge_ctx, .invoke_fn = git.handleGitAdd },
    .{ .name = "git.log", .context = &bridge_ctx, .invoke_fn = git.handleGitLog },
    .{ .name = "git.diff", .context = &bridge_ctx, .invoke_fn = git.handleGitDiff },
    .{ .name = "git.branch", .context = &bridge_ctx, .invoke_fn = git.handleGitBranch },
    .{ .name = "git.checkout", .context = &bridge_ctx, .invoke_fn = git.handleGitCheckout },
    .{ .name = "git.blame", .context = &bridge_ctx, .invoke_fn = git.handleGitBlame },
    .{ .name = "git.stash", .context = &bridge_ctx, .invoke_fn = git.handleGitStash },
    .{ .name = "git.tag", .context = &bridge_ctx, .invoke_fn = git.handleGitTag },
    .{ .name = "git.fetch", .context = &bridge_ctx, .invoke_fn = git.handleGitFetch },
    .{ .name = "git.merge", .context = &bridge_ctx, .invoke_fn = git.handleGitMerge },
    .{ .name = "git.remote_status", .context = &bridge_ctx, .invoke_fn = git.handleGitRemoteStatus },
    .{ .name = "git.add_remote", .context = &bridge_ctx, .invoke_fn = git.handleGitAddRemote },
    .{ .name = "git.discard_file", .context = &bridge_ctx, .invoke_fn = git.handleGitCheckout },
    .{ .name = "git.get_conflict_files", .context = &bridge_ctx, .invoke_fn = git.handleGetConflictFiles },
    .{ .name = "git.get_last_commit_info", .context = &bridge_ctx, .invoke_fn = git.handleGetLastCommitInfo },
    .{ .name = "git.resolve_conflict", .context = &bridge_ctx, .invoke_fn = git.handleGitResolveConflict },
    .{ .name = "git.commit_conflict_resolution", .context = &bridge_ctx, .invoke_fn = git.handleGitCommitConflictResolution },
};

const system_handlers = [_]zero_native.bridge.Handler{
    .{ .name = "system.copy_text_to_clipboard", .context = &bridge_ctx, .invoke_fn = system.handleCopyTextToClipboard },
    .{ .name = "system.open_vault_file_external", .context = &bridge_ctx, .invoke_fn = system.handleOpenVaultFileExternal },
    .{ .name = "system.trigger_menu_command", .context = &bridge_ctx, .invoke_fn = system.handleTriggerMenuCommand },
    .{ .name = "system.update_menu_state", .context = &bridge_ctx, .invoke_fn = system.handleUpdateMenuState },
    .{ .name = "system.update_current_window_min_size", .context = &bridge_ctx, .invoke_fn = system.handleUpdateCurrentWindowMinSize },
    .{ .name = "system.sync_vault_asset_scope_for_window", .context = &bridge_ctx, .invoke_fn = system.handleSyncVaultAssetScopeForWindow },
    .{ .name = "system.start_vault_watcher", .context = &bridge_ctx, .invoke_fn = system.handleStartVaultWatcher },
    .{ .name = "system.stop_vault_watcher", .context = &bridge_ctx, .invoke_fn = system.handleStopVaultWatcher },
    .{ .name = "system.get_settings", .context = &bridge_ctx, .invoke_fn = system.handleGetSettings },
    .{ .name = "system.save_settings", .context = &bridge_ctx, .invoke_fn = system.handleSaveSettings },
    .{ .name = "system.load_vault_list", .context = &bridge_ctx, .invoke_fn = system.handleLoadVaultList },
    .{ .name = "system.save_vault_list", .context = &bridge_ctx, .invoke_fn = system.handleSaveVaultList },
    .{ .name = "system.search_vault", .context = &bridge_ctx, .invoke_fn = vault.handleSearchVault },
    .{ .name = "system.read_text_from_clipboard", .context = &bridge_ctx, .invoke_fn = system.handleReadTextFromClipboard },
    .{ .name = "system.check_claude_cli", .context = &bridge_ctx, .invoke_fn = system.handleCheckClaudeCli },
    .{ .name = "system.get_ai_agents_status", .context = &bridge_ctx, .invoke_fn = system.handleGetAiAgentsStatus },
    .{ .name = "system.stream_claude_chat", .context = &bridge_ctx, .invoke_fn = system.handleStreamClaudeChat },
    .{ .name = "system.stream_ai_agent", .context = &bridge_ctx, .invoke_fn = system.handleStreamAiAgent },
    .{ .name = "system.register_mcp_tools", .context = &bridge_ctx, .invoke_fn = system.handleRegisterMcpTools },
    .{ .name = "system.check_mcp_status", .context = &bridge_ctx, .invoke_fn = system.handleCheckMcpStatus },
    .{ .name = "system.get_mcp_config_snippet", .context = &bridge_ctx, .invoke_fn = system.handleGetMcpConfigSnippet },
    .{ .name = "system.sync_mcp_bridge_vault", .context = &bridge_ctx, .invoke_fn = system.handleSyncMcpBridgeVault },
    .{ .name = "system.get_agent_docs_path", .context = &bridge_ctx, .invoke_fn = system.handleGetAgentDocsPath },
    .{ .name = "system.get_vault_ai_guidance_status", .context = &bridge_ctx, .invoke_fn = system.handleGetVaultAiGuidanceStatus },
    .{ .name = "system.restore_vault_ai_guidance", .context = &bridge_ctx, .invoke_fn = system.handleRestoreVaultAiGuidance },
    .{ .name = "system.reinit_telemetry", .context = &bridge_ctx, .invoke_fn = system.handleReinitTelemetry },
    .{ .name = "system.perform_current_window_titlebar_double_click", .context = &bridge_ctx, .invoke_fn = system.handlePerformCurrentWindowTitlebarDoubleClick },
    .{ .name = "system.download_and_install_app_update", .context = &bridge_ctx, .invoke_fn = system.handleDownloadAndInstallAppUpdate },
    .{ .name = "system.save_ai_model_provider_api_key", .context = &bridge_ctx, .invoke_fn = system.handleSaveAiModelProviderApiKey },
    .{ .name = "system.delete_ai_model_provider_api_key", .context = &bridge_ctx, .invoke_fn = system.handleDeleteAiModelProviderApiKey },
    .{ .name = "system.remove_mcp_tools", .context = &bridge_ctx, .invoke_fn = system.handleRemoveMcpTools },
    .{ .name = "system.pick_folder", .context = &bridge_ctx, .invoke_fn = system.handlePickFolder },
};

pub fn main(init: std.process.Init) !void {
    var app = App{ .env_map = init.environ_map };

    // Resolve platform config directory
    var config_buffer: [512]u8 = undefined;
    const config_path = resolveConfigPath(init.environ_map, &config_buffer) catch "";

    // Store io in bridge context for handlers to use
    bridge_ctx = .{
        .io = &init.io,
        .env_map = init.environ_map,
        .config_path = config_buffer,
        .config_path_len = config_path.len,
    };

    const bridge_dispatcher = zero_native.BridgeDispatcher{
        .policy = .{
            .enabled = true,
            .commands = &command_policies,
        },
        .registry = .{
            .handlers = &vault_handlers ++ &git_handlers ++ &system_handlers,
        },
    };

    try runner.runWithOptions(app.app(), .{
        .app_name = "Chynote",
        .window_title = "Chynote",
        .bundle_id = "com.chynote.app",
        .icon_path = "assets/icon.icns",
        .bridge = bridge_dispatcher,
        .builtin_bridge = .{
            .enabled = true,
            .commands = &builtin_bridge_policies,
        },
        .security = .{
            .navigation = .{ .allowed_origins = &dev_origins },
        },
    }, init);
}

test "app name is configured" {
    try std.testing.expectEqualStrings("chynote", "chynote");
}

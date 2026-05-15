const std = @import("std");
const runner = @import("runner");
const zero_native = @import("zero-native");
const vault = @import("vault");
const git = @import("git");
const system = @import("system");

pub const panic = std.debug.FullPanic(zero_native.debug.capturePanic);

// Context passed to all bridge handlers
const BridgeContext = struct {
    io: *const std.Io,
};

var bridge_ctx: BridgeContext = undefined;

const App = struct {
    env_map: *std.process.Environ.Map,

    fn app(self: *@This()) zero_native.App {
        return .{
            .context = self,
            .name = "tolaria",
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

const dev_origins = [_][]const u8{ "zero://app", "zero://inline", "http://127.0.0.1:5173" };

const command_policies = [_]zero_native.bridge.CommandPolicy{
    .{ .name = "vault.list_vault", .origins = &.{ "zero://app" } },
    .{ .name = "vault.get_note_content", .origins = &.{ "zero://app" } },
    .{ .name = "vault.save_note_content", .origins = &.{ "zero://app" } },
    .{ .name = "vault.create_folder", .origins = &.{ "zero://app" } },
    .{ .name = "vault.list_folders", .origins = &.{ "zero://app" } },
    .{ .name = "vault.reload_vault", .origins = &.{ "zero://app" } },
    .{ .name = "vault.list_vault_folders", .origins = &.{ "zero://app" } },
    .{ .name = "vault.check_vault_exists", .origins = &.{ "zero://app" } },
    .{ .name = "vault.list_views", .origins = &.{ "zero://app" } },
    .{ .name = "vault.save_view", .origins = &.{ "zero://app" } },
    .{ .name = "vault.delete_view", .origins = &.{ "zero://app" } },
    .{ .name = "vault.reload_vault_entry", .origins = &.{ "zero://app" } },
    .{ .name = "vault.sync_note_title", .origins = &.{ "zero://app" } },
    .{ .name = "vault.validate_note_content", .origins = &.{ "zero://app" } },
    .{ .name = "vault.delete_note", .origins = &.{ "zero://app" } },
    .{ .name = "vault.batch_delete_notes", .origins = &.{ "zero://app" } },
    .{ .name = "vault.create_note_content", .origins = &.{ "zero://app" } },
    .{ .name = "vault.rename_vault_folder", .origins = &.{ "zero://app" } },
    .{ .name = "vault.delete_vault_folder", .origins = &.{ "zero://app" } },
    .{ .name = "vault.update_frontmatter", .origins = &.{ "zero://app" } },
    .{ .name = "vault.delete_frontmatter_property", .origins = &.{ "zero://app" } },
    .{ .name = "vault.rename_note", .origins = &.{ "zero://app" } },
    .{ .name = "vault.move_note_to_folder", .origins = &.{ "zero://app" } },
    .{ .name = "vault.save_image", .origins = &.{ "zero://app" } },
    .{ .name = "vault.copy_image_to_vault", .origins = &.{ "zero://app" } },
    .{ .name = "vault.batch_archive_notes", .origins = &.{ "zero://app" } },
    .{ .name = "vault.get_file_history", .origins = &.{ "zero://app" } },
    .{ .name = "vault.get_modified_files", .origins = &.{ "zero://app" } },
    .{ .name = "vault.get_file_diff", .origins = &.{ "zero://app" } },
    .{ .name = "vault.get_vault_pulse", .origins = &.{ "zero://app" } },
    .{ .name = "vault.search_vault", .origins = &.{ "zero://app" } },
    .{ .name = "vault.create_empty_vault", .origins = &.{ "zero://app" } },
    .{ .name = "vault.create_getting_started_vault", .origins = &.{ "zero://app" } },
    .{ .name = "vault.get_default_vault_path", .origins = &.{ "zero://app" } },
    .{ .name = "vault.check_for_app_update", .origins = &.{ "zero://app" } },
    .{ .name = "vault.repair_vault", .origins = &.{ "zero://app" } },
    .{ .name = "vault.should_use_external_media_preview", .origins = &.{ "zero://app" } },
    .{ .name = "vault.get_build_number", .origins = &.{ "zero://app" } },
    .{ .name = "git.status", .origins = &.{ "zero://app" } },
    .{ .name = "git.commit", .origins = &.{ "zero://app" } },
    .{ .name = "git.push", .origins = &.{ "zero://app" } },
    .{ .name = "git.pull", .origins = &.{ "zero://app" } },
    .{ .name = "git.clone", .origins = &.{ "zero://app" } },
    .{ .name = "git.init", .origins = &.{ "zero://app" } },
    .{ .name = "git.add", .origins = &.{ "zero://app" } },
    .{ .name = "git.log", .origins = &.{ "zero://app" } },
    .{ .name = "git.diff", .origins = &.{ "zero://app" } },
    .{ .name = "git.branch", .origins = &.{ "zero://app" } },
    .{ .name = "git.checkout", .origins = &.{ "zero://app" } },
    .{ .name = "git.blame", .origins = &.{ "zero://app" } },
    .{ .name = "git.stash", .origins = &.{ "zero://app" } },
    .{ .name = "git.tag", .origins = &.{ "zero://app" } },
    .{ .name = "git.fetch", .origins = &.{ "zero://app" } },
    .{ .name = "git.merge", .origins = &.{ "zero://app" } },
    .{ .name = "system.copy_text_to_clipboard", .origins = &.{ "zero://app" } },
    .{ .name = "system.open_vault_file_external", .origins = &.{ "zero://app" } },
    .{ .name = "system.trigger_menu_command", .origins = &.{ "zero://app" } },
    .{ .name = "system.update_menu_state", .origins = &.{ "zero://app" } },
    .{ .name = "system.update_current_window_min_size", .origins = &.{ "zero://app" } },
    .{ .name = "system.sync_vault_asset_scope_for_window", .origins = &.{ "zero://app" } },
    .{ .name = "system.start_vault_watcher", .origins = &.{ "zero://app" } },
    .{ .name = "system.stop_vault_watcher", .origins = &.{ "zero://app" } },
    .{ .name = "system.get_settings", .origins = &.{ "zero://app" } },
    .{ .name = "system.save_settings", .origins = &.{ "zero://app" } },
    .{ .name = "system.load_vault_list", .origins = &.{ "zero://app" } },
    .{ .name = "system.save_vault_list", .origins = &.{ "zero://app" } },
    .{ .name = "system.search_vault", .origins = &.{ "zero://app" } },
    .{ .name = "system.read_text_from_clipboard", .origins = &.{ "zero://app" } },
};

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
    .{ .name = "system.read_text_from_clipboard", .context = &bridge_ctx, .invoke_fn = vault.handleReadTextFromClipboard },
};

pub fn main(init: std.process.Init) !void {
    var app = App{ .env_map = init.environ_map };

    // Store io in bridge context for handlers to use
    bridge_ctx = .{ .io = &init.io };

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
        .app_name = "Tolaria",
        .window_title = "Tolaria",
        .bundle_id = "com.tolaria.app",
        .icon_path = "assets/icon.icns",
        .bridge = bridge_dispatcher,
        .security = .{
            .navigation = .{ .allowed_origins = &dev_origins },
        },
    }, init);
}

test "app name is configured" {
    try std.testing.expectEqualStrings("tolaria", "tolaria");
}

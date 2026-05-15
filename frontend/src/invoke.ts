/**
 * Tolaria zero-native bridge wrapper
 * Wraps window.zero.invoke() to match the Tauri invoke API
 */

export interface InvokeOptions {
  timeout?: number;
}

declare global {
  interface Window {
    zero: {
      invoke: <T = unknown>(cmd: string, payload?: Record<string, unknown>) => Promise<T>;
      on: (event: string, handler: (data: unknown) => void) => void;
      off: (event: string, handler: (data: unknown) => void) => void;
    };
  }
}

/**
 * Invoke a bridge command via window.zero.invoke()
 * Matches the Tauri invoke() API signature
 */
export async function invoke<T>(
  cmd: string,
  args?: Record<string, unknown>,
  options?: InvokeOptions
): Promise<T> {
  const { timeout = 30000 } = options ?? {};

  const promise = window.zero.invoke<T>(cmd, args ?? {});

  if (timeout > 0) {
    return Promise.race([
      promise,
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error(`Command ${cmd} timed out after ${timeout}ms`)), timeout)
      ),
    ]);
  }

  return promise;
}

/**
 * Check if running in zero-native environment
 */
export function isZeroNative(): boolean {
  return typeof window !== 'undefined' && typeof window.zero !== 'undefined';
}

/**
 * Check if running in Tauri environment
 */
export function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI__' in window;
}

/**
 * Command aliases - maps frontend command names to backend handler names
 * with param remapping for Tauri → zero-native compatibility
 */
const commandAliases: Record<string, { cmd: string; paramMap?: Record<string, string> }> = {
  // Vault aliases
  'create_vault_folder': { cmd: 'vault.create_folder', paramMap: { vaultPath: 'vault_path', folderName: 'folder_path' } },
  'save_note_content': { cmd: 'vault.save_note_content', paramMap: { path: 'note_path' } },
  'get_note_content': { cmd: 'vault.get_note_content', paramMap: { path: 'note_path' } },
  'list_vault': { cmd: 'vault.list_vault', paramMap: { path: 'vault_path' } },
  'list_folders': { cmd: 'vault.list_folders', paramMap: { path: 'vault_path' } },
  'reload_vault': { cmd: 'vault.reload_vault', paramMap: { path: 'vault_path' } },
  'list_vault_folders': { cmd: 'vault.list_vault_folders', paramMap: { path: 'vault_path' } },
  'check_vault_exists': { cmd: 'vault.check_vault_exists', paramMap: { path: 'vault_path' } },
  'list_views': { cmd: 'vault.list_views' },
  'save_view': { cmd: 'vault.save_view' },
  'delete_view': { cmd: 'vault.delete_view' },
  'reload_vault_entry': { cmd: 'vault.reload_vault_entry', paramMap: { path: 'vault_path' } },
  'sync_note_title': { cmd: 'vault.sync_note_title' },
  'validate_note_content': { cmd: 'vault.validate_note_content' },
  'delete_note': { cmd: 'vault.delete_note', paramMap: { path: 'note_path' } },
  'batch_delete_notes': { cmd: 'vault.batch_delete_notes' },
  'create_note_content': { cmd: 'vault.create_note_content', paramMap: { path: 'note_path' } },
  'rename_vault_folder': { cmd: 'vault.rename_vault_folder' },
  'delete_vault_folder': { cmd: 'vault.delete_vault_folder' },
  'update_frontmatter': { cmd: 'vault.update_frontmatter' },
  'delete_frontmatter_property': { cmd: 'vault.delete_frontmatter_property' },
  'rename_note': { cmd: 'vault.rename_note' },
  'move_note_to_folder': { cmd: 'vault.move_note_to_folder' },
  'save_image': { cmd: 'vault.save_image' },
  'copy_image_to_vault': { cmd: 'vault.copy_image_to_vault' },
  'batch_archive_notes': { cmd: 'vault.batch_archive_notes' },
  'get_file_history': { cmd: 'vault.get_file_history' },
  'get_modified_files': { cmd: 'vault.get_modified_files' },
  'get_file_diff': { cmd: 'vault.get_file_diff' },
  'get_vault_pulse': { cmd: 'vault.get_vault_pulse' },
  'search_vault': { cmd: 'vault.search_vault' },
  'create_empty_vault': { cmd: 'vault.create_empty_vault' },
  'create_getting_started_vault': { cmd: 'vault.create_getting_started_vault' },
  'get_default_vault_path': { cmd: 'vault.get_default_vault_path' },
  'check_for_app_update': { cmd: 'vault.check_for_app_update' },
  'repair_vault': { cmd: 'vault.repair_vault' },
  'should_use_external_media_preview': { cmd: 'vault.should_use_external_media_preview' },
  'get_build_number': { cmd: 'vault.get_build_number' },

  // Git aliases
  'init_git_repo': { cmd: 'git.init', paramMap: { vaultPath: 'repo_path' } },

  // System aliases (no param remapping needed for these)
  'copy_text_to_clipboard': { cmd: 'system.copy_text_to_clipboard' },
  'open_vault_file_external': { cmd: 'system.open_vault_file_external' },
  'trigger_menu_command': { cmd: 'system.trigger_menu_command' },
  'update_menu_state': { cmd: 'system.update_menu_state' },
  'update_current_window_min_size': { cmd: 'system.update_current_window_min_size' },
  'sync_vault_asset_scope_for_window': { cmd: 'system.sync_vault_asset_scope_for_window' },
  'start_vault_watcher': { cmd: 'system.start_vault_watcher' },
  'stop_vault_watcher': { cmd: 'system.stop_vault_watcher' },
  'get_settings': { cmd: 'system.get_settings' },
  'save_settings': { cmd: 'system.save_settings' },
  'load_vault_list': { cmd: 'system.load_vault_list' },
  'save_vault_list': { cmd: 'system.save_vault_list' },
  'system_search_vault': { cmd: 'system.search_vault' },
  'read_text_from_clipboard': { cmd: 'system.read_text_from_clipboard' },
};

/**
 * Remap parameters according to alias map
 */
function remapParams<T extends Record<string, unknown>>(
  params: T,
  paramMap?: Record<string, string>
): Record<string, unknown> {
  if (!paramMap) return params;
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(params)) {
    const newKey = paramMap[key] ?? key;
    result[newKey] = value;
  }
  return result;
}

/**
 * Get the appropriate invoke function for the current environment
 * Prefers Tauri if available, falls back to zero-native
 */
export function getInvoke() {
  if (isTauri()) {
    // Use Tauri - would need to import from @tauri-apps/api/core
    return async <T>(cmd: string, args?: Record<string, unknown>) => {
      const { invoke: tauriInvoke } = await import('@tauri-apps/api/core');
      return tauriInvoke<T>(cmd, args);
    };
  } else if (isZeroNative()) {
    // Return wrapper that handles aliases
    return async <T>(cmd: string, args?: Record<string, unknown>) => {
      const alias = commandAliases[cmd];
      const actualCmd = alias?.cmd ?? cmd;
      const actualArgs = alias?.paramMap ? remapParams(args ?? {}) : args;
      return invoke<T>(actualCmd, actualArgs);
    };
  }
  throw new Error('No native bridge available (neither Tauri nor zero-native)');
}

/**
 * Direct invoke without aliasing - for internal use
 */
export const directInvoke = invoke;

/**
 * Chynote zero-native bridge wrapper
 * Wraps window.zero.invoke() to the same call shape as the Tauri
 * invoke() API so call sites read identically.
 */

export interface InvokeOptions {
  timeout?: number;
}

export interface ZeroNativeOpenFileOptions {
  title?: string;
  defaultPath?: string;
  allowDirectories?: boolean;
  allowMultiple?: boolean;
}

export interface ZeroNativeSaveFileOptions {
  title?: string;
  defaultPath?: string;
  defaultName?: string;
}

declare global {
  interface Window {
    zero: {
      invoke: <T = unknown>(cmd: string, payload?: Record<string, unknown>) => Promise<T>;
      on: (event: string, handler: (data: unknown) => void) => void;
      off: (event: string, handler: (data: unknown) => void) => void;
      dialogs: {
        openFile: (options?: ZeroNativeOpenFileOptions) => Promise<string[] | null>;
        saveFile: (options?: ZeroNativeSaveFileOptions) => Promise<string | null>;
      };
    };
  }
}

/**
 * Invoke a bridge command via window.zero.invoke(). Param remapping for
 * Zig handlers lives in lib/bridgeParams.ts via @zero-apps/api/core.
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
 * Returns true when running inside the zero-native WebView. The legacy
 * `__TAURI__` global is also accepted as a fallback so the same build
 * still works in the (deprecated) Tauri runtime.
 */
export function isZeroNative(): boolean {
  if (typeof window === 'undefined') return false;
  return typeof window.zero !== 'undefined' || '__TAURI__' in window;
}

/**
 * Get the appropriate invoke function for the current environment.
 */
export function getInvoke() {
  if (!isZeroNative()) {
    throw new Error('No native bridge available (not running in zero-native)');
  }
  return async <T>(cmd: string, args?: Record<string, unknown>) => {
    const { invoke: coreInvoke } = await import('@zero-apps/api/core');
    return coreInvoke<T>(cmd, args);
  };
}

/**
 * Direct invoke without aliasing - for internal use
 */
export const directInvoke = invoke;

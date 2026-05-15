export interface Window {
  label: string;
  close: () => Promise<void>;
  minimize: () => Promise<void>;
  maximize: () => Promise<void>;
  unmaximize: () => Promise<void>;
  isMaximized: () => Promise<boolean>;
  setFocus: () => Promise<void>;
  setSize: (size: { width: number; height: number }) => Promise<void>;
  setMinSize: (size: { width: number; height: number }) => Promise<void>;
  setTitle: (title: string) => Promise<void>;
}

export interface WindowOptions {
  label: string;
  url?: string;
  title?: string;
  width?: number;
  height?: number;
  resizable?: boolean;
  fullscreen?: boolean;
}

let currentWindow: Window | null = null;

export function getCurrentWindow(): Window {
  if (!currentWindow) {
    currentWindow = {
      label: 'main',
      close: async () => {},
      minimize: async () => {},
      maximize: async () => {},
      unmaximize: async () => {},
      isMaximized: async () => false,
      setFocus: async () => {},
      setSize: async () => {},
      setMinSize: async () => {},
      setTitle: async () => {},
    };
  }
  return currentWindow;
}

export async function getAllWindows(): Promise<Window[]> {
  return [getCurrentWindow()];
}

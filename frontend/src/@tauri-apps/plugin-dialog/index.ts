export interface DialogFilter {
  name: string;
  extensions: string[];
}

export interface OpenDialogOptions {
  title?: string;
  defaultPath?: string;
  filters?: DialogFilter[];
  multiple?: boolean;
  directory?: boolean;
}

export interface SaveDialogOptions {
  title?: string;
  defaultPath?: string;
  filters?: DialogFilter[];
}

export interface MessageDialogOptions {
  title?: string;
  message: string;
  type?: 'info' | 'warning' | 'error';
}

export async function open(options?: OpenDialogOptions): Promise<string | string[] | null> {
  console.log('open dialog not implemented in zero-native:', options);
  return null;
}

export async function save(options?: SaveDialogOptions): Promise<string | null> {
  console.log('save dialog not implemented in zero-native:', options);
  return null;
}

export async function message(options?: MessageDialogOptions): Promise<void> {
  console.log('message dialog not implemented in zero-native:', options);
}

export async function confirm(message: string, options?: { title?: string; type?: 'warning' | 'error' }): Promise<boolean> {
  console.log('confirm dialog not implemented in zero-native:', message, options);
  return false;
}

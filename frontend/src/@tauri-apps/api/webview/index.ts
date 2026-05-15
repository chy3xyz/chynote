export interface DragDropEvent {
  paths: string[];
  position: { x: number; y: number };
}

export interface Webview {
  label: string;
}

export function getCurrentWebview(): Webview {
  return { label: 'main' };
}

export async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke: zeroInvoke } = window.zero;
  return zeroInvoke<T>(cmd, args ?? {});
}

export class Channel<T> {
  private listeners: ((event: T) => void)[] = [];

  set onmessage(handler: (event: T) => void) {
    this.listeners.push(handler);
  }

  emit(event: T) {
    for (const listener of this.listeners) {
      listener(event);
    }
  }
}

export function createChannel<T>(eventName: string): Channel<T> {
  const channel = new Channel<T>();
  if (window.zero.on) {
    window.zero.on(eventName, (event: T) => channel.emit(event));
  }
  return channel;
}

export function convertFileSrc(filePath: string): string {
  return `asset://localhost/${encodeURIComponent(filePath)}`;
}

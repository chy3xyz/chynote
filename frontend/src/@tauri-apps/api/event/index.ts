export type UnlistenFn = () => void;

export interface Event<T> {
  payload: T;
}

export async function listen<T>(event: string, handler: (event: Event<T>) => void): Promise<UnlistenFn> {
  const wrappedHandler = (payload: T) => handler({ payload });
  if (window.zero.on) {
    window.zero.on(event, wrappedHandler);
  }
  return () => {
    if (window.zero.off) {
      window.zero.off(event, wrappedHandler);
    }
  };
}

export async function once<T>(event: string, handler: (event: Event<T>) => void): Promise<UnlistenFn> {
  let unlisten: UnlistenFn;
  const wrappedHandler = (payload: T) => {
    handler({ payload });
    unlisten();
  };
  if (window.zero.on) {
    window.zero.on(event, wrappedHandler);
  }
  unlisten = () => {
    if (window.zero.off) {
      window.zero.off(event, wrappedHandler);
    }
  };
  return unlisten;
}

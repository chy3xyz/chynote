export class WebviewWindow {
  constructor(label: string, options?: {
    url?: string;
    title?: string;
    width?: number;
    height?: number;
    resizable?: boolean;
    titleBarStyle?: 'regular' | 'overlay';
    trafficLightPosition?: any;
    hiddenTitle?: boolean;
    decorations?: boolean;
  }) {
    console.log('WebviewWindow not fully implemented in zero-native:', label, options);
  }

  close(): Promise<void> {
    console.log('WebviewWindow.close not implemented');
    return Promise.resolve();
  }

  setTitle(title: string): Promise<void> {
    console.log('WebviewWindow.setTitle not implemented:', title);
    return Promise.resolve();
  }

  minimize(): Promise<void> {
    console.log('WebviewWindow.minimize not implemented');
    return Promise.resolve();
  }

  maximize(): Promise<void> {
    console.log('WebviewWindow.maximize not implemented');
    return Promise.resolve();
  }

  unmaximize(): Promise<void> {
    console.log('WebviewWindow.unmaximize not implemented');
    return Promise.resolve();
  }

  show(): Promise<void> {
    console.log('WebviewWindow.show not implemented');
    return Promise.resolve();
  }

  hide(): Promise<void> {
    console.log('WebviewWindow.hide not implemented');
    return Promise.resolve();
  }

  setFocus(): Promise<void> {
    console.log('WebviewWindow.setFocus not implemented');
    return Promise.resolve();
  }
}

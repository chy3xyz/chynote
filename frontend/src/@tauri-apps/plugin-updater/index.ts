export interface Update {
  version: string;
  date?: string;
  body?: string;
}

export interface UpdateCheckResult {
  available: boolean;
  version?: string;
  date?: string;
  body?: string;
}

export interface DownloadProgress {
  chunkLength: number;
  contentLength?: number;
}

export async function checkUpdate(): Promise<UpdateCheckResult> {
  return { available: false };
}

export async function downloadAndInstall(
  onEvent?: (event: DownloadProgress | { event: 'Finished' }) => void
): Promise<void> {
  console.log('downloadAndInstall not implemented in zero-native');
}

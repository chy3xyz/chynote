export async function exit(code: number = 0): Promise<void> {
  console.log('exit not implemented in zero-native, code:', code);
}

export async function restart(): Promise<void> {
  console.log('restart not implemented in zero-native');
}

export interface PhotoLibraryPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}

/// «1.5 МБ», «820 КБ», «0 Б».
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}

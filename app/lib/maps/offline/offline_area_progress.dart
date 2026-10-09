/// Ход сохранения области.
class OfflineAreaProgress {
  const OfflineAreaProgress({required this.downloadedTiles, required this.totalTiles, this.bytesDownloaded = 0});

  final int downloadedTiles;
  final int totalTiles;
  final int bytesDownloaded;

  /// 0..1; без тайлов — 1.
  double get fraction => totalTiles == 0 ? 1 : (downloadedTiles / totalTiles).clamp(0.0, 1.0);

  bool get isComplete => downloadedTiles >= totalTiles;
}

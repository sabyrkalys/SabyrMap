import 'package:app/landmarks/composite/statistics/composite_statistics.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_object.dart';

/// Всё, что нужно экрану детализации: элемент списка, содержимое файла
/// (null — не прочитано), статистика и сведения о файле.
class LandmarkDetailsData {
  const LandmarkDetailsData({
    required this.item,
    required this.folder,
    this.object,
    this.stats,
    this.sizeBytes,
    this.modified,
  });

  final LandmarkItem item;
  final LandmarkObject? object;
  final CompositeStatistics? stats;

  /// Папка файла для показа.
  final String folder;
  final int? sizeBytes;
  final DateTime? modified;
}

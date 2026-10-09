import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:path/path.dart' as p;

/// Путь текущей папки от корня места: «Мои метки / Несортированные метки / 2026».
abstract final class ExplorerBreadcrumbs {
  static String of(PlaceRoot? place, String? folder) {
    if (folder == null) return '';
    if (place == null) return p.basename(folder);
    if (p.equals(place.path, folder)) return place.title;
    if (!p.isWithin(place.path, folder)) return p.basename(folder);
    return [place.title, ...p.split(p.relative(folder, from: place.path))].join(' / ');
  }
}

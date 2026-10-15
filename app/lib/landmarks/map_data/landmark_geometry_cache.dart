import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:path/path.dart' as p;

import 'landmark_features.dart';

/// Полные объекты меток для карты: в индексе только метаданные
/// ([LandmarkItem]), геометрия читается здесь — один раз на версию файла.
///
/// Decision: версия файла — время его изменения ([LandmarkItem.fileModifiedAt]);
/// изменился файл — объект перечитывается. Объекты внутри `.ldk` берутся
/// из одного прочитанного файла меток. Нечитаемый файл на карту не
/// попадает.
class LandmarkGeometryCache {
  LandmarkGeometryCache(this._repository);

  final LandmarkRepository _repository;
  final Map<String, ({DateTime modified, LandmarkObject object})> _files = {};

  /// Объект записи [item] (у вложенного — объект внутри `.ldk`); null —
  /// файл не читается.
  Future<LandmarkObject?> objectFor(LandmarkItem item) async {
    final file = await _file(item.filePath, item.fileModifiedAt);
    if (file == null || !item.isNested) return file;
    final index = item.nestedIndex;
    return file is LdkFileObject && index != null && index >= 0 && index < file.objects.length
        ? file.objects[index]
        : null;
  }

  /// GeoJSON-объекты всех [items]. Записи самих файлов меток пропускаются:
  /// их объекты — отдельные записи индекса ([LandmarkItem.isNested]).
  Future<List<Map<String, dynamic>>> featuresOf(Iterable<LandmarkItem> items) async {
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item.type == LandmarkType.ldkFile) continue;
      final object = await objectFor(item);
      if (object != null) out.addAll(LandmarkFeatures.of(item.path, object));
    }
    return out;
  }

  /// `FeatureCollection` для [items].
  Future<Map<String, dynamic>> collectionOf(Iterable<LandmarkItem> items) async =>
      LandmarkFeatures.collection(await featuresOf(items));

  /// Забывает файлы, которых больше нет среди [alive] (пути файлов).
  void retainOnly(Iterable<String> alive) {
    final keep = {for (final path in alive) p.normalize(path)};
    _files.removeWhere((path, _) => !keep.contains(path));
  }

  Future<LandmarkObject?> _file(String path, DateTime modified) async {
    final key = p.normalize(path);
    final cached = _files[key];
    if (cached != null && cached.modified == modified) return cached.object;
    try {
      final object = (await _repository.load(key)).content;
      _files[key] = (modified: modified, object: object);
      return object;
    } on Exception {
      _files.remove(key);
      return null;
    }
  }
}

import 'package:app/landmarks/models/landmark_object.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';

/// Сведения об объекте картинкой. Рисование появится вместе с UI
/// (Flutter Canvas); пока вызов честно сообщает, что функция недоступна.
class DetailsImageExporter {
  const DetailsImageExporter(this.paths, this.storage);

  final StoragePaths paths;
  final StorageService storage;

  /// Всегда [UnsupportedError]: экспорт картинкой ещё не сделан.
  Future<String> export(LandmarkObject object, String targetFolder, {String? preferredFilename}) =>
      Future.error(UnsupportedError('Exporting details as an image is not available yet'));
}

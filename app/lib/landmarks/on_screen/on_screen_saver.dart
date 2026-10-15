import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';

/// «Сохранить все» в «Метках на экране»: копии меток — в один новый файл
/// меток (`.ldk`).
abstract final class OnScreenSaver {
  /// Создаёт файл меток [name] (с [comment] и [description]) в [folder]
  /// (по умолчанию — папка новых меток) и кладёт в него копии файлов
  /// [paths]. Файл меток среди них отдаёт свои объекты — вложенных файлов
  /// меток не бывает. Возвращает путь нового файла.
  static Future<String> saveAll(
    LandmarkServices services,
    List<String> paths, {
    required String name,
    String? comment,
    String? description,
    String? folder,
  }) async {
    final objects = <LandmarkObject>[];
    for (final path in paths) {
      final content = (await services.repository.load(path)).content;
      if (content is LdkFileObject) {
        objects.addAll(content.objects);
      } else {
        objects.add(content);
      }
    }
    final target = await services.creation.create(
      MarkerDraft(
        type: LandmarkType.ldkFile,
        name: name,
        comment: comment,
        description: description,
        longitude: 0,
        latitude: 0,
        targetFolder: folder,
      ),
    );
    final created = (await services.repository.load(target)).content as LdkFileObject;
    await services.repository.update(
      target,
      LandmarkFile.of(
        LdkFileObject(
          userMetadata: created.userMetadata,
          technicalMetadata: created.technicalMetadata,
          objects: objects,
        ),
      ),
    );
    return target;
  }
}

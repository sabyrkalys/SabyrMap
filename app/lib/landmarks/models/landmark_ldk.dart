import 'package:collection/collection.dart';

import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';

/// Файл меток (`.ldk`): метаданные (имя, комментарий, описание) и
/// вложенные объекты — копии точек, наборов, маршрутов, треков и областей.
///
/// Decision: вложенных файлов меток нет — список плоский, как «Метки на
/// экране», из которых он сохраняется.
class LdkFileObject extends LandmarkObject {
  const LdkFileObject({
    this.userMetadata = const LandmarkMetadata(),
    this.technicalMetadata = const LandmarkMetadata(),
    this.objects = const [],
  });

  @override
  final LandmarkMetadata userMetadata;

  @override
  final LandmarkMetadata technicalMetadata;

  /// Вложенные объекты, по порядку; [LdkFileObject] среди них нет.
  final List<LandmarkObject> objects;

  @override
  LandmarkType get type => LandmarkType.ldkFile;

  @override
  LdkFileObject withUserMetadata(LandmarkMetadata userMetadata) =>
      LdkFileObject(userMetadata: userMetadata, technicalMetadata: technicalMetadata, objects: objects);

  @override
  LdkFileObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) =>
      LdkFileObject(userMetadata: userMetadata, technicalMetadata: technicalMetadata, objects: objects);

  static const _list = ListEquality<LandmarkObject>();

  @override
  bool operator ==(Object other) =>
      other is LdkFileObject &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata &&
      _list.equals(other.objects, objects);

  @override
  int get hashCode => Object.hash(userMetadata, technicalMetadata, _list.hash(objects));
}

import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';

/// Файл меток (`.ldk`).
///
/// Decision: в этой итерации у файла только метаданные (имя, комментарий,
/// описание), payload пустой; дерево вложенных объектов — отдельный слой.
class LdkFileObject extends LandmarkObject {
  const LdkFileObject({
    this.userMetadata = const LandmarkMetadata(),
    this.technicalMetadata = const LandmarkMetadata(),
  });

  @override
  final LandmarkMetadata userMetadata;

  @override
  final LandmarkMetadata technicalMetadata;

  @override
  LandmarkType get type => LandmarkType.ldkFile;

  @override
  LdkFileObject withUserMetadata(LandmarkMetadata userMetadata) =>
      LdkFileObject(
        userMetadata: userMetadata,
        technicalMetadata: technicalMetadata,
      );

  @override
  LdkFileObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) =>
      LdkFileObject(
        userMetadata: userMetadata,
        technicalMetadata: technicalMetadata,
      );

  @override
  bool operator ==(Object other) =>
      other is LdkFileObject &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata;

  @override
  int get hashCode => Object.hash(userMetadata, technicalMetadata);
}

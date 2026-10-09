import 'package:app/landmarks/models/landmark_object.dart';
import 'package:app/landmarks/models/landmark_type.dart';

/// Объект, открытый в режиме правки.
class EditModeTarget {
  const EditModeTarget({
    required this.filePath,
    required this.type,
    required this.object,
    this.isDirty = false,
    this.historyDepth = 0,
  });

  final String filePath;
  final LandmarkType type;

  /// Текущая (несохранённая) версия объекта.
  final LandmarkObject object;

  /// Отличается ли объект от того, что в файле.
  final bool isDirty;

  /// Сколько шагов можно отменить.
  final int historyDepth;

  EditModeTarget copyWith({LandmarkObject? object, bool? isDirty, int? historyDepth}) => EditModeTarget(
    filePath: filePath,
    type: type,
    object: object ?? this.object,
    isDirty: isDirty ?? this.isDirty,
    historyDepth: historyDepth ?? this.historyDepth,
  );
}

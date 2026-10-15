import 'package:app/landmarks/models/landmark_object.dart';
import 'package:app/landmarks/models/landmark_type.dart';

/// Объект, открытый в режиме правки.
class EditModeTarget {
  const EditModeTarget({
    this.filePath,
    this.folder,
    required this.type,
    required this.object,
    this.isDirty = false,
    this.historyDepth = 0,
  });

  /// Файл объекта; null — новый объект, ещё не сохранённый ([isNew]).
  final String? filePath;

  /// Куда сохранить новый объект; null — папка новых меток.
  final String? folder;
  final LandmarkType type;

  bool get isNew => filePath == null;

  /// Текущая (несохранённая) версия объекта.
  final LandmarkObject object;

  /// Отличается ли объект от того, что в файле.
  final bool isDirty;

  /// Сколько шагов можно отменить.
  final int historyDepth;

  EditModeTarget copyWith({LandmarkObject? object, bool? isDirty, int? historyDepth}) => EditModeTarget(
    filePath: filePath,
    folder: folder,
    type: type,
    object: object ?? this.object,
    isDirty: isDirty ?? this.isDirty,
    historyDepth: historyDepth ?? this.historyDepth,
  );
}

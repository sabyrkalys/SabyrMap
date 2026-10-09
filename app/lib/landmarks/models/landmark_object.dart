import 'landmark_metadata.dart';
import 'landmark_type.dart';

/// Объект верхнего уровня в файле метки.
abstract class LandmarkObject {
  const LandmarkObject();

  LandmarkType get type;

  /// Видимые пользователю свойства: имя, цвет, иконка, описание...
  LandmarkMetadata get userMetadata;

  /// Служебные свойства файла: время создания и правки, версия.
  LandmarkMetadata get technicalMetadata;

  /// Копия с другими служебными метаданными (тем же содержимым).
  LandmarkObject withTechnicalMetadata(LandmarkMetadata technicalMetadata);

  /// Копия с другими пользовательскими метаданными (тем же содержимым).
  LandmarkObject withUserMetadata(LandmarkMetadata userMetadata);
}

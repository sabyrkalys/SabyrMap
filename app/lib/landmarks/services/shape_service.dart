import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:app/landmarks/validation/waypoint_validator.dart';

/// Геометрия круга и текста: центр/точка, радиус, надпись. Свойства (имя,
/// цвет...) правятся общей правкой метаданных; запись — через
/// репозиторий (индекс меток обновляется сам).
class ShapeService {
  ShapeService(this._repository);

  final LandmarkRepository _repository;

  /// Меняет центр и/или радиус круга [path]; возвращает записанный круг.
  Future<CircleObject> updateCircle(String path, {LandmarkLocation? center, double? radiusMeters}) async {
    final circle = await _load<CircleObject>(path);
    if (radiusMeters != null &&
        (!radiusMeters.isFinite || radiusMeters <= 0 || radiusMeters > WaypointValidator.maxRadiusMeters)) {
      throw ValidationException(['radiusMeters must be within (0, ${WaypointValidator.maxRadiusMeters}]']);
    }
    final next = circle.copyWith(center: center, radiusMeters: radiusMeters);
    await _repository.update(path, LandmarkFile.of(next));
    return next;
  }

  /// Меняет точку и/или надпись текста [path]; возвращает записанный текст.
  Future<TextObject> updateText(String path, {LandmarkLocation? location, String? text}) async {
    final label = await _load<TextObject>(path);
    final trimmed = text?.trim();
    if (trimmed != null && (trimmed.isEmpty || trimmed.length > WaypointValidator.maxTextLength)) {
      throw ValidationException(['text must be 1..${WaypointValidator.maxTextLength} characters']);
    }
    final next = label.copyWith(location: location, text: trimmed);
    await _repository.update(path, LandmarkFile.of(next));
    return next;
  }

  Future<T> _load<T extends LandmarkObject>(String path) async {
    final content = (await _repository.load(path)).content;
    if (content is! T) throw ArgumentError.value(path, 'path', 'not a ${T.toString()}');
    return content;
  }
}

import 'package:app/landmarks/models/landmark_area.dart';
import 'package:app/landmarks/models/landmark_location.dart';

/// Правка многоугольника области. Чистые функции: возвращают новый
/// многоугольник; неверный индекс — [RangeError].
abstract final class PolygonOps {
  /// Вставляет точку контура на место [atIndex] (по умолчанию — в конец).
  static AreaPolygon addOutlinePoint(AreaPolygon polygon, LandmarkLocation location, {int? atIndex}) {
    final index = atIndex ?? polygon.outline.length;
    RangeError.checkValueInInterval(index, 0, polygon.outline.length, 'atIndex');
    return _withOutline(polygon, [...polygon.outline]..insert(index, location));
  }

  static AreaPolygon removeOutlinePoint(AreaPolygon polygon, int index) {
    RangeError.checkValidIndex(index, polygon.outline, 'index');
    return _withOutline(polygon, [...polygon.outline]..removeAt(index));
  }

  static AreaPolygon moveOutlinePoint(AreaPolygon polygon, int index, LandmarkLocation location) {
    RangeError.checkValidIndex(index, polygon.outline, 'index');
    return _withOutline(polygon, [...polygon.outline]..[index] = location);
  }

  /// Переносит точку контура с [from] на место [to].
  static AreaPolygon reorderOutline(AreaPolygon polygon, int from, int to) {
    RangeError.checkValidIndex(from, polygon.outline, 'from');
    RangeError.checkValidIndex(to, polygon.outline, 'to');
    final out = [...polygon.outline];
    out.insert(to, out.removeAt(from));
    return _withOutline(polygon, out);
  }

  static AreaPolygon addHole(AreaPolygon polygon, List<LandmarkLocation> hole) =>
      AreaPolygon(userMetadata: polygon.userMetadata, outline: polygon.outline, holes: [...polygon.holes, hole]);

  static AreaPolygon removeHole(AreaPolygon polygon, int holeIndex) {
    RangeError.checkValidIndex(holeIndex, polygon.holes, 'holeIndex');
    return AreaPolygon(
      userMetadata: polygon.userMetadata,
      outline: polygon.outline,
      holes: [...polygon.holes]..removeAt(holeIndex),
    );
  }

  static AreaPolygon _withOutline(AreaPolygon polygon, List<LandmarkLocation> outline) =>
      AreaPolygon(userMetadata: polygon.userMetadata, outline: outline, holes: polygon.holes);
}

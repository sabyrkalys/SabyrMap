import 'package:app/landmarks/models/landmark_waypoint.dart';

/// Правка списка путевых точек. Чистые функции: возвращают новый список,
/// неверный индекс — [RangeError].
abstract final class WaypointOps {
  /// Вставляет [wp] на место [atIndex] (по умолчанию — в конец).
  static List<WaypointObject> add(List<WaypointObject> list, WaypointObject wp, {int? atIndex}) {
    final index = atIndex ?? list.length;
    RangeError.checkValueInInterval(index, 0, list.length, 'atIndex');
    return [...list]..insert(index, wp);
  }

  static List<WaypointObject> removeAt(List<WaypointObject> list, int index) {
    RangeError.checkValidIndex(index, list, 'index');
    return [...list]..removeAt(index);
  }

  static List<WaypointObject> replaceAt(List<WaypointObject> list, int index, WaypointObject wp) {
    RangeError.checkValidIndex(index, list, 'index');
    return [...list]..[index] = wp;
  }

  /// Переносит элемент с [from] так, чтобы он оказался на месте [to].
  static List<WaypointObject> reorder(List<WaypointObject> list, int from, int to) {
    RangeError.checkValidIndex(from, list, 'from');
    RangeError.checkValidIndex(to, list, 'to');
    final out = [...list];
    out.insert(to, out.removeAt(from));
    return out;
  }

  static List<WaypointObject> reverseOrder(List<WaypointObject> list) => list.reversed.toList();
}

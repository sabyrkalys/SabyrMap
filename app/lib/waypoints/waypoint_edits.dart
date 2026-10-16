import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/landmark_services_provider.dart';
import 'waypoint_color.dart';

/// Правки путевых точек из диалогов карты — файлы `.wpt` через сервисы
/// меток. Отдельной модели точки нет: карта и списки читают точки из
/// индекса меток, а он обновляется после каждой записи.
///
/// Поля диалога хранятся в пользовательских метаданных: тип метки —
/// `type`, заметка — `description`, цвет — `color` (ARGB), значок из
/// библиотеки — `user_icon`, комментарий и значок метки — `comment` и
/// `icon`.
class WaypointEdits {
  WaypointEdits(this._services);

  final LandmarkServices _services;

  /// Ключ типа метки приложения в метаданных.
  static const String typeKey = 'type';

  /// Имена всех путевых точек — для следующего «Путевая точка N».
  Iterable<String> get names => _services.index.byType(LandmarkType.waypoint).map((item) => item.name);

  /// Новая точка; возвращает её путь.
  Future<String> create({
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
    String? iconFileName,
    String? folder,
    Map<String, Object> extra = const {},
  }) => _guard('Could not create waypoint', () {
    return _services.creation.create(
      MarkerDraft(
        type: LandmarkType.waypoint,
        longitude: lng,
        latitude: lat,
        name: name,
        description: note,
        colorValue: _argb(color),
        targetFolder: folder,
        extraMetadata: {typeKey: type, LandmarkMetadata.userIconKey: ?iconFileName, ...extra},
      ),
    );
  });

  /// Правка точки [path]; [iconFileName] null — значок из библиотеки
  /// снимается.
  Future<void> update(
    String path, {
    required String name,
    required String type,
    required String note,
    required String? color,
    required String? iconFileName,
  }) => _guard('Could not update waypoint', () {
    return _services.waypoints.update(
      path,
      WaypointPatch(
        name: name,
        description: note,
        extra: {typeKey: type, LandmarkMetadata.colorKey: _argb(color), LandmarkMetadata.userIconKey: iconFileName},
      ),
    );
  });

  Future<void> delete(String path) => _guard('Could not delete waypoint', () => _services.waypoints.delete(path));

  static Future<T> _guard<T>(String what, Future<T> Function() action) async {
    try {
      return await action();
    } on ValidationException catch (e) {
      throw WaypointException(e.errors.join('; '));
    } on Exception catch (e) {
      throw WaypointException('$what: $e');
    }
  }

  /// `#RRGGBB` → непрозрачный ARGB; null — без своего цвета.
  static int? _argb(String? hex) => hex == null ? null : colorFromHex(hex).toARGB32();
}

final waypointEditsProvider = Provider<WaypointEdits>((ref) => WaypointEdits(ref.watch(landmarkServicesProvider)));

class WaypointException implements Exception {
  const WaypointException(this.message);

  final String message;

  @override
  String toString() => 'WaypointException: $message';
}

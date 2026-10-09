import 'package:app/landmarks/models/landmark_location.dart';

import 'intent_kind.dart';
import 'intent_payload.dart';

/// Разбор внешнего запроса (action + extras).
abstract final class IntentParser {
  /// Действие → вид запроса.
  ///
  /// Decision: действие узнаётся по последнему сегменту после точки
  /// (`<пространство имён>.DISPLAY_LOCATION`), без привязки к пространству
  /// имён — так один разбор принимает запросы любых приложений-источников.
  static const Map<String, IntentKind> actions = {
    'DISPLAY_LOCATION': IntentKind.displayLocation,
    'LANDMARKS_FAST_WAYPOINT': IntentKind.fastWaypoint,
    'TRACKER_START': IntentKind.trackerStart,
    'TRACKER_STOP': IntentKind.trackerStop,
    'TRACKER_ADD_WAYPOINT': IntentKind.trackerAddWaypoint,
    'APP_STOP': IntentKind.appStop,
  };

  /// Ключи extras — без учёта регистра.
  static IntentPayload parse(Map<String, Object?> extras, {String? action}) {
    final kind = action == null ? IntentKind.unknown : (actions[action.split('.').last.toUpperCase()] ?? IntentKind.unknown);
    final e = {for (final entry in extras.entries) entry.key.toLowerCase(): entry.value};
    Object? any(List<String> keys) => keys.map((k) => e[k]).firstWhere((v) => v != null, orElse: () => null);

    final lat = _double(any(['latitude', 'lat']));
    final lon = _double(any(['longitude', 'lon', 'lng']));
    final valid = lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180;
    return IntentPayload(
      kind: kind,
      location: valid ? LandmarkLocation(latitude: lat, longitude: lon) : null,
      elevationMeters: _double(any(['elevation', 'altitude', 'ele', 'alt'])),
      heading: _double(any(['heading', 'bearing'])),
      timestampSec: _double(any(['time', 'timestamp']))?.round(),
      name: _string(any(['name', 'title'])),
      comment: _string(any(['comment'])),
      description: _string(any(['description', 'desc'])),
      iconId: _string(any(['icon', 'icon_id', 'iconid'])),
      memId: _string(any(['mem_id', 'memid'])),
      trackId: _string(any(['track_id', 'trackid'])),
      setId: _string(any(['set_id', 'setid'])),
      moveTo: _bool(any(['move_to', 'moveto'])),
    );
  }

  static double? _double(Object? v) => switch (v) {
    final num n when n.isFinite => n.toDouble(),
    final String s => double.tryParse(s.trim()),
    _ => null,
  };

  static String? _string(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  static bool _bool(Object? v) => switch (v) {
    final bool b => b,
    final num n => n != 0,
    final String s => s.toLowerCase() == 'true' || s == '1',
    _ => false,
  };
}

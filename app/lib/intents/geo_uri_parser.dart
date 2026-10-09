import 'package:app/landmarks/models/landmark_location.dart';

import 'intent_kind.dart';
import 'intent_payload.dart';

/// Разбор `geo:` ссылок (RFC 5870 и вариант с `?q=`).
///
/// `geo:55.75,37.61`, `geo:55.75,37.61,150;crs=wgs84?z=12`,
/// `geo:55.75,37.61(Москва)`, `geo:0,0?q=55.75,37.61(Москва)`.
/// Система координат кроме WGS84 (в том числе UTM) — null.
abstract final class GeoUriParser {
  static final RegExp _point = RegExp(r'^\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)(?:\s*,\s*([+-]?\d+(?:\.\d+)?))?');

  static IntentPayload? parse(String uri) {
    final raw = uri.trim().replaceAll('+', ' ');
    String text;
    try {
      text = Uri.decodeFull(raw);
    } on ArgumentError {
      // Не %-кодированная ссылка (например, с кириллицей как есть).
      text = raw;
    }
    if (!text.toLowerCase().startsWith('geo:')) return null;
    var body = text.substring(4);
    var query = '';
    final q = body.indexOf('?');
    if (q >= 0) {
      query = body.substring(q + 1);
      body = body.substring(0, q);
    }
    final params = body.split(';');
    for (final param in params.skip(1)) {
      final kv = param.split('=');
      if (kv.first.trim().toLowerCase() == 'crs') {
        final crs = kv.length > 1 ? kv[1].trim().toLowerCase() : '';
        if (crs != 'wgs84' && crs != 'epsg:4326') return null;
      }
    }

    String? queryValue(String key) {
      for (final part in query.split('&')) {
        final i = part.indexOf('=');
        if (i > 0 && part.substring(0, i).toLowerCase() == key) return part.substring(i + 1);
      }
      return null;
    }

    var point = params.first;
    final fromQuery = queryValue('q');
    final main = _point.firstMatch(point);
    final isZero = main != null && double.parse(main[1]!) == 0 && double.parse(main[2]!) == 0;
    if (fromQuery != null && (_point.hasMatch(fromQuery)) && (main == null || isZero)) point = fromQuery;

    final m = _point.firstMatch(point);
    if (m == null) return null;
    final lat = double.parse(m[1]!);
    final lon = double.parse(m[2]!);
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    final name = RegExp(r'\(([^)]*)\)').firstMatch(point)?.group(1)?.trim() ??
        RegExp(r'\(([^)]*)\)').firstMatch(fromQuery ?? '')?.group(1)?.trim();
    return IntentPayload(
      kind: IntentKind.displayLocation,
      location: LandmarkLocation(latitude: lat, longitude: lon),
      elevationMeters: m[3] == null ? null : double.parse(m[3]!),
      name: name == null || name.isEmpty ? null : name,
      moveTo: true,
    );
  }
}

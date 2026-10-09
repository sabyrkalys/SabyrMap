import 'package:app/landmarks/models/landmark_location.dart';

import 'intent_kind.dart';
import 'intent_payload.dart';

/// Координаты из ссылок веб-карт Google (`maps.google.com`,
/// `www.google.com/maps`, `goo.gl/maps`): `/@lat,lon`, `?q=lat,lon`,
/// `?ll=lat,lon`, `?query=lat,lon`, `/place/<имя>/@lat,lon`.
/// Короткие ссылки без координат в адресе (их раскрывает только сеть)
/// и прочие хосты — null.
abstract final class GoogleMapsParser {
  static final RegExp _pair = RegExp(r'^\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)');
  static final RegExp _at = RegExp(r'/@([+-]?\d+(?:\.\d+)?),([+-]?\d+(?:\.\d+)?)');

  static IntentPayload? parse(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url.trim());
    } on FormatException {
      return null;
    }
    if (!_supported(uri)) return null;

    (double, double)? coords;
    final at = _at.firstMatch(uri.path);
    if (at != null) coords = (double.parse(at[1]!), double.parse(at[2]!));
    for (final key in ['q', 'll', 'query', 'center']) {
      if (coords != null) break;
      final v = uri.queryParameters[key];
      final m = v == null ? null : _pair.firstMatch(v);
      if (m != null) coords = (double.parse(m[1]!), double.parse(m[2]!));
    }
    if (coords == null) return null;
    final (lat, lon) = coords;
    if (lat.abs() > 90 || lon.abs() > 180) return null;

    final segments = uri.pathSegments;
    final place = segments.indexOf('place');
    final rawName = place >= 0 && place + 1 < segments.length ? segments[place + 1] : null;
    final name = rawName?.replaceAll('+', ' ').trim();
    return IntentPayload(
      kind: IntentKind.displayLocation,
      location: LandmarkLocation(latitude: lat, longitude: lon),
      name: name == null || name.isEmpty || name.startsWith('@') ? null : name,
      moveTo: true,
    );
  }

  static bool _supported(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (host == 'maps.google.com') return true;
    if ((host == 'www.google.com' || host == 'google.com') && path.startsWith('/maps')) return true;
    if (host == 'goo.gl' && path.startsWith('/maps')) return true;
    return false;
  }
}

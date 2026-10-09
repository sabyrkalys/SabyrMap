import 'dart:typed_data';

import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/import_export/utils/xml_utils.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:xml/xml.dart';

/// Разбор GPX 1.0/1.1: `<wpt>` → путевые точки, `<rte>` → маршруты,
/// `<trk>` → треки.
class GpxParser {
  const GpxParser();

  /// Опция: путевые точки файла с единственным треком прикрепляются к нему.
  static const String includeWaypointsInTrack = 'includeWaypointsInTrack';

  /// Пространство имён расширений sabyrmap (цвет).
  static const String sabyrmapNamespace = 'urn:sabyrmap:gpx:1';

  /// Объекты файла в порядке: точки, маршруты, треки. Не GPX или битый
  /// XML — [FormatException]; неверная точка — пропуск с предупреждением.
  List<LandmarkObject> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning}) {
    final doc = XmlUtils.parseBytes(bytes, charset: options.charset);
    final root = doc.rootElement;
    if (root.localName != 'gpx') throw FormatException('Not a GPX file: root is <${root.localName}>');
    void warn(String w) => onWarning?.call(w);

    final waypoints = <WaypointObject>[];
    for (final (i, el) in XmlUtils.children(root, 'wpt').indexed) {
      final wp = _waypoint(el, options, warn, 'wpt $i');
      if (wp != null) waypoints.add(wp);
    }
    final routes = <RouteObject>[];
    for (final (i, el) in XmlUtils.children(root, 'rte').indexed) {
      routes.add(
        RouteObject(
          userMetadata: _metadata(el),
          waypoints: [
            for (final (j, pt) in XmlUtils.children(el, 'rtept').indexed) ?_waypoint(pt, options, warn, 'rte $i point $j'),
          ],
        ),
      );
    }
    final tracks = <TrackObject>[];
    for (final (i, el) in XmlUtils.children(root, 'trk').indexed) {
      tracks.add(
        TrackObject(
          userMetadata: _metadata(el),
          segments: [
            for (final (s, seg) in XmlUtils.children(el, 'trkseg').indexed)
              TrackSegment(
                locations: [
                  for (final (j, pt) in XmlUtils.children(seg, 'trkpt').indexed)
                    ?_location(pt, options, warn, 'trk $i segment $s point $j'),
                ],
              ),
          ],
        ),
      );
    }

    final attach = options.extra(includeWaypointsInTrack, true) && tracks.length == 1 && waypoints.isNotEmpty;
    if (attach) {
      final t = tracks.single;
      tracks[0] = TrackObject(waypoints: waypoints, segments: t.segments, userMetadata: t.userMetadata);
    }
    return [if (!attach) ...waypoints, ...routes, ...tracks];
  }

  WaypointObject? _waypoint(XmlElement el, ImportOptions options, void Function(String) warn, String where) {
    final location = _location(el, options, warn, where);
    return location == null ? null : WaypointObject(location: location, userMetadata: _metadata(el));
  }

  LandmarkLocation? _location(XmlElement el, ImportOptions options, void Function(String) warn, String where) {
    final lat = double.tryParse(el.getAttribute('lat') ?? '');
    final lon = double.tryParse(el.getAttribute('lon') ?? '');
    if (lat == null || lon == null) {
      warn('$where: missing or invalid lat/lon, skipped');
      return null;
    }
    try {
      return FormatSupport.location(
        lat,
        lon,
        elevation: double.tryParse(XmlUtils.childText(el, 'ele') ?? ''),
        timeMs: FormatSupport.parseIsoTime(XmlUtils.childText(el, 'time')),
        options: options,
      );
    } on FormatException catch (e) {
      warn('$where: ${e.message}, skipped');
      return null;
    }
  }

  static LandmarkMetadata _metadata(XmlElement el) {
    final extensions = XmlUtils.child(el, 'extensions');
    return FormatSupport.metadata(
      name: XmlUtils.childText(el, 'name'),
      comment: XmlUtils.childText(el, 'cmt'),
      description: XmlUtils.childText(el, 'desc'),
      icon: XmlUtils.childText(el, 'sym'),
      color: extensions == null ? null : FormatSupport.parseHexColor(XmlUtils.childText(extensions, 'color')),
    );
  }
}

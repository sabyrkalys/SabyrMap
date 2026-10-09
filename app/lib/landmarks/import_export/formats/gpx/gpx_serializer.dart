import 'dart:typed_data';

import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/import_export/utils/elevation_source.dart';
import 'package:app/landmarks/import_export/utils/xml_utils.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:xml/xml.dart';

import 'gpx_parser.dart';

/// Запись GPX 1.1: путевые точки, маршруты, треки. Наборы и области GPX не
/// умеет — они пропускаются с предупреждением.
class GpxSerializer {
  const GpxSerializer();

  /// Опция экспорта: писать ли высоты (`none` — не писать).
  static const String elevationSource = 'elevationSource';

  Uint8List serialize(List<LandmarkObject> objects, ExportOptions options, {WarningSink? onWarning}) {
    final writeElevation = ElevationSource.parse(options.extras[elevationSource]).readsElevation;
    final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
    if (options.charset != null && options.charset!.toLowerCase().replaceAll('_', '-') != 'utf-8') {
      onWarning?.call('GPX is always written in UTF-8; charset ${options.charset} ignored');
    }
    b.element(
      'gpx',
      attributes: {
        'version': '1.1',
        'creator': 'sabyrmap',
        'xmlns': 'http://www.topografix.com/GPX/1/1',
        'xmlns:sabyrmap': GpxParser.sabyrmapNamespace,
      },
      nest: () {
        // Схема GPX: сначала все wpt, затем rte, затем trk.
        for (final o in objects) {
          if (o is WaypointObject) _point(b, 'wpt', o.location, o.userMetadata, writeElevation);
          if (o is TrackObject && options.includeWaypoints) {
            for (final w in o.waypoints) {
              _point(b, 'wpt', w.location, w.userMetadata, writeElevation);
            }
          }
        }
        for (final o in objects.whereType<RouteObject>()) {
          b.element(
            'rte',
            nest: () {
              _meta(b, o.userMetadata);
              for (final w in o.waypoints) {
                _point(b, 'rtept', w.location, w.userMetadata, writeElevation);
              }
            },
          );
        }
        for (final o in objects.whereType<TrackObject>()) {
          final segments = options.includeSegments
              ? [for (final s in o.segments) s.locations]
              : [
                  [for (final s in o.segments) ...s.locations],
                ];
          b.element(
            'trk',
            nest: () {
              _meta(b, o.userMetadata);
              for (final locations in segments) {
                b.element(
                  'trkseg',
                  nest: () {
                    for (final l in locations) {
                      _point(b, 'trkpt', l, const LandmarkMetadata(), writeElevation);
                    }
                  },
                );
              }
            },
          );
        }
        for (final o in objects.where((o) => o is SetObject || o is AreaObject)) {
          onWarning?.call('GPX cannot hold a ${o.type.extension} object; skipped');
        }
      },
    );
    return XmlUtils.serialize(b.buildDocument());
  }

  static void _point(XmlBuilder b, String tag, LandmarkLocation l, LandmarkMetadata m, bool writeElevation) {
    b.element(
      tag,
      attributes: {'lat': _number(l.latitude), 'lon': _number(l.longitude)},
      nest: () {
        final ele = FormatSupport.elevationOf(l);
        if (ele != null && writeElevation) b.element('ele', nest: _number(ele));
        final time = FormatSupport.timeOf(l);
        if (time != null) b.element('time', nest: FormatSupport.isoTime(time));
        _meta(b, m);
      },
    );
  }

  /// name, cmt, desc, sym и цвет в расширении — в порядке схемы GPX.
  static void _meta(XmlBuilder b, LandmarkMetadata m) {
    if (m.name != null) b.element('name', nest: m.name);
    if (m.comment != null) b.element('cmt', nest: m.comment);
    if (m.description != null) b.element('desc', nest: m.description);
    if (m.iconId != null) b.element('sym', nest: m.iconId);
    if (m.colorValue != null) {
      b.element(
        'extensions',
        nest: () => b.element('sabyrmap:color', nest: FormatSupport.hexColor(m.colorValue!)),
      );
    }
  }

  static String _number(double v) {
    final s = v.toStringAsFixed(7);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }
}

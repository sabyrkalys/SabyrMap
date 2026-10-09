import 'dart:typed_data';

import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/import_export/utils/xml_utils.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Запись KML 2.2 (или KMZ — ZIP с `doc.kml`).
class KmlSerializer {
  const KmlSerializer();

  /// Опция: KMZ вместо KML.
  static const String asKmz = 'asKmz';

  /// Опция: вложить картинки в KMZ (пока не поддерживается).
  static const String embedPictures = 'embedPictures';

  Uint8List serialize(List<LandmarkObject> objects, ExportOptions options, {WarningSink? onWarning}) {
    if (options.extra(embedPictures, false)) {
      onWarning?.call('Embedding pictures into KMZ is not supported yet; pictures were not added');
    }
    final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element(
      'kml',
      attributes: {'xmlns': 'http://www.opengis.net/kml/2.2'},
      nest: () => b.element(
        'Document',
        nest: () {
          for (final o in objects) {
            switch (o) {
              case WaypointObject():
                _placemark(b, o.userMetadata, () => _point(b, o.location));
              case RouteObject():
                _placemark(b, o.userMetadata, () => _line(b, [for (final w in o.waypoints) w.location]));
              case TrackObject():
                final lines = options.includeSegments
                    ? [for (final s in o.segments) s.locations]
                    : [
                        [for (final s in o.segments) ...s.locations],
                      ];
                _placemark(b, o.userMetadata, () => _multi(b, lines, _line));
                if (options.includeWaypoints) {
                  for (final w in o.waypoints) {
                    _placemark(b, w.userMetadata, () => _point(b, w.location));
                  }
                }
              case AreaObject():
                _placemark(b, o.userMetadata, () => _multi(b, o.polygons, _polygon));
              default:
                onWarning?.call('KML export does not support ${o.type.extension} objects; skipped');
            }
          }
        },
      ),
    );
    final kml = XmlUtils.serialize(b.buildDocument());
    if (!options.extra(asKmz, false)) return kml;
    final archive = Archive()..addFile(ArchiveFile.bytes('doc.kml', kml));
    return ZipEncoder().encodeBytes(archive);
  }

  static void _placemark(XmlBuilder b, LandmarkMetadata m, void Function() geometry) {
    b.element(
      'Placemark',
      nest: () {
        if (m.name != null) b.element('name', nest: m.name);
        final text = m.description ?? m.comment;
        if (text != null) b.element('description', nest: text);
        if (m.colorValue != null || m.iconId != null) {
          b.element(
            'Style',
            nest: () {
              if (m.colorValue != null || m.iconId != null) {
                b.element(
                  'IconStyle',
                  nest: () {
                    if (m.colorValue != null) b.element('color', nest: argbToKmlColor(m.colorValue!));
                    if (m.iconId != null) b.element('Icon', nest: () => b.element('href', nest: m.iconId));
                  },
                );
              }
              if (m.colorValue != null) {
                b.element('LineStyle', nest: () => b.element('color', nest: argbToKmlColor(m.colorValue!)));
              }
            },
          );
        }
        geometry();
      },
    );
  }

  /// Несколько геометрий — в MultiGeometry, одна — как есть.
  static void _multi<T>(XmlBuilder b, List<T> items, void Function(XmlBuilder, T) write) {
    if (items.length == 1) {
      write(b, items.single);
    } else {
      b.element(
        'MultiGeometry',
        nest: () {
          for (final item in items) {
            write(b, item);
          }
        },
      );
    }
  }

  static void _point(XmlBuilder b, LandmarkLocation l) =>
      b.element('Point', nest: () => b.element('coordinates', nest: _tuple(l)));

  static void _line(XmlBuilder b, List<LandmarkLocation> locations) => b.element(
    'LineString',
    nest: () => b.element('coordinates', nest: locations.map(_tuple).join(' ')),
  );

  static void _polygon(XmlBuilder b, AreaPolygon polygon) {
    void ring(String boundary, List<LandmarkLocation> points) => b.element(
      boundary,
      nest: () => b.element(
        'LinearRing',
        nest: () => b.element('coordinates', nest: [...points, ?points.firstOrNull].map(_tuple).join(' ')),
      ),
    );
    b.element(
      'Polygon',
      nest: () {
        ring('outerBoundaryIs', polygon.outline);
        for (final hole in polygon.holes) {
          ring('innerBoundaryIs', hole);
        }
      },
    );
  }

  static String _tuple(LandmarkLocation l) {
    final ele = FormatSupport.elevationOf(l);
    return [_n(l.longitude), _n(l.latitude), if (ele != null) _n(ele)].join(',');
  }

  static String _n(double v) {
    final s = v.toStringAsFixed(7);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// ARGB → KML-цвет `aabbggrr`.
  static String argbToKmlColor(int argb) {
    final hex = FormatSupport.hexColor(argb).toLowerCase();
    final a = hex.substring(0, 2);
    final r = hex.substring(2, 4);
    final g = hex.substring(4, 6);
    final bl = hex.substring(6, 8);
    return '$a$bl$g$r';
  }
}

import 'dart:typed_data';

import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/import_export/utils/xml_utils.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Разбор KML и KMZ (ZIP с `doc.kml`).
///
/// - `Point` → путевая точка;
/// - `LineString` → трек из одного сегмента;
/// - `Polygon` / `LinearRing` → область;
/// - `MultiGeometry` делится по видам. Decision: точки — отдельные путевые
///   точки; линии — один трек, по сегменту на линию; многоугольники —
///   одна область, по многоугольнику на каждый. Так трек из нескольких
///   сегментов возвращается тем же, каким был выгружен.
///
/// Стили — частично: цвет линии (или значка) → `color`, ссылка значка →
/// `icon`.
class KmlParser {
  const KmlParser();

  List<LandmarkObject> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning}) {
    final doc = XmlUtils.parseBytes(isZip(bytes) ? kmlFromKmz(bytes) : bytes, charset: options.charset);
    if (doc.rootElement.localName != 'kml') {
      throw FormatException('Not a KML file: root is <${doc.rootElement.localName}>');
    }
    final styles = _styles(doc);
    final objects = <LandmarkObject>[];
    for (final (i, placemark) in XmlUtils.descendants(doc, 'Placemark').indexed) {
      try {
        objects.addAll(_placemark(placemark, styles, options, onWarning));
      } on FormatException catch (e) {
        onWarning?.call('Placemark $i: ${e.message}, skipped');
      }
    }
    return objects;
  }

  /// ZIP по сигнатуре `PK\x03\x04`.
  static bool isZip(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;

  /// `doc.kml` из KMZ (или первый `.kml` в архиве).
  static Uint8List kmlFromKmz(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      throw FormatException('Invalid KMZ archive: $e');
    }
    final file =
        archive.findFile('doc.kml') ?? archive.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('.kml')).firstOrNull;
    if (file == null) throw const FormatException('KMZ archive has no .kml file');
    return file.content;
  }

  List<LandmarkObject> _placemark(
    XmlElement placemark,
    Map<String, _Style> styles,
    ImportOptions options,
    WarningSink? onWarning,
  ) {
    final style = _styleOf(placemark, styles);
    final metadata = FormatSupport.metadata(
      name: XmlUtils.childText(placemark, 'name'),
      description: XmlUtils.childText(placemark, 'description'),
      color: style?.color,
      icon: style?.icon,
    );
    final points = <LandmarkLocation>[];
    final lines = <List<LandmarkLocation>>[];
    final polygons = <AreaPolygon>[];
    void collect(XmlElement geometry) {
      switch (geometry.localName) {
        case 'Point':
          points.addAll(_coordinates(geometry, options).take(1));
        case 'LineString':
          lines.add(_coordinates(geometry, options));
        case 'LinearRing':
          polygons.add(AreaPolygon(outline: FormatSupport.openRing(_coordinates(geometry, options))));
        case 'Polygon':
          polygons.add(_polygon(geometry, options));
        case 'MultiGeometry':
          geometry.childElements.forEach(collect);
        default:
          onWarning?.call('Unsupported KML geometry <${geometry.localName}> skipped');
      }
    }

    for (final child in placemark.childElements) {
      if (const {'Point', 'LineString', 'LinearRing', 'Polygon', 'MultiGeometry'}.contains(child.localName)) {
        collect(child);
      }
    }
    if (points.isEmpty && lines.isEmpty && polygons.isEmpty) throw const FormatException('no geometry');
    return [
      for (final p in points) WaypointObject(location: p, userMetadata: metadata),
      if (lines.isNotEmpty)
        TrackObject(userMetadata: metadata, segments: [for (final l in lines) TrackSegment(locations: l)]),
      if (polygons.isNotEmpty) AreaObject(userMetadata: metadata, polygons: polygons),
    ];
  }

  AreaPolygon _polygon(XmlElement polygon, ImportOptions options) {
    List<LandmarkLocation> ring(XmlElement boundary) {
      final linear = XmlUtils.child(boundary, 'LinearRing');
      return linear == null ? const [] : FormatSupport.openRing(_coordinates(linear, options));
    }

    final outer = XmlUtils.child(polygon, 'outerBoundaryIs');
    if (outer == null) throw const FormatException('Polygon without outerBoundaryIs');
    return AreaPolygon(
      outline: ring(outer),
      holes: [for (final inner in XmlUtils.children(polygon, 'innerBoundaryIs')) ring(inner)],
    );
  }

  /// `lon,lat[,alt]` через пробелы.
  static List<LandmarkLocation> _coordinates(XmlElement geometry, ImportOptions options) {
    final text = XmlUtils.childText(geometry, 'coordinates');
    if (text == null) throw FormatException('<${geometry.localName}> without coordinates');
    return [
      for (final tuple in text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty))
        () {
          final parts = tuple.split(',');
          final lon = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
          final lat = parts.length > 1 ? double.tryParse(parts[1]) : null;
          if (lon == null || lat == null) throw FormatException('Invalid coordinates "$tuple"');
          return FormatSupport.location(
            lat,
            lon,
            elevation: parts.length > 2 ? double.tryParse(parts[2]) : null,
            options: options,
          );
        }(),
    ];
  }

  /// Стили документа по id (`Style` и `StyleMap` → его `normal`).
  static Map<String, _Style> _styles(XmlDocument doc) {
    final styles = <String, _Style>{
      for (final s in XmlUtils.descendants(doc, 'Style'))
        if (s.getAttribute('id') case final id?) id: _Style.of(s),
    };
    for (final map in XmlUtils.descendants(doc, 'StyleMap')) {
      final id = map.getAttribute('id');
      if (id == null) continue;
      for (final pair in XmlUtils.children(map, 'Pair')) {
        if (XmlUtils.childText(pair, 'key') != 'normal') continue;
        final url = XmlUtils.childText(pair, 'styleUrl')?.replaceFirst('#', '');
        final inline = XmlUtils.child(pair, 'Style');
        final style = inline != null ? _Style.of(inline) : styles[url];
        if (style != null) styles[id] = style;
      }
    }
    return styles;
  }

  static _Style? _styleOf(XmlElement placemark, Map<String, _Style> styles) {
    final inline = XmlUtils.child(placemark, 'Style');
    if (inline != null) return _Style.of(inline);
    final url = XmlUtils.childText(placemark, 'styleUrl');
    return url == null ? null : styles[url.replaceFirst('#', '')];
  }

  /// KML-цвет `aabbggrr` → ARGB.
  static int? kmlColorToArgb(String? text) {
    final hex = text?.trim();
    if (hex == null || !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) return null;
    final a = hex.substring(0, 2);
    final b = hex.substring(2, 4);
    final g = hex.substring(4, 6);
    final r = hex.substring(6, 8);
    return int.parse('$a$r$g$b', radix: 16);
  }
}

class _Style {
  const _Style(this.color, this.icon);

  /// Цвет линии, иначе цвет значка; ссылка значка.
  factory _Style.of(XmlElement style) {
    final line = XmlUtils.child(style, 'LineStyle');
    final icon = XmlUtils.child(style, 'IconStyle');
    final color = KmlParser.kmlColorToArgb(line == null ? null : XmlUtils.childText(line, 'color')) ??
        KmlParser.kmlColorToArgb(icon == null ? null : XmlUtils.childText(icon, 'color'));
    final iconElement = icon == null ? null : XmlUtils.child(icon, 'Icon');
    return _Style(color, iconElement == null ? null : XmlUtils.childText(iconElement, 'href'));
  }

  final int? color;
  final String? icon;
}

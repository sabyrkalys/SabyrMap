import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'aqx_descriptor.dart';
import 'projection_spec.dart';
import 'url_template.dart';
import 'zoom_range.dart';

/// Разбор описания онлайн-карты (AQX, XML).
///
/// Decision — ожидаемая структура (точной схемы в задании нет):
/// ```xml
/// <aqx version="1">
///   <name>Topo</name>
///   <description>…</description>
///   <source id="topo">            <!-- id; без него — из имени файла/карты -->
///     <zoom-levels>1-17</zoom-levels>          <!-- или min="1" max="17" -->
///     <server>https://a.example/{$z}/{$x}/{$y}.png</server>
///     <server url="https://b.example/…">
///       <header name="User-Agent">sabyrmap</header>
///     </server>
///     <update-delay>30d</update-delay>         <!-- секунды или s/m/h/d -->
///     <max-threads>2</max-threads>             <!-- 1..3 -->
///     <projection-code>EPSG:3857</projection-code>
///     <clear-color min="250,250,250" max="255,255,255"/>
///     <variable name="layer" default="topo"/>
///     <param name="key">value</param>
///     <insecure>true</insecure>
///   </source>
/// </aqx>
/// ```
/// Элементы источника можно писать и прямо в `<aqx>`. Неизвестные
/// элементы пропускаются. Нет имени или сервера — [FormatException].
class AqxParser {
  const AqxParser();

  Future<AqxDescriptor> parseFile(String path) async {
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (e) {
      throw FormatException('Cannot read ${p.basename(path)}: ${e.message}');
    }
    return parseString(text, fallbackId: p.basenameWithoutExtension(path));
  }

  AqxDescriptor parseString(String xml, {String? fallbackId}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw FormatException('Invalid AQX: ${e.message}');
    }
    final root = doc.rootElement;
    if (root.localName != 'aqx') throw FormatException('Not an AQX file: root is <${root.localName}>');
    final source = _child(root, 'source') ?? root;

    final name = _text(source, 'name') ?? _text(root, 'name');
    if (name == null) throw const FormatException('AQX without <name>');
    final servers = [
      for (final s in _children(source, 'server'))
        if ((s.getAttribute('url') ?? _ownText(s)) case final url? when url.isNotEmpty)
          AqxServer(
            url: url,
            headers: _children(s, 'header').isEmpty
                ? null
                : {for (final h in _children(s, 'header')) h.getAttribute('name') ?? '': h.innerText.trim()},
          ),
    ];
    if (servers.isEmpty) throw const FormatException('AQX without <server>');

    final zoom = _child(source, 'zoom-levels');
    final ZoomRange range;
    if (zoom == null) {
      range = const ZoomRange(0, 18);
    } else if (zoom.getAttribute('min') != null || zoom.getAttribute('max') != null) {
      final min = int.tryParse(zoom.getAttribute('min') ?? '0');
      final max = int.tryParse(zoom.getAttribute('max') ?? '18');
      if (min == null || max == null || min > max) throw const FormatException('Invalid <zoom-levels>');
      range = ZoomRange(min, max);
    } else {
      range = ZoomRange.parse(zoom.innerText);
    }

    final clear = _child(source, 'clear-color');
    final clearMin = _rgb(clear?.getAttribute('min'));
    final clearMax = _rgb(clear?.getAttribute('max'));
    final tileSize = int.tryParse(_text(source, 'tile-size') ?? '');

    return AqxDescriptor(
      id: source.getAttribute('id') ?? fallbackId ?? _slug(name),
      name: name,
      description: _text(source, 'description') ?? _text(root, 'description'),
      urlTemplate: UrlTemplate(servers.first.url),
      zoomRange: range,
      projection: ProjectionSpec(
        code: _text(source, 'projection-code') ?? ProjectionSpec.webMercator,
        bboxCrsCode: _text(source, 'bbox-crs'),
        wktDefinition: _text(source, 'wkt'),
        resolution: double.tryParse(_text(source, 'resolution') ?? ''),
        offsetX: double.tryParse(_text(source, 'offset-x') ?? ''),
        offsetY: double.tryParse(_text(source, 'offset-y') ?? ''),
        tileSize: tileSize,
      ),
      maxThreads: (int.tryParse(_text(source, 'max-threads') ?? '') ?? 1).clamp(1, 3),
      updateDelay: _duration(_text(source, 'update-delay')),
      insecure: (_text(source, 'insecure') ?? source.getAttribute('insecure')) == 'true',
      clearColorMinR: clearMin?[0],
      clearColorMinG: clearMin?[1],
      clearColorMinB: clearMin?[2],
      clearColorMaxR: clearMax?[0],
      clearColorMaxG: clearMax?[1],
      clearColorMaxB: clearMax?[2],
      servers: servers,
      defaultParams: {
        for (final v in _children(source, 'variable'))
          if (v.getAttribute('name') case final n?) n: v.getAttribute('default') ?? v.innerText.trim(),
        for (final pr in _children(source, 'param'))
          if (pr.getAttribute('name') case final n?) n: pr.getAttribute('value') ?? pr.innerText.trim(),
      },
      version: int.tryParse(root.getAttribute('version') ?? '') ?? 1,
    );
  }

  static Iterable<XmlElement> _children(XmlElement e, String name) => e.childElements.where((c) => c.localName == name);
  static XmlElement? _child(XmlElement e, String name) => _children(e, name).firstOrNull;

  static String? _text(XmlElement e, String name) {
    final t = _child(e, name)?.innerText.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// Текст элемента без вложенных элементов.
  static String? _ownText(XmlElement e) {
    final t = e.children.whereType<XmlText>().map((n) => n.value).join().trim();
    return t.isEmpty ? null : t;
  }

  static List<int>? _rgb(String? text) {
    if (text == null) return null;
    final parts = text.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).map(int.tryParse).toList();
    if (parts.length != 3 || parts.any((v) => v == null || v < 0 || v > 255)) {
      throw FormatException('Invalid clear color "$text"');
    }
    return parts.cast<int>();
  }

  /// `3600`, `90s`, `15m`, `12h`, `30d`.
  static Duration? _duration(String? text) {
    if (text == null) return null;
    final m = RegExp(r'^(\d+)\s*([smhd]?)$').firstMatch(text.trim().toLowerCase());
    if (m == null) throw FormatException('Invalid <update-delay> "$text"');
    final v = int.parse(m[1]!);
    return switch (m[2]) {
      'm' => Duration(minutes: v),
      'h' => Duration(hours: v),
      'd' => Duration(days: v),
      _ => Duration(seconds: v),
    };
  }

  static String _slug(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return s.isEmpty ? 'online-map' : s;
  }
}

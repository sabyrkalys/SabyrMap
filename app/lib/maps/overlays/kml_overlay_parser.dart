import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/maps/file_maps/map_bounds.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'kml_overlay_descriptor.dart';

/// Наложения-картинки из KML/KMZ (`GroundOverlay` с `Icon/href` и
/// `LatLonBox`). Из KMZ картинки распаковываются во временную папку —
/// оттуда их забирает [ImageOverlayInstaller].
class KmlOverlayParser {
  KmlOverlayParser({Directory? tempRoot}) : _tempRoot = tempRoot;

  final Directory? _tempRoot;

  /// Неверный файл — [FormatException]. Наложения без картинки на диске
  /// (адрес в сети, нет в архиве) пропускаются.
  Future<List<KmlOverlayDescriptor>> parse(String path) async {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      throw FormatException('Cannot read ${p.basename(path)}: ${e.message}');
    }
    final isZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 3 && bytes[3] == 4;
    if (!isZip) return _parseKml(utf8.decode(bytes, allowMalformed: true), (href) => _local(p.dirname(path), href));

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      throw FormatException('Invalid KMZ: $e');
    }
    final kml = archive.findFile('doc.kml') ??
        archive.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('.kml')).firstOrNull;
    if (kml == null) throw const FormatException('KMZ archive has no .kml file');
    final temp = await (_tempRoot ?? Directory.systemTemp).createTemp('sabyrmap_overlay_');
    return _parseKml(utf8.decode(kml.content, allowMalformed: true), (href) {
      final name = p.posix.normalize(p.posix.join(p.posix.dirname(kml.name), href));
      final entry = archive.findFile(name);
      if (entry == null || !entry.isFile || name.startsWith('..')) return null;
      final out = File(p.join(temp.path, p.basename(name)));
      out.writeAsBytesSync(entry.content);
      return out.path;
    });
  }

  List<KmlOverlayDescriptor> _parseKml(String text, String? Function(String href) resolve) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(text);
    } on XmlException catch (e) {
      throw FormatException('Invalid KML: ${e.message}');
    }
    if (doc.rootElement.localName != 'kml') throw const FormatException('Not a KML document');
    final out = <KmlOverlayDescriptor>[];
    for (final overlay in doc.descendantElements.where((e) => e.localName == 'GroundOverlay')) {
      final href = _text(_child(overlay, 'Icon'), 'href');
      final box = _child(overlay, 'LatLonBox');
      if (href == null || box == null) continue;
      if (href.contains('://')) continue;
      final image = resolve(href);
      if (image == null) continue;
      double edge(String name) {
        final v = double.tryParse(_text(box, name) ?? '');
        if (v == null) throw FormatException('LatLonBox without <$name>');
        return v;
      }

      final bounds = MapBounds(northLat: edge('north'), southLat: edge('south'), westLon: edge('west'), eastLon: edge('east'));
      if (!bounds.isValid) throw FormatException('Invalid LatLonBox $bounds');
      out.add(
        KmlOverlayDescriptor(
          name: _text(overlay, 'name') ?? p.basenameWithoutExtension(image),
          imagePath: image,
          bounds: bounds,
          rotation: double.tryParse(_text(box, 'rotation') ?? '') ?? 0,
          drawOrder: int.tryParse(_text(overlay, 'drawOrder') ?? ''),
        ),
      );
    }
    return out;
  }

  static String? _local(String dir, String href) {
    final path = p.normalize(p.isAbsolute(href) ? href : p.join(dir, href));
    return File(path).existsSync() ? path : null;
  }

  static XmlElement? _child(XmlElement? e, String name) => e?.childElements.where((c) => c.localName == name).firstOrNull;

  static String? _text(XmlElement? e, String name) {
    final t = _child(e, name)?.innerText.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

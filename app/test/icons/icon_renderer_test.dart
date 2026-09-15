import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/icons/icon_library_scanner.dart';
import 'package:app/icons/icon_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('icon_renderer_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('raster input is re-encoded to the canonical square canvas size', () async {
    // A minimal 2x1 red-then-blue PNG, built at runtime via dart:ui so the
    // test has no binary fixture to maintain.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint()..color = const ui.Color(0xFFFF0000));
    canvas.drawRect(const ui.Rect.fromLTWH(1, 0, 1, 1), ui.Paint()..color = const ui.Color(0xFF0000FF));
    final srcImage = await recorder.endRecording().toImage(2, 1);
    final srcPng = (await srcImage.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final file = File('${tempDir.path}/two_by_one.png')..writeAsBytesSync(srcPng);
    final icon = IconFile(path: file.path, fileName: 'two_by_one.png', displayName: 'two_by_one', format: IconFileFormat.raster);

    final bytes = await renderIconBytes(icon, null);
    final image = await _decode(bytes);

    expect(image.width, kIconCanvasSize);
    expect(image.height, kIconCanvasSize);
  });

  test('svg input is tinted to the requested color', () async {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
        '<rect width="10" height="10" fill="#FF0000"/></svg>';
    final file = File('${tempDir.path}/marker.svg')..writeAsStringSync(svg);
    final icon = IconFile(path: file.path, fileName: 'marker.svg', displayName: 'marker', format: IconFileFormat.svg);

    final bytes = await renderIconBytes(icon, '#00FF00');
    final image = await _decode(bytes);
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final centerPixel = (kIconCanvasSize ~/ 2) * kIconCanvasSize + (kIconCanvasSize ~/ 2);
    final r = pixels!.getUint8(centerPixel * 4);
    final g = pixels.getUint8(centerPixel * 4 + 1);
    final b = pixels.getUint8(centerPixel * 4 + 2);
    final a = pixels.getUint8(centerPixel * 4 + 3);

    expect(image.width, kIconCanvasSize);
    expect(a, greaterThan(0));
    expect(g, greaterThan(200));
    expect(r, lessThan(50));
    expect(b, lessThan(50));
  });
}

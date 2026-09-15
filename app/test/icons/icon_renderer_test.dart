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

  test('raster input is aspect-fit and centered, not stretched to fill the canvas', () async {
    // A 20x10 source, left half red / right half blue. Aspect-fit at
    // kIconCanvasSize=48 scales by 48/20=2.4 (longest side = width), giving a
    // 48x24 image letterboxed with 12px of transparent padding above and
    // below. A bug that stretched non-uniformly (separate x/y scale factors)
    // or dropped the centering offset would fail the sampled assertions
    // below, even though width/height alone would still read 48x48.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 10, 10), ui.Paint()..color = const ui.Color(0xFFFF0000));
    canvas.drawRect(const ui.Rect.fromLTWH(10, 0, 10, 10), ui.Paint()..color = const ui.Color(0xFF0000FF));
    final srcImage = await recorder.endRecording().toImage(20, 10);
    final srcPng = (await srcImage.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final file = File('${tempDir.path}/twenty_by_ten.png')..writeAsBytesSync(srcPng);
    final icon =
        IconFile(path: file.path, fileName: 'twenty_by_ten.png', displayName: 'twenty_by_ten', format: IconFileFormat.raster);

    final bytes = await renderIconBytes(icon, null);
    final image = await _decode(bytes);
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    Map<String, int> at(int x, int y) {
      final i = (y * kIconCanvasSize + x) * 4;
      return {
        'r': pixels!.getUint8(i),
        'g': pixels.getUint8(i + 1),
        'b': pixels.getUint8(i + 2),
        'a': pixels.getUint8(i + 3),
      };
    }

    expect(image.width, kIconCanvasSize);
    expect(image.height, kIconCanvasSize);

    // Well inside the fitted red region (source x in [0,10) -> output x in
    // [0,24); source y in [0,10) -> output y in [12,36)).
    final redPixel = at(12, 24);
    expect(redPixel['r'], greaterThan(200));
    expect(redPixel['g'], lessThan(50));
    expect(redPixel['b'], lessThan(50));
    expect(redPixel['a'], greaterThan(0));

    // Well inside the fitted blue region (output x in [24,48)).
    final bluePixel = at(36, 24);
    expect(bluePixel['b'], greaterThan(200));
    expect(bluePixel['r'], lessThan(50));
    expect(bluePixel['g'], lessThan(50));
    expect(bluePixel['a'], greaterThan(0));

    // Top and bottom letterbox padding (output y in [0,12) and [36,48)) must
    // be transparent -- proving the image was fit to 48x24 and centered, not
    // stretched to fill the full 48x48 square.
    expect(at(24, 2)['a'], 0);
    expect(at(24, 45)['a'], 0);
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

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../waypoints/waypoint_color.dart';
import 'icon_library_scanner.dart';

/// Every rendered marker bitmap (raster or SVG) is normalized to this square
/// size before being registered with MapLibre's addImage, so callers never
/// need to compute a per-image iconSize -- see the design spec's "Global
/// Constraints".
const int kIconCanvasSize = 48;

/// Size of a waypoint icon on the map, in logical pixels (dp). The bitmap
/// is rendered at this times the screen's pixel ratio: MapLibre draws the
/// registered image pixel for pixel, so a fixed 48 px bitmap was only
/// ~15 dp (about 2 mm) on a 3.25× screen.
const double kIconLogicalSize = 40;

/// Bitmap side, in physical pixels, for a screen with [devicePixelRatio].
int iconCanvasPixels(double devicePixelRatio) => (kIconLogicalSize * devicePixelRatio).round().clamp(kIconCanvasSize, 512);

/// Renders [icon] to a [size]×[size] PNG. Raster (`png`/`jpg`/`jpeg`) input
/// is aspect-fit and centered, unmodified in color. SVG input is tinted a
/// single flat color (via a `srcIn` blend) equal to [colorHex] (`#000000` if
/// null) -- correct only for monochrome glyph-style SVGs, which is what this
/// feature targets -- and its empty margins are trimmed, so the drawing
/// itself fills the square (map symbols often sit in a large blank canvas).
Future<Uint8List> renderIconBytes(IconFile icon, String? colorHex, {int size = kIconCanvasSize}) {
  if (icon.format == IconFileFormat.raster) return _renderRaster(icon, size);
  return _renderSvg(icon, colorHex, size);
}

Future<Uint8List> _renderRaster(IconFile icon, int size) async {
  final bytes = await File(icon.path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  final longestSide = image.width > image.height ? image.width : image.height;
  final scale = size / longestSide;
  final dx = (size - image.width * scale) / 2;
  final dy = (size - image.height * scale) / 2;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  canvas.translate(dx, dy);
  canvas.scale(scale);
  canvas.drawImage(image, Offset.zero, ui.Paint());
  image.dispose();

  return _encode(recorder, size);
}

Future<Uint8List> _renderSvg(IconFile icon, String? colorHex, int size) async {
  final svgString = await File(icon.path).readAsString();
  final tint = colorFromHex(colorHex ?? '#000000');
  final pictureInfo = await vg.loadPicture(SvgStringLoader(svgString), null);

  // Draw the whole SVG canvas at twice the target size, find the drawn part
  // and fit that part into the target square.
  final work = size * 2;
  final srcW = pictureInfo.size.width > 0 ? pictureInfo.size.width : work.toDouble();
  final srcH = pictureInfo.size.height > 0 ? pictureInfo.size.height : work.toDouble();
  final longestSide = srcW > srcH ? srcW : srcH;
  final scale = work / longestSide;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, work.toDouble(), work.toDouble()));
  canvas.saveLayer(
    Rect.fromLTWH(0, 0, work.toDouble(), work.toDouble()),
    ui.Paint()..colorFilter = ui.ColorFilter.mode(tint, ui.BlendMode.srcIn),
  );
  canvas.translate((work - srcW * scale) / 2, (work - srcH * scale) / 2);
  canvas.scale(scale);
  canvas.drawPicture(pictureInfo.picture);
  canvas.restore();
  pictureInfo.picture.dispose();
  final full = await recorder.endRecording().toImage(work, work);

  final bounds = await _drawnBounds(full) ?? Rect.fromLTWH(0, 0, work.toDouble(), work.toDouble());
  // A thin margin so antialiased edges are not cut.
  final margin = size * 0.03;
  final fit = (size - 2 * margin) / (bounds.width > bounds.height ? bounds.width : bounds.height);
  final dstW = bounds.width * fit;
  final dstH = bounds.height * fit;
  final out = ui.PictureRecorder();
  ui.Canvas(out, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble())).drawImageRect(
    full,
    bounds,
    Rect.fromLTWH((size - dstW) / 2, (size - dstH) / 2, dstW, dstH),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  full.dispose();
  return _encode(out, size);
}

/// The box around pixels that are not (almost) transparent; null — none.
Future<Rect?> _drawnBounds(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;
  final w = image.width;
  final h = image.height;
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (data.getUint8((y * w + x) * 4 + 3) > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  return Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
}

Future<Uint8List> _encode(ui.PictureRecorder recorder, int size) async {
  final output = await recorder.endRecording().toImage(size, size);
  final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
  output.dispose();
  return byteData!.buffer.asUint8List();
}

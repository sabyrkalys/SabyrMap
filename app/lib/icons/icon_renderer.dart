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

/// Renders [icon] to a `kIconCanvasSize x kIconCanvasSize` PNG. Raster
/// (`png`/`jpg`/`jpeg`) input is aspect-fit and centered, unmodified in
/// color. SVG input is aspect-fit, centered, and tinted a single flat color
/// (via a `srcIn` blend) equal to [colorHex] (`#000000` if null) -- correct
/// only for monochrome glyph-style SVGs, which is what this feature targets.
Future<Uint8List> renderIconBytes(IconFile icon, String? colorHex) {
  if (icon.format == IconFileFormat.raster) return _renderRaster(icon);
  return _renderSvg(icon, colorHex);
}

Future<Uint8List> _renderRaster(IconFile icon) async {
  final bytes = await File(icon.path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  final longestSide = image.width > image.height ? image.width : image.height;
  final scale = kIconCanvasSize / longestSide;
  final dx = (kIconCanvasSize - image.width * scale) / 2;
  final dy = (kIconCanvasSize - image.height * scale) / 2;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, kIconCanvasSize.toDouble(), kIconCanvasSize.toDouble()));
  canvas.translate(dx, dy);
  canvas.scale(scale);
  canvas.drawImage(image, Offset.zero, ui.Paint());
  image.dispose();

  final output = await recorder.endRecording().toImage(kIconCanvasSize, kIconCanvasSize);
  final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
  output.dispose();
  return byteData!.buffer.asUint8List();
}

Future<Uint8List> _renderSvg(IconFile icon, String? colorHex) async {
  final svgString = await File(icon.path).readAsString();
  final tint = colorFromHex(colorHex ?? '#000000');
  final pictureInfo = await vg.loadPicture(SvgStringLoader(svgString), null);

  final srcW = pictureInfo.size.width > 0 ? pictureInfo.size.width : kIconCanvasSize.toDouble();
  final srcH = pictureInfo.size.height > 0 ? pictureInfo.size.height : kIconCanvasSize.toDouble();
  final longestSide = srcW > srcH ? srcW : srcH;
  final scale = kIconCanvasSize / longestSide;
  final dx = (kIconCanvasSize - srcW * scale) / 2;
  final dy = (kIconCanvasSize - srcH * scale) / 2;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, kIconCanvasSize.toDouble(), kIconCanvasSize.toDouble()));
  canvas.saveLayer(
    Rect.fromLTWH(0, 0, kIconCanvasSize.toDouble(), kIconCanvasSize.toDouble()),
    ui.Paint()..colorFilter = ui.ColorFilter.mode(tint, ui.BlendMode.srcIn),
  );
  canvas.translate(dx, dy);
  canvas.scale(scale);
  canvas.drawPicture(pictureInfo.picture);
  canvas.restore();
  pictureInfo.picture.dispose();

  final output = await recorder.endRecording().toImage(kIconCanvasSize, kIconCanvasSize);
  final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
  output.dispose();
  return byteData!.buffer.asUint8List();
}

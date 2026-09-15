import 'dart:typed_data';

import 'icon_library_scanner.dart';
import 'icon_renderer.dart';

typedef AddImageFn = Future<void> Function(String name, Uint8List bytes);
typedef RenderIconFn = Future<Uint8List> Function(IconFile icon, String? colorHex);

/// Pure naming rule for a registered MapLibre image: raster icons ignore
/// color (never tinted), SVG icons are keyed by color too since a re-tint
/// needs a distinct registered image.
String symbolImageName(IconFile icon, String? colorHex) {
  if (icon.format == IconFileFormat.raster) return 'icon_raster_${icon.fileName}';
  return 'icon_svg_${icon.fileName}_${colorHex ?? ''}';
}

/// Registers each distinct (icon file, color) pair with the map's style at
/// most once. Takes a plain [AddImageFn] callback instead of a
/// MapLibreMapController so this class is unit-testable without a real
/// platform view.
class IconImageCache {
  IconImageCache({required AddImageFn addImage, RenderIconFn render = renderIconBytes})
      : _addImage = addImage,
        _render = render;

  final AddImageFn _addImage;
  final RenderIconFn _render;
  final Set<String> _registered = {};

  Future<String> resolve(IconFile icon, String? colorHex) async {
    final name = symbolImageName(icon, colorHex);
    if (_registered.contains(name)) return name;
    final effectiveColor = icon.format == IconFileFormat.svg ? colorHex : null;
    final bytes = await _render(icon, effectiveColor);
    await _addImage(name, bytes);
    _registered.add(name);
    return name;
  }

  /// Call on every style reload -- MapLibre's registered images don't
  /// survive it, so this cache's bookkeeping must be dropped too.
  void clear() => _registered.clear();
}

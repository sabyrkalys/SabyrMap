import 'dart:typed_data';

import 'package:app/icons/icon_image_cache.dart';
import 'package:app/icons/icon_library_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rasterIcon = IconFile(path: '/x/camp.png', fileName: 'camp.png', displayName: 'camp', format: IconFileFormat.raster);
  final svgIcon = IconFile(path: '/x/marker.svg', fileName: 'marker.svg', displayName: 'marker', format: IconFileFormat.svg);

  group('symbolImageName', () {
    test('raster name ignores color', () {
      expect(symbolImageName(rasterIcon, '#FF0000'), 'icon_raster_camp.png');
      expect(symbolImageName(rasterIcon, null), 'icon_raster_camp.png');
    });

    test('svg name includes the color', () {
      expect(symbolImageName(svgIcon, '#FF0000'), 'icon_svg_marker.svg_#FF0000');
      expect(symbolImageName(svgIcon, '#00FF00'), 'icon_svg_marker.svg_#00FF00');
    });
  });

  group('IconImageCache', () {
    test('renders and registers on first resolve', () async {
      final addImageCalls = <(String, Uint8List)>[];
      var renderCalls = 0;
      final cache = IconImageCache(
        addImage: (name, bytes) async => addImageCalls.add((name, bytes)),
        render: (icon, colorHex) async {
          renderCalls++;
          return Uint8List.fromList([1, 2, 3]);
        },
      );

      final name = await cache.resolve(svgIcon, '#FF0000');

      expect(name, 'icon_svg_marker.svg_#FF0000');
      expect(renderCalls, 1);
      expect(addImageCalls, hasLength(1));
      expect(addImageCalls.single.$1, name);
    });

    test('a second resolve for the same (icon, color) pair is a cache hit', () async {
      var renderCalls = 0;
      final cache = IconImageCache(
        addImage: (_, __) async {},
        render: (icon, colorHex) async {
          renderCalls++;
          return Uint8List.fromList([1]);
        },
      );

      await cache.resolve(svgIcon, '#FF0000');
      await cache.resolve(svgIcon, '#FF0000');

      expect(renderCalls, 1);
    });

    test('a different color for the same svg is a cache miss', () async {
      var renderCalls = 0;
      final cache = IconImageCache(addImage: (_, __) async {}, render: (icon, colorHex) async {
        renderCalls++;
        return Uint8List.fromList([1]);
      });

      await cache.resolve(svgIcon, '#FF0000');
      await cache.resolve(svgIcon, '#00FF00');

      expect(renderCalls, 2);
    });

    test('clear() forgets registrations, forcing a re-render on next resolve', () async {
      var renderCalls = 0;
      final cache = IconImageCache(addImage: (_, __) async {}, render: (icon, colorHex) async {
        renderCalls++;
        return Uint8List.fromList([1]);
      });
      await cache.resolve(svgIcon, '#FF0000');

      cache.clear();
      await cache.resolve(svgIcon, '#FF0000');

      expect(renderCalls, 2);
    });
  });
}

import 'package:app/maps/color/color_range.dart';
import 'package:app/maps/color/layer_color_controller.dart';
import 'package:app/maps/color/layer_color_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contains on and past the edges', () {
    const r = ColorRange(channel: 0, center: 100);
    expect(r.width, 5);
    expect(r.contains(100), isTrue);
    expect(r.contains(95), isTrue);
    expect(r.contains(105), isTrue);
    expect(r.contains(94), isFalse);
    expect(r.contains(106), isFalse);
  });

  test('channelOf reads R, G, B', () {
    expect(const ColorRange(channel: 0, center: 0).channelOf(0xFF102030), 0x10);
    expect(const ColorRange(channel: 1, center: 0).channelOf(0xFF102030), 0x20);
    expect(const ColorRange(channel: 2, center: 0).channelOf(0xFF102030), 0x30);
  });

  test('layer colour: identity keeps the pixel', () {
    expect(LayerColorController.applyToPixel(0x80123456, LayerColorSettings.identity()), 0x80123456);
  });

  test('layer colour: contrast, brightness, saturation, tint, inversion, clipping', () {
    expect(LayerColorController.applyToPixel(0xFF80C040, const LayerColorSettings(contrast: 2)), 0xFF80FF00);
    expect(LayerColorController.applyToPixel(0xFF000000, const LayerColorSettings(brightness: 0.5)), 0xFF808080);
    final gray = LayerColorController.applyToPixel(0xFFFF0000, const LayerColorSettings(saturation: 0));
    expect((gray >> 16) & 0xFF, (gray >> 8) & 0xFF);
    expect(LayerColorController.applyToPixel(0xFFFFFFFF, const LayerColorSettings(tint: 0xFFFF0000)), 0xFFFF0000);
    expect(LayerColorController.applyToPixel(0xFF102030, const LayerColorSettings(inverted: true)), 0xFFEFDFCF);
  });
}

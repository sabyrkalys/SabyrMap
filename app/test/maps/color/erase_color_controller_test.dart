import 'package:app/maps/color/color_range.dart';
import 'package:app/maps/color/erase_color_controller.dart';
import 'package:app/maps/color/erase_color_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final white = EraseColorSettings.fromColor(0xFFF0F0F0);

  test('disabled never erases', () {
    expect(EraseColorController.shouldErase(0xFFF0F0F0, white.copyWith(enabled: false)), isFalse);
    expect(EraseColorController.shouldErase(0xFFF0F0F0, const EraseColorSettings(enabled: true)), isFalse);
  });

  test('exactly the colour is erased', () {
    expect(EraseColorController.shouldErase(0xFFF0F0F0, white), isTrue);
    expect(white.screenCenterHex, '#F0F0F0');
  });

  test('exactly on the ±width edge is erased', () {
    expect(EraseColorController.shouldErase(0xFFF5EBF5, white), isTrue);
  });

  test('outside the range on any channel is kept', () {
    expect(EraseColorController.shouldErase(0xFFF6F0F0, white), isFalse);
    expect(EraseColorController.shouldErase(0xFFF0F0EA, white), isFalse);
  });

  test('withErasedAlpha clears only the alpha of erased pixels', () {
    expect(EraseColorController.withErasedAlpha(0xFFF1F0EF, white), 0x00F1F0EF);
    expect(EraseColorController.withErasedAlpha(0xFF000000, white), 0xFF000000);
  });

  test('custom width and JSON round-trip', () {
    final wide = EraseColorSettings.fromColor(0xFF808080, width: 20);
    expect(EraseColorController.shouldErase(0xFF949494, wide), isTrue);
    expect(EraseColorSettings.fromJson(wide.toJson()), wide);
    expect(wide.ranges.first, const ColorRange(channel: 0, center: 0x80, width: 20));
  });
}

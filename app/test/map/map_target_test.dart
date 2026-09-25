import 'package:app/map/map_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('starts with no target', () {
    expect(container().read(mapTargetProvider), isA<MapTargetNone>());
  });

  test('setAt sets the target start; clear removes it', () {
    final c = container();
    c.read(mapTargetProvider.notifier).setAt(const LatLng(1, 2));
    expect(c.read(mapTargetProvider).point, const LatLng(1, 2));

    c.read(mapTargetProvider.notifier).setAt(const LatLng(3, 4));
    expect(c.read(mapTargetProvider).point, const LatLng(3, 4));

    c.read(mapTargetProvider.notifier).clear();
    expect(c.read(mapTargetProvider), isA<MapTargetNone>());
  });

  test('the crosshair card opens, closes and toggles; a target survives it', () {
    final c = container();
    c.read(mapTargetProvider.notifier).setAt(const LatLng(1, 2));
    c.read(crosshairMenuOpenProvider.notifier).open();
    expect(c.read(crosshairMenuOpenProvider), isTrue);
    c.read(crosshairMenuOpenProvider.notifier).toggle();
    expect(c.read(crosshairMenuOpenProvider), isFalse);
    c.read(crosshairMenuOpenProvider.notifier).toggle();
    c.read(crosshairMenuOpenProvider.notifier).close();
    expect(c.read(crosshairMenuOpenProvider), isFalse);
    expect(c.read(mapTargetProvider).point, const LatLng(1, 2));
  });

  test('formatDistance', () {
    expect(formatDistance(0), '0.0 м');
    expect(formatDistance(349.6), '349.6 м');
    expect(formatDistance(1.26), '1.3 м');
    expect(formatDistance(999.4), '999.4 м');
    expect(formatDistance(999.96), '1.0 км');
    expect(formatDistance(1000), '1.0 км');
    expect(formatDistance(1234), '1.2 км');
  });
}

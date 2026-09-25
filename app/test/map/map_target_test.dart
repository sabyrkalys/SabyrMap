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

  test('pick only sets a target while picking', () {
    final c = container();
    c.read(mapTargetProvider.notifier).pick(const LatLng(1, 2));
    expect(c.read(mapTargetProvider), isA<MapTargetNone>());

    c.read(mapTargetProvider.notifier).startPicking();
    expect(c.read(mapTargetProvider), isA<MapTargetPicking>());
    c.read(mapTargetProvider.notifier).pick(const LatLng(1, 2));
    expect(c.read(mapTargetProvider).point, const LatLng(1, 2));

    c.read(mapTargetProvider.notifier).pick(const LatLng(3, 4));
    expect(c.read(mapTargetProvider).point, const LatLng(1, 2), reason: 'not picking any more');
  });

  test('clear removes the target', () {
    final c = container();
    c.read(mapTargetProvider.notifier)
      ..startPicking()
      ..pick(const LatLng(1, 2))
      ..clear();
    expect(c.read(mapTargetProvider), isA<MapTargetNone>());
  });

  test('opening the menu cancels picking but keeps a set target', () {
    final c = container();
    c.read(mapTargetProvider.notifier).startPicking();
    c.read(crosshairMenuOpenProvider.notifier).open();
    expect(c.read(mapTargetProvider), isA<MapTargetNone>());
    c.read(crosshairMenuOpenProvider.notifier).close();

    c.read(mapTargetProvider.notifier)
      ..startPicking()
      ..pick(const LatLng(1, 2));
    c.read(crosshairMenuOpenProvider.notifier).toggle();
    expect(c.read(crosshairMenuOpenProvider), isTrue);
    expect(c.read(mapTargetProvider).point, const LatLng(1, 2));

    c.read(crosshairMenuOpenProvider.notifier).toggle();
    expect(c.read(crosshairMenuOpenProvider), isFalse);
    c.read(crosshairMenuOpenProvider.notifier).open();
    c.read(crosshairMenuOpenProvider.notifier).close();
    expect(c.read(crosshairMenuOpenProvider), isFalse);
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

import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/on_screen/on_screen_registry.dart';
import 'package:app/landmarks/on_screen/on_screen_sort.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LandmarkItem item(
  String name, {
  LandmarkType type = LandmarkType.waypoint,
  double? lat,
  double? lon,
  int created = 0,
  double? alt,
  String? icon,
}) => LandmarkItem(
  path: '/m/$name.${type.extension}',
  name: name,
  type: type,
  colorValue: 0xFFEE1111,
  createdAt: created,
  updatedAt: created,
  fileSizeBytes: 0,
  fileModifiedAt: DateTime(2026),
  latitude: lat,
  longitude: lon,
  maxElevationMeters: alt,
  iconId: icon,
);

void main() {
  test('everything is on screen until hidden or removed', () {
    final r = OnScreenRegistry();
    expect(r.isVisible('/a'), isTrue);
    expect(r.toggle('/a'), isFalse);
    expect((r.isOnScreen('/a'), r.isVisible('/a')), (true, false));
    r.removeAll(['/a', '/b']);
    expect((r.isOnScreen('/a'), r.isOnScreen('/b')), (false, false));
    r.show('/a');
    expect((r.isVisible('/a'), r.isOnScreen('/b')), (true, false));
    r.moved('/b', '/c');
    expect((r.isOnScreen('/b'), r.isOnScreen('/c')), (true, false));
  });

  test('state survives a restart through settings', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    OnScreenRegistry(settings)
      ..hide('/h')
      ..removeAll(['/r']);
    final restored = OnScreenRegistry(settings)..restore();
    expect((restored.isOnScreen('/h'), restored.isVisible('/h'), restored.isOnScreen('/r')), (true, false, false));
  });

  test('sorts by type, distance, altitude and icon; missing values last', () {
    final a = item('a', lat: 48.0, lon: 37.0, created: 3, alt: 200, icon: 'b');
    final b = item('b', type: LandmarkType.area, created: 1);
    final c = item('c', lat: 48.5, lon: 37.0, created: 2, alt: 100, icon: 'a');
    const center = (latitude: 48.6, longitude: 37.0);
    List<String> names(OnScreenSort s) => [
      for (final i in s.apply([a, b, c], center: center)) i.name,
    ];
    expect(names(const OnScreenSort(field: OnScreenSortField.type, ascending: false)), ['b', 'a', 'c']);
    expect(names(const OnScreenSort(field: OnScreenSortField.distance)), ['c', 'a', 'b']);
    expect(names(const OnScreenSort(field: OnScreenSortField.distance, ascending: false)), ['a', 'c', 'b']);
    expect(names(const OnScreenSort(field: OnScreenSortField.date)), ['b', 'c', 'a']);
    expect(names(const OnScreenSort(field: OnScreenSortField.altitude)), ['c', 'a', 'b']);
    expect(names(const OnScreenSort(field: OnScreenSortField.icon)), ['c', 'a', 'b']);
    expect(
      OnScreenSort.decode(const OnScreenSort(field: OnScreenSortField.icon, ascending: false).encode()),
      const OnScreenSort(field: OnScreenSortField.icon, ascending: false),
    );
    expect(OnScreenSort.bearingFrom(center, c)!.round(), 180);
  });
}

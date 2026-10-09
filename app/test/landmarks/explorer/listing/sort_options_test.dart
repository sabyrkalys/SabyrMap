import 'package:app/landmarks/explorer/listing/sort_options.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../explorer_fixture.dart';

void main() {
  List<String> names(List items) => [for (final i in items) i.name as String];

  test('by name: case-insensitive and stable for equal names', () {
    final items = [item('beta'), item('Alpha'), item('alpha'), item('Gamma')];
    final sorted = const SortOptions().apply(items);
    expect(names(sorted), ['Alpha', 'alpha', 'beta', 'Gamma']);
    expect(names(const SortOptions().apply(sorted.reversed.toList())), names(sorted));
    expect(names(const SortOptions(direction: SortDirection.descending).apply(items)), ['Gamma', 'beta', 'Alpha', 'alpha']);
  });

  test('by date ascending and descending', () {
    final items = [item('b', createdAt: 2), item('a', createdAt: 3), item('c', createdAt: 1)];
    expect(names(const SortOptions(field: SortField.date).apply(items)), ['c', 'b', 'a']);
    expect(
      names(const SortOptions(field: SortField.date, direction: SortDirection.descending).apply(items)),
      ['a', 'b', 'c'],
    );
  });

  test('by distance needs a centre; without it the order is kept', () {
    final items = [
      item('far', type: LandmarkType.waypoint, lat: 51, lon: 31),
      item('track'),
      item('near', type: LandmarkType.waypoint, lat: 50.01, lon: 30.01),
    ];
    const byDistance = SortOptions(field: SortField.distanceFromScreenCenter);
    expect(names(byDistance.apply(items)), ['far', 'track', 'near']);
    expect(names(byDistance.apply(items, center: (latitude: 50, longitude: 30))), ['near', 'far', 'track']);
  });

  test('items without the value go last in both directions', () {
    final items = [item('none'), item('long', length: 10), item('short', length: 1)];
    expect(names(const SortOptions(field: SortField.length).apply(items)), ['short', 'long', 'none']);
    expect(
      names(const SortOptions(field: SortField.length, direction: SortDirection.descending).apply(items)),
      ['long', 'short', 'none'],
    );
  });

  test('every field sorts without errors', () {
    final items = [item('a', duration: 2, gain: 5, area: 1), item('b', duration: 1, gain: 1, area: 9)];
    expect(names(const SortOptions(field: SortField.duration).apply(items)), ['b', 'a']);
    expect(names(const SortOptions(field: SortField.elevationGain).apply(items)), ['b', 'a']);
    expect(names(const SortOptions(field: SortField.area).apply(items)), ['a', 'b']);
  });

  test('an empty list is fine', () {
    for (final field in SortField.values) {
      expect(SortOptions(field: field).apply(const []), isEmpty);
    }
  });

  test('copyWith, encode and decode', () {
    const s = SortOptions(field: SortField.area, direction: SortDirection.descending);
    expect(s.copyWith(field: SortField.name), const SortOptions(field: SortField.name, direction: SortDirection.descending));
    expect(SortOptions.decode(s.encode()), s);
    expect(SortOptions.decode('nope'), isNull);
    expect(SortOptions.decode(null), isNull);
  });

  test('haversine distance is about right', () {
    expect(SortOptions.distanceMeters(50, 30, 51, 30), closeTo(111195, 10));
  });
}

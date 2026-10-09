import 'package:app/landmarks/explorer/display/display_state.dart';
import 'package:app/landmarks/explorer/listing/filter_options.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../explorer_fixture.dart';

void main() {
  final items = [
    item('a', year: 2024, activity: 'hike'),
    item('b', year: 2025, activity: 'bike'),
    item('c', year: 2025, activity: 'hike'),
    item('d', createdAt: DateTime(2023, 6, 1).millisecondsSinceEpoch),
    item('w', type: LandmarkType.waypoint, year: 2025),
  ];
  List<String> pass(ItemFilter filter, {DisplayState display = const DisplayState()}) => [
    for (final i in FilterOptions(filter: filter).apply(items, display: display)) i.name,
  ];

  test('an empty filter passes everything', () {
    expect(const ItemFilter().isEmpty, isTrue);
    expect(pass(const ItemFilter()), ['a', 'b', 'c', 'd', 'w']);
  });

  test('by years, falling back to the creation year', () {
    expect(pass(const ItemFilter(years: {2025})), ['b', 'c', 'w']);
    expect(pass(const ItemFilter(years: {2023, 2024})), ['a', 'd']);
  });

  test('by activities', () {
    expect(pass(const ItemFilter(activities: {'hike'})), ['a', 'c']);
  });

  test('year and activity together are AND', () {
    expect(pass(const ItemFilter(years: {2025}, activities: {'hike'})), ['c']);
  });

  test('by type and by display', () {
    expect(pass(const ItemFilter(onlyType: LandmarkType.waypoint)), ['w']);
    expect(pass(const ItemFilter(onlyDisplayed: true), display: DisplayState(displayedPaths: {items[1].path})), ['b']);
    expect(pass(const ItemFilter(onlyDisplayed: true)), isEmpty);
  });

  test('copyWith, encode and decode', () {
    const filter = ItemFilter(years: {2025}, activities: {'hike'}, onlyDisplayed: true, onlyType: LandmarkType.track);
    expect(ItemFilter.decode(filter.encode()), filter);
    expect(filter.copyWith(onlyType: null).onlyType, isNull);
    expect(filter.copyWith(years: {}).years, isEmpty);
    expect(filter.copyWith().onlyType, LandmarkType.track);
    expect(ItemFilter.decode('{broken'), isNull);
  });
}

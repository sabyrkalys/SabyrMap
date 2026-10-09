import 'package:app/landmarks/explorer/statistics/list_statistics.dart';
import 'package:app/landmarks/explorer/statistics/statistics_calculator.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../explorer_fixture.dart';

void main() {
  const calc = StatisticsCalculator();

  test('an empty list gives zeros', () {
    expect(calc.calculate(const []), const ListStatistics());
  });

  test('waypoints only: count, zero totals', () {
    final stats = calc.calculate([item('a', type: LandmarkType.waypoint), item('b', type: LandmarkType.waypoint)]);
    expect(stats.itemCount, 2);
    expect(stats.totalLengthMeters, 0);
    expect(stats.totalDurationMs, 0);
    expect(stats.lengthByYear, isEmpty);
  });

  test('mixed list sums what is there', () {
    final stats = calc.calculate([
      item('t1', length: 1000, duration: 60000, gain: 50, year: 2024),
      item('t2', length: 500.5, gain: 10, year: 2025),
      item('area', type: LandmarkType.area, area: 2500),
      item('w', type: LandmarkType.waypoint),
    ]);
    expect(stats.itemCount, 4);
    expect(stats.totalLengthMeters, 1500.5);
    expect(stats.totalDurationMs, 60000);
    expect(stats.totalElevationGainMeters, 60);
    expect(stats.totalAreaSquareMeters, 2500);
  });

  test('by year: the year field, else the creation year', () {
    final created2023 = DateTime(2023, 7, 1).millisecondsSinceEpoch;
    final items = [
      item('a', length: 100, duration: 10, year: 2024),
      item('b', length: 50, duration: 5, year: 2024),
      item('c', length: 7, createdAt: created2023),
      item('d', duration: 3, createdAt: created2023),
    ];
    expect(calc.lengthByYear(items), {2024: 150, 2023: 7});
    expect(calc.durationByYear(items), {2024: 15, 2023: 3});
  });

  test('by activity, missing activity is unknown', () {
    final items = [
      item('a', length: 100, activity: 'hike'),
      item('b', length: 20, activity: 'hike'),
      item('c', length: 5),
      item('d', activity: 'bike'),
    ];
    expect(calc.lengthByActivity(items), {'hike': 120, StatisticsCalculator.unknownActivity: 5});
  });
}

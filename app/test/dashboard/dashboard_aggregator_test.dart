import 'package:app/dashboard/activity_breakdown.dart';
import 'package:app/dashboard/dashboard_aggregator.dart';
import 'package:app/dashboard/dashboard_snapshot.dart';
import 'package:app/dashboard/year_breakdown.dart';
import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../landmarks/services/fixture.dart';

LandmarkItem item(
  String name, {
  LandmarkType type = LandmarkType.track,
  int createdAt = 0,
  double? length,
  int? duration,
  double? gain,
  double? loss,
  double? area,
  String? activity,
  int? year,
}) => LandmarkItem(
  path: '/x/$name',
  name: name,
  type: type,
  colorValue: 0,
  createdAt: createdAt,
  updatedAt: createdAt,
  fileSizeBytes: 1,
  fileModifiedAt: DateTime(2026),
  lengthMeters: length,
  durationMs: duration,
  elevationGainMeters: gain,
  elevationLossMeters: loss,
  areaSquareMeters: area,
  activity: activity,
  year: year,
);

void main() {
  const agg = DashboardAggregator();

  test('an empty list gives zeros', () {
    expect(agg.aggregate(const []), const DashboardSnapshot());
    expect(agg.byYear(const []), isEmpty);
    expect(agg.byActivity(const []), isEmpty);
  });

  test('a mixed list sums what is there', () {
    final items = [
      item('a', length: 1000, duration: 60000, gain: 50, loss: 20, activity: 'hike', year: 2024),
      item('b', length: 500, gain: 10, activity: 'bike', year: 2025),
      item('c', type: LandmarkType.area, area: 2500, year: 2025),
      item('w', type: LandmarkType.waypoint, createdAt: DateTime(2023, 6).millisecondsSinceEpoch),
    ];
    expect(
      agg.aggregate(items),
      const DashboardSnapshot(
        totalItems: 4,
        totalLengthMeters: 1500,
        totalDurationMs: 60000,
        totalGainMeters: 60,
        totalLossMeters: 20,
        totalAreaSquareMeters: 2500,
        yearCount: 3,
        activityCount: 3,
      ),
    );
  });

  test('byYear and byActivity group', () {
    final items = [
      item('a', length: 100, duration: 10, year: 2025, activity: 'hike'),
      item('b', length: 50, duration: 5, year: 2025, activity: 'hike'),
      item('c', length: 400, createdAt: DateTime(2024, 7).millisecondsSinceEpoch),
      item('d', year: 2025, activity: 'bike'),
    ];
    expect(agg.byYear(items), const [
      YearBreakdown(year: 2024, lengthMeters: 400, itemCount: 1),
      YearBreakdown(year: 2025, lengthMeters: 150, durationMs: 15, itemCount: 3),
    ]);
    expect(agg.byActivity(items), const [
      ActivityBreakdown(activity: 'unknown', lengthMeters: 400, itemCount: 1),
      ActivityBreakdown(activity: 'hike', lengthMeters: 150, itemCount: 2),
      ActivityBreakdown(activity: 'bike', lengthMeters: 0, itemCount: 1),
    ]);
  });

  test('the controller reads files and aggregates', () async {
    final f = await ServicesFixture.create();
    addTearDown(f.dispose);
    final a = await f.services.compositeCreation.createTrack(
      const TrackDraft(
        activity: 'hike',
        initialLocations: [
          LandmarkLocation(latitude: 0, longitude: 0),
          LandmarkLocation(latitude: 0, longitude: 0.01),
        ],
      ),
      const LandmarkLocation(latitude: 0, longitude: 0),
    );
    final dashboard = f.services.dashboardController;
    await dashboard.refresh([a, '${f.root.path}/missing.trk']);
    expect(dashboard.isLoading, isFalse);
    expect(dashboard.snapshot!.totalItems, 1);
    expect(dashboard.snapshot!.totalLengthMeters, closeTo(1112, 2));
    expect(dashboard.activities.single.activity, 'hike');
    dashboard.clear();
    expect(dashboard.snapshot, isNull);
  });
}

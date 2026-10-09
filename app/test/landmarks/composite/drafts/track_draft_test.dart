import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final draft = TrackDraft(
    name: 'N',
    comment: 'c',
    description: 'd',
    colorValue: 0xFF112233,
    iconId: 'flag',
    targetFolder: '/f',
    initialLocations: [loc(1, 2)],
    initialWaypoints: [wp(1, 2, 'A')],
    activity: 'hike',
  );

  test('defaults', () {
    const empty = TrackDraft();
    expect(empty.autoSplitByTime, isFalse);
    expect(empty.splitGapSeconds, TrackDraft.defaultSplitGapSeconds);
    expect(empty.initialLocations, isEmpty);
  });

  test('copyWith replaces the given fields', () {
    final changed = draft.copyWith(activity: 'bike', autoSplitByTime: true, splitGapSeconds: 60);
    expect(changed.activity, 'bike');
    expect(changed.autoSplitByTime, isTrue);
    expect(changed.splitGapSeconds, 60);
    expect(changed.name, 'N');
    expect(changed.initialWaypoints, draft.initialWaypoints);
    expect(changed.initialLocations, draft.initialLocations);
  });

  test('toMarkerDraft keeps every common field', () {
    final m = draft.toMarkerDraft(loc(50, 30));
    expect(m.type, LandmarkType.track);
    expect((m.latitude, m.longitude), (50, 30));
    expect((m.name, m.comment, m.description), ('N', 'c', 'd'));
    expect((m.colorValue, m.iconId, m.targetFolder), (0xFF112233, 'flag', '/f'));
  });
}

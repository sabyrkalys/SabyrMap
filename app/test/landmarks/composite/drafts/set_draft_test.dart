import 'package:app/landmarks/composite/drafts/set_draft.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final draft = SetDraft(
    name: 'N',
    comment: 'c',
    description: 'd',
    colorValue: 0xFF112233,
    iconId: 'flag',
    targetFolder: '/f',
    initialWaypoints: [loc(1, 2), loc(3, 4)],
  );

  test('copyWith replaces the given fields', () {
    final changed = draft.copyWith(name: 'M', initialWaypoints: [loc(5, 6)]);
    expect(changed.name, 'M');
    expect(changed.initialWaypoints, [loc(5, 6)]);
    expect(changed.comment, 'c');
    expect(changed.colorValue, 0xFF112233);
    expect(changed.targetFolder, '/f');
  });

  test('toMarkerDraft keeps every common field', () {
    final m = draft.toMarkerDraft(loc(50, 30));
    expect(m.type, LandmarkType.set);
    expect(m.latitude, 50);
    expect(m.longitude, 30);
    expect(m.name, 'N');
    expect(m.comment, 'c');
    expect(m.description, 'd');
    expect(m.colorValue, 0xFF112233);
    expect(m.iconId, 'flag');
    expect(m.targetFolder, '/f');
  });
}

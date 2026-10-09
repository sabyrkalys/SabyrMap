import 'package:app/landmarks/composite/drafts/area_draft.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final draft = AreaDraft(
    name: 'N',
    comment: 'c',
    description: 'd',
    colorValue: 0xFF112233,
    iconId: 'flag',
    targetFolder: '/f',
    initialOutline: [loc(0, 0), loc(0, 1), loc(1, 1)],
  );

  test('closed by default; copyWith replaces the given fields', () {
    expect(draft.isClosed, isTrue);
    final changed = draft.copyWith(isClosed: false, name: 'M');
    expect(changed.isClosed, isFalse);
    expect(changed.name, 'M');
    expect(changed.initialOutline, draft.initialOutline);
    expect(changed.iconId, 'flag');
  });

  test('toMarkerDraft keeps every common field', () {
    final m = draft.toMarkerDraft(loc(50, 30));
    expect(m.type, LandmarkType.area);
    expect((m.latitude, m.longitude), (50, 30));
    expect((m.name, m.comment, m.description), ('N', 'c', 'd'));
    expect((m.colorValue, m.iconId, m.targetFolder), (0xFF112233, 'flag', '/f'));
  });
}

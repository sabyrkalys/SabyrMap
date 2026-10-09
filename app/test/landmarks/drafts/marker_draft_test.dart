import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const draft = MarkerDraft(type: LandmarkType.waypoint, longitude: 30.5, latitude: 50.4);

  test('only type, longitude and latitude are required', () {
    expect(draft.name, isNull);
    expect(draft.comment, isNull);
    expect(draft.description, isNull);
    expect(draft.colorValue, isNull);
    expect(draft.iconId, isNull);
    expect(draft.targetFolder, isNull);
  });

  test('copyWith replaces the given fields and keeps the rest', () {
    final changed = draft.copyWith(name: 'Bunker', colorValue: 0xFFFF0000, latitude: 51, targetFolder: '/x');
    expect(changed.name, 'Bunker');
    expect(changed.colorValue, 0xFFFF0000);
    expect(changed.latitude, 51);
    expect(changed.targetFolder, '/x');
    expect(changed.longitude, 30.5);
    expect(changed.type, LandmarkType.waypoint);
    expect(draft.copyWith(), draft);
    expect(draft.copyWith(type: LandmarkType.route).type, LandmarkType.route);
  });

  test('WaypointPatch.isEmpty and hasLocation', () {
    expect(const WaypointPatch().isEmpty, isTrue);
    expect(const WaypointPatch(comment: '').isEmpty, isFalse);
    expect(const WaypointPatch(latitude: 1).hasLocation, isTrue);
    expect(const WaypointPatch(name: 'a').hasLocation, isFalse);
  });

  test('MetadataPatch.apply edits, bumps the version and stamps the time', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);
    const patch = MetadataPatch(set: {'name': 'B'}, remove: {'comment'});
    expect(patch.isEmpty, isFalse);
    expect(const MetadataPatch().isEmpty, isTrue);
    final out = patch.apply(const LandmarkMetadata(entries: {'name': 'A', 'comment': 'c'}, version: 3), now: now);
    expect(out.entries, {'name': 'B', 'updated_at': 1760000000000, 'created_at': 1760000000000});
    expect(out.version, 4);
  });
}

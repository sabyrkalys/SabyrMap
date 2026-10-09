import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:app/landmarks/validation/waypoint_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const valid = MarkerDraft(
    type: LandmarkType.waypoint,
    longitude: 30.5,
    latitude: 50.4,
    name: 'Bunker',
    colorValue: 0xFFFF0000,
  );

  Matcher failsWith(String fragment) =>
      isA<ValidationResult>().having((r) => r.isValid, 'isValid', isFalse).having((r) => r.errors.join(' '), 'errors', contains(fragment));

  test('a valid draft passes', () {
    final result = WaypointValidator.validate(valid);
    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
    expect(WaypointValidator.validate(valid.copyWith(latitude: 90, longitude: -180)).isValid, isTrue);
  });

  test('latitude above 90 fails', () {
    expect(WaypointValidator.validate(valid.copyWith(latitude: 90.0001)), failsWith('latitude'));
  });

  test('longitude above 180 fails', () {
    expect(WaypointValidator.validate(valid.copyWith(longitude: 180.5)), failsWith('longitude'));
  });

  test('NaN coordinates fail', () {
    expect(WaypointValidator.validate(valid.copyWith(latitude: double.nan)), failsWith('NaN'));
  });

  test('a 201-character name fails, 200 passes', () {
    expect(WaypointValidator.validate(valid.copyWith(name: 'a' * 201)), failsWith('name'));
    expect(WaypointValidator.validate(valid.copyWith(name: 'a' * 200)).isValid, isTrue);
  });

  test('long comment and description fail', () {
    expect(WaypointValidator.validate(valid.copyWith(comment: 'a' * 5001)), failsWith('comment'));
    expect(WaypointValidator.validate(valid.copyWith(description: 'a' * 20001)), failsWith('description'));
  });

  test('colour outside ARGB fails', () {
    expect(WaypointValidator.validate(valid.copyWith(colorValue: -1)), failsWith('colorValue'));
    expect(WaypointValidator.validate(valid.copyWith(colorValue: 0x100000000)), failsWith('colorValue'));
  });

  test('a type other than waypoint fails', () {
    expect(WaypointValidator.validate(valid.copyWith(type: LandmarkType.track)), failsWith('waypoint'));
  });

  test('several problems are all reported', () {
    final result = WaypointValidator.validate(valid.copyWith(latitude: 100, longitude: 200, colorValue: -5));
    expect(result.errors, hasLength(3));
    expect(() => result.errors.add('x'), throwsUnsupportedError);
  });

  test('patches are checked by the same rules', () {
    expect(WaypointValidator.validatePatch(const WaypointPatch()).isValid, isTrue);
    expect(WaypointValidator.validatePatch(const WaypointPatch(latitude: 91)), failsWith('latitude'));
    expect(WaypointValidator.validatePatch(WaypointPatch(name: 'a' * 201)), failsWith('name'));
  });

  test('ValidationException lists the errors', () {
    expect(const ValidationException(['a', 'b']).toString(), 'ValidationException: a; b');
  });
}

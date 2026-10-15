import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/on_screen/on_screen_saver.dart';
import 'package:app/landmarks/serialization/binary_writer.dart';
import 'package:app/landmarks/serialization/landmark_codec.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fixture.dart';

void main() {
  late ServicesFixture f;

  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.dispose());

  const center = LandmarkLocation(longitude: 37.08, latitude: 48.46);

  group('codec', () {
    final circle = LandmarkFile.of(
      const CircleObject(center: center, radiusMeters: 250.5, userMetadata: LandmarkMetadata(entries: {'name': 'Зона'})),
    );
    final text = LandmarkFile.of(
      const TextObject(location: center, text: 'Мост\nвзорван', userMetadata: LandmarkMetadata(entries: {'rotation': 45})),
    );

    test('circle and text round-trip; every cut is rejected', () {
      for (final file in [circle, text]) {
        final bytes = LandmarkCodec.encode(file);
        expect(LandmarkCodec.decode(bytes), file);
        for (var cut = 0; cut < bytes.length; cut++) {
          expect(() => LandmarkCodec.decode(Uint8List.sublistView(bytes, 0, cut)), throwsA(isA<SerializationException>()));
        }
      }
    });

    test('a zero or broken radius is rejected on read', () {
      final bytes = LandmarkCodec.encode(circle);
      final w = BinaryWriter()..writeDouble(0);
      final broken = Uint8List.fromList([...bytes.sublist(0, bytes.length - 8), ...w.toBytes()]);
      expect(() => LandmarkCodec.decode(broken), throwsA(isA<SerializationException>()));
    });
  });

  test('creates, edits and indexes a circle and a text; both go into a landmark file', () async {
    final s = f.services;
    MarkerDraft draft(LandmarkType type, {double? radius, String? text}) => MarkerDraft(
      type: type,
      name: type == LandmarkType.circle ? 'Зона' : null,
      longitude: center.longitude,
      latitude: center.latitude,
      radiusMeters: radius,
      text: text,
      targetFolder: f.paths.landmarks,
    );

    final circlePath = await s.creation.create(draft(LandmarkType.circle, radius: 300));
    final textPath = await s.creation.create(draft(LandmarkType.text, text: '  Мост  '));
    expect(p.extension(circlePath), '.cir');
    expect(p.extension(textPath), '.lbl');

    final circleItem = s.index.byPath(circlePath)!;
    expect((circleItem.type, circleItem.name), (LandmarkType.circle, 'Зона'));
    expect(circleItem.latitude, closeTo(48.46, 1e-6));
    expect(s.index.byPath(textPath)!.longitude, closeTo(37.08, 1e-6));

    await s.shapes.updateCircle(circlePath, radiusMeters: 500);
    await s.shapes.updateText(textPath, text: 'Брод', location: const LandmarkLocation(longitude: 37.1, latitude: 48.5));
    expect(((await s.repository.load(circlePath)).content as CircleObject).radiusMeters, 500);
    final label = (await s.repository.load(textPath)).content as TextObject;
    expect(label.text, 'Брод');
    expect(label.location.latitude, closeTo(48.5, 1e-6));
    expect(s.index.byPath(textPath)!.latitude, closeTo(48.5, 1e-6));

    final ldk = await OnScreenSaver.saveAll(s, [circlePath, textPath], name: 'Схема');
    expect(s.index.nestedIn(ldk).map((i) => i.type), [LandmarkType.circle, LandmarkType.text]);
    expect(s.index.nestedIn(ldk).first.latitude, closeTo(48.46, 1e-6));
  });

  test('bad circles and texts are rejected', () async {
    final s = f.services;
    Future<String> make(LandmarkType type, {double? radius, String? text}) => s.creation.create(
      MarkerDraft(type: type, longitude: 37, latitude: 48, radiusMeters: radius, text: text),
    );
    await expectLater(make(LandmarkType.circle), throwsA(isA<ValidationException>()));
    await expectLater(make(LandmarkType.circle, radius: -1), throwsA(isA<ValidationException>()));
    await expectLater(make(LandmarkType.text, text: '   '), throwsA(isA<ValidationException>()));

    final path = await make(LandmarkType.circle, radius: 10);
    await expectLater(s.shapes.updateCircle(path, radiusMeters: 0), throwsA(isA<ValidationException>()));
    await expectLater(s.shapes.updateText(path, text: 'x'), throwsA(isA<ArgumentError>()));
  });
}

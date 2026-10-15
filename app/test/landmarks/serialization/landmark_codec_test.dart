import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/serialization/binary_reader.dart';
import 'package:app/landmarks/serialization/landmark_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LandmarkFile roundTrip(LandmarkFile f) => LandmarkCodec.decode(LandmarkCodec.encode(f));

  LandmarkLocation loc(double lon, double lat, {List<LocationValue> values = const []}) =>
      LandmarkLocation(longitude: lon, latitude: lat, values: values);

  const technical = LandmarkMetadata(entries: {'created_at': 1760000000000, 'updated_at': 1760000000500}, version: 2);
  final full = [
    const LocationValue(type: LocationValueType.elevation, value: 312000),
    const LocationValue(type: LocationValueType.utcTime, value: 1760000000123),
    const LocationValue(type: LocationValueType.accuracy, value: 450),
  ];
  WaypointObject wp(String name, double lon, double lat) => WaypointObject(
    userMetadata: LandmarkMetadata(entries: {'name': name, 'color': 0xFFFF0000, 'icon': 'flag'}),
    location: loc(lon, lat, values: full),
  );

  final samples = <LandmarkFile>[
    LandmarkFile.of(
      WaypointObject(
        userMetadata: const LandmarkMetadata(entries: {'name': 'Bunker', 'comment': 'вход с севера'}, version: 1),
        technicalMetadata: technical,
        location: loc(30.5234, 50.4501, values: full),
      ),
    ),
    LandmarkFile.of(
      SetObject(
        userMetadata: const LandmarkMetadata(entries: {'name': 'Посты'}),
        technicalMetadata: technical,
        waypoints: [wp('A', 30.1, 50.1), wp('B', 30.2, 50.2)],
      ),
    ),
    LandmarkFile.of(
      RouteObject(
        userMetadata: const LandmarkMetadata(entries: {'name': 'Маршрут'}),
        technicalMetadata: technical,
        waypoints: [wp('Start', 30.1, 50.1), wp('Finish', 30.3, 50.3)],
      ),
    ),
    LandmarkFile.of(
      AreaObject(
        userMetadata: const LandmarkMetadata(entries: {'name': 'Поле'}),
        technicalMetadata: technical,
        polygons: [
          AreaPolygon(
            userMetadata: const LandmarkMetadata(entries: {'name': 'outer'}),
            outline: [loc(30, 50), loc(30.1, 50), loc(30.1, 50.1), loc(30, 50.1)],
            holes: [
              [loc(30.02, 50.02), loc(30.04, 50.02), loc(30.04, 50.04)],
            ],
          ),
          AreaPolygon(outline: [loc(31, 51), loc(31.1, 51), loc(31.1, 51.1)]),
        ],
      ),
    ),
    LandmarkFile.of(
      TrackObject(
        userMetadata: const LandmarkMetadata(entries: {'name': 'Выход 9 октября'}),
        technicalMetadata: technical,
        waypoints: [wp('Привал', 30.15, 50.15)],
        segments: [
          TrackSegment(
            userMetadata: const LandmarkMetadata(entries: {'name': 'seg 1'}),
            locations: [loc(30.1, 50.1, values: full), loc(30.11, 50.11, values: full)],
          ),
          TrackSegment(locations: [loc(30.2, 50.2)]),
        ],
      ),
    ),
    LandmarkFile.of(
      CircleObject(center: loc(30.5, 50.5), radiusMeters: 1250, userMetadata: const LandmarkMetadata(entries: {'name': 'Зона'})),
    ),
    LandmarkFile.of(TextObject(location: loc(30.6, 50.6), text: 'Брод', technicalMetadata: technical)),
    LandmarkFile.of(
      LdkFileObject(
        userMetadata: const LandmarkMetadata(entries: {'name': 'Поход', 'comment': 'Весна'}),
        technicalMetadata: technical,
      ),
    ),
  ];

  for (final sample in samples) {
    test('${sample.type.extension} round-trips', () {
      expect(roundTrip(sample), sample);
    });
  }

  test('empty objects round-trip', () {
    for (final empty in <LandmarkObject>[
      const WaypointObject(location: LandmarkLocation(longitude: 0, latitude: 0)),
      const SetObject(),
      const LdkFileObject(),
      const RouteObject(),
      const AreaObject(),
      const AreaObject(polygons: [AreaPolygon()]),
      const TrackObject(),
      const TrackObject(segments: [TrackSegment()]),
    ]) {
      final file = LandmarkFile.of(empty);
      expect(roundTrip(file), file);
    }
  });

  test('a track with 5000 points round-trips', () {
    final points = [
      for (var i = 0; i < 5000; i++)
        loc((300000000 + i * 100) / 1e7, (500000000 + i * 100) / 1e7, values: [LocationValue(type: LocationValueType.utcTime, value: 1760000000000 + i * 1000)]),
    ];
    final file = LandmarkFile.of(TrackObject(segments: [TrackSegment(locations: points)]));
    final back = roundTrip(file).content as TrackObject;
    expect(back.segments.single.locations, hasLength(5000));
    expect(back, file.content);
  });

  test('header carries magic and version', () {
    for (final type in LandmarkType.values) {
      final file = samples.firstWhere((s) => s.type == type);
      final bytes = LandmarkCodec.encode(file);
      final r = BinaryReader(bytes);
      final packed = r.readInt();
      expect(packed >> 8, type.magic);
      expect(packed & 0xFF, LandmarkType.formatVersion);
      expect(r.readInt(), 8);
      expect(LandmarkCodec.readHeader(BinaryReader(bytes)).type, type);
    }
  });

  test('a longer header is skipped', () {
    final bytes = LandmarkCodec.encode(samples.first);
    final extended = Uint8List(bytes.length + 4)
      ..setRange(0, 4, bytes)
      ..setRange(4, 8, [0, 0, 0, 12])
      ..setRange(12, bytes.length + 4, bytes, 8);
    expect(LandmarkCodec.decode(extended), samples.first);
  });

  test('wrong magic is rejected', () {
    final bytes = LandmarkCodec.encode(samples.first)..[1] = 0x77;
    expect(() => LandmarkCodec.decode(bytes), throwsA(isA<SerializationException>()));
  });

  test('unsupported version is rejected', () {
    final bytes = LandmarkCodec.encode(samples.first)..[3] = 9;
    expect(() => LandmarkCodec.decode(bytes), throwsA(isA<SerializationException>()));
  });

  test('truncated files are rejected at every cut', () {
    for (final sample in samples) {
      final bytes = LandmarkCodec.encode(sample);
      for (var cut = 0; cut < bytes.length; cut += 7) {
        expect(
          () => LandmarkCodec.decode(Uint8List.sublistView(bytes, 0, cut)),
          throwsA(isA<SerializationException>()),
          reason: '${sample.type.extension} cut at $cut',
        );
      }
    }
  });

  test('trailing garbage is rejected', () {
    final bytes = LandmarkCodec.encode(samples.first);
    expect(() => LandmarkCodec.decode(Uint8List.fromList([...bytes, 0])), throwsA(isA<SerializationException>()));
  });

  test('type that does not match the content is rejected', () {
    expect(
      () => LandmarkCodec.encode(LandmarkFile(type: LandmarkType.route, content: const SetObject())),
      throwsA(isA<SerializationException>()),
    );
  });

  test('extensions and magics map back to types', () {
    for (final t in LandmarkType.values) {
      expect(LandmarkType.fromExtension(t.extension), t);
      expect(LandmarkType.fromExtension('.${t.extension.toUpperCase()}'), t);
      expect(LandmarkType.fromMagic(t.magic), t);
    }
    expect(LandmarkType.fromExtension('gpx'), isNull);
    expect(LandmarkType.fromMagic(0x123456), isNull);
  });

  group('landmark file with objects', () {
    final ldk = LandmarkFile.of(
      LdkFileObject(
        userMetadata: const LandmarkMetadata(entries: {'name': 'Метки на экране'}),
        technicalMetadata: technical,
        objects: [
          for (final s in samples)
            if (s.type != LandmarkType.ldkFile) s.content,
        ],
      ),
    );

    test('round-trips every object type', () {
      expect((ldk.content as LdkFileObject).objects, hasLength(samples.length - 1));
      expect(roundTrip(ldk), ldk);
    });

    test('a file written before objects (empty payload) reads as empty', () {
      final empty = LandmarkFile.of(const LdkFileObject(userMetadata: LandmarkMetadata(entries: {'name': 'Старый'})));
      expect((roundTrip(empty).content as LdkFileObject).objects, isEmpty);
    });

    test('cut inside the objects is rejected', () {
      final bytes = LandmarkCodec.encode(ldk);
      final metadataEnd = LandmarkCodec.encode(
        LandmarkFile.of(
          LdkFileObject(userMetadata: (ldk.content as LdkFileObject).userMetadata, technicalMetadata: technical),
        ),
      ).length;
      for (var cut = metadataEnd + 1; cut < bytes.length; cut++) {
        expect(
          () => LandmarkCodec.decode(Uint8List.sublistView(bytes, 0, cut)),
          throwsA(isA<SerializationException>()),
          reason: 'cut at $cut',
        );
      }
    });

    test('a landmark file inside a landmark file is rejected', () {
      expect(
        () => LandmarkCodec.encode(LandmarkFile.of(const LdkFileObject(objects: [LdkFileObject()]))),
        throwsA(isA<SerializationException>()),
      );
    });
  });
}

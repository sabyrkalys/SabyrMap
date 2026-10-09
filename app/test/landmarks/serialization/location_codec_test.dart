import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/serialization/binary_writer.dart';
import 'package:app/landmarks/serialization/location_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LandmarkLocation roundTrip(LandmarkLocation l) => LocationCodec.decode(LocationCodec.encode(l));

  final allValues = [
    const LocationValue(type: LocationValueType.accuracy, value: 350),
    const LocationValue(type: LocationValueType.battery, value: 87),
    const LocationValue(type: LocationValueType.elevation, value: -12345),
    LocationValue(type: LocationValueType.cellular, value: Uint8List.fromList([3, 200])),
    const LocationValue(type: LocationValueType.pressure, value: 1013250),
    LocationValue(type: LocationValueType.satellites, value: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 255])),
    const LocationValue(type: LocationValueType.utcTime, value: 1760000000123),
    const LocationValue(type: LocationValueType.verticalAcc, value: 800),
  ];

  test('round-trips every LocationValue type', () {
    final l = LandmarkLocation(longitude: 30.5234, latitude: 50.4501, values: allValues);
    expect(roundTrip(l), l);
    expect(allValues.map((v) => v.type).toSet(), LocationValueType.all.toSet());
  });

  test('empty values round-trip, size covers just the coordinates', () {
    const l = LandmarkLocation(longitude: 0, latitude: 0);
    final bytes = LocationCodec.encode(l);
    expect(bytes.length, 12);
    expect(bytes.sublist(0, 4), [0, 0, 0, 8]);
    expect(roundTrip(l), l);
  });

  test('coordinates are kept to 1e-7 degrees', () {
    const l = LandmarkLocation(longitude: -179.123456789, latitude: 89.987654321);
    final back = roundTrip(l);
    expect(back.longitude, closeTo(l.longitude, 1e-7));
    expect(back.latitude, closeTo(l.latitude, 1e-7));
    expect(back.longitude, -179.1234568);
  });

  test('extreme coordinates fit', () {
    const l = LandmarkLocation(longitude: 180, latitude: -90);
    expect(roundTrip(l), l);
  });

  test('coordinates out of range are rejected', () {
    expect(() => LocationCodec.encode(const LandmarkLocation(longitude: 181, latitude: 0)), throwsA(isA<SerializationException>()));
    expect(
      () => LocationCodec.encode(const LandmarkLocation(longitude: 0, latitude: double.nan)),
      throwsA(isA<SerializationException>()),
    );
  });

  test('unknown value type is rejected on write and read', () {
    expect(
      () => LocationCodec.encode(const LandmarkLocation(longitude: 0, latitude: 0, values: [LocationValue(type: 0x7a, value: 1)])),
      throwsA(isA<SerializationException>()),
    );
    final bytes = (BinaryWriter()
          ..writeInt(10)
          ..writeInt(0)
          ..writeInt(0)
          ..writeByte(0x7a)
          ..writeByte(0))
        .toBytes();
    expect(() => LocationCodec.decode(bytes), throwsA(isA<SerializationException>()));
  });

  test('wrong value shape is rejected', () {
    expect(
      () => LocationCodec.encode(
        LandmarkLocation(longitude: 0, latitude: 0, values: [LocationValue(type: LocationValueType.cellular, value: Uint8List(3))]),
      ),
      throwsA(isA<SerializationException>()),
    );
    expect(
      () => LocationCodec.encode(
        const LandmarkLocation(longitude: 0, latitude: 0, values: [LocationValue(type: LocationValueType.elevation, value: 'high')]),
      ),
      throwsA(isA<SerializationException>()),
    );
  });

  test('a value overrunning the declared size is rejected', () {
    final bytes = (BinaryWriter()
          ..writeInt(10)
          ..writeInt(0)
          ..writeInt(0)
          ..writeByte(LocationValueType.elevation)
          ..writeInt(1))
        .toBytes();
    expect(() => LocationCodec.decode(bytes), throwsA(isA<SerializationException>()));
  });
}

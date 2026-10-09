import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/serialization/binary_writer.dart';
import 'package:app/landmarks/serialization/metadata_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LandmarkMetadata roundTrip(LandmarkMetadata m) => MetadataCodec.decode(MetadataCodec.encode(m));

  test('empty metadata round-trips', () {
    expect(roundTrip(const LandmarkMetadata()), const LandmarkMetadata());
  });

  test('count -1 reads as empty metadata', () {
    final bytes = (BinaryWriter()..writeInt(-1)).toBytes();
    expect(MetadataCodec.decode(bytes), const LandmarkMetadata());
  });

  test('every value type round-trips, with the version', () {
    final m = LandmarkMetadata(
      version: 7,
      entries: {
        'visible': true,
        'locked': false,
        'color': 0xFF336699,
        'negative': -2,
        'big': 0x7FFFFFFFFFFFFFFF,
        'ratio': 0.125,
        'name': 'Высота 312',
        'comment': '',
        'icon': 'cabin',
        'thumb': Uint8List.fromList([0, 1, 2, 255]),
        'empty_raw': Uint8List(0),
        'style': LandmarkMetadata.encodeStyle({'width': 3, 'dash': true}),
      },
    );
    final back = roundTrip(m);
    expect(back, m);
    expect(back.entries.keys, m.entries.keys);
    expect(back.name, 'Высота 312');
    expect(back.colorValue, 0xFF336699);
    expect(back.iconId, 'cabin');
    expect(back.style, {'width': 3, 'dash': true});
    expect(back.entries['thumb'], isA<Uint8List>());
  });

  test('version grows with an edit and survives encoding', () {
    const original = LandmarkMetadata(entries: {'name': 'A'}, version: 1);
    final edited = original.withEntries({'name': 'B'}).copyWith(version: original.version + 1);
    final back = roundTrip(edited);
    expect(back.version, 2);
    expect(back.name, 'B');
  });

  test('unsupported value types are rejected on write', () {
    expect(
      () => MetadataCodec.encode(const LandmarkMetadata(entries: {'style': {'width': 3}})),
      throwsA(isA<SerializationException>()),
    );
    expect(
      () => MetadataCodec.encode(LandmarkMetadata(entries: {'when': DateTime(2026)})),
      throwsA(isA<SerializationException>()),
    );
    expect(() => MetadataCodec.encode(const LandmarkMetadata(entries: {'x': null})), throwsA(isA<SerializationException>()));
  });

  test('unknown value type code is rejected on read', () {
    final bytes = (BinaryWriter()
          ..writeInt(1)
          ..writeString('x')
          ..writeInt(-9))
        .toBytes();
    expect(() => MetadataCodec.decode(bytes), throwsA(isA<SerializationException>()));
  });

  test('extensions are read past', () {
    final bytes = (BinaryWriter()
          ..writeInt(1)
          ..writeString('name')
          ..writeInt(1)
          ..writeBytes(Uint8List.fromList([0x41]))
          ..writeInt(3)
          ..writeInt(1)
          ..writeString('ext')
          ..writeInt(0)
          ..writeInt(0)
          ..writeInt(-1))
        .toBytes();
    expect(MetadataCodec.decode(bytes), const LandmarkMetadata(entries: {'name': 'A'}, version: 3));
  });

  test('truncated metadata is rejected', () {
    final bytes = MetadataCodec.encode(const LandmarkMetadata(entries: {'name': 'Bunker'}));
    expect(() => MetadataCodec.decode(Uint8List.sublistView(bytes, 0, bytes.length - 3)), throwsA(isA<SerializationException>()));
  });
}

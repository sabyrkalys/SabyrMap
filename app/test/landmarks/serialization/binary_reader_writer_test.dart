import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/serialization/binary_reader.dart';
import 'package:app/landmarks/serialization/binary_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips every primitive, including boundaries', () {
    final raw = Uint8List.fromList([0, 1, 127, 128, 255]);
    final w = BinaryWriter()
      ..writeInt(-0x80000000)
      ..writeInt(0x7FFFFFFF)
      ..writeInt(-1)
      ..writeInt(0)
      ..writeLong(-0x8000000000000000)
      ..writeLong(0x7FFFFFFFFFFFFFFF)
      ..writeLong(-2)
      ..writeByte(-128)
      ..writeByte(127)
      ..writeByte(-1)
      ..writeDouble(3.141592653589793)
      ..writeDouble(-0.0)
      ..writeDouble(double.infinity)
      ..writeString('')
      ..writeString('Высота 312 🏔 日本')
      ..writeBytes(raw);

    final r = BinaryReader(w.toBytes());
    expect(r.readInt(), -0x80000000);
    expect(r.readInt(), 0x7FFFFFFF);
    expect(r.readInt(), -1);
    expect(r.readInt(), 0);
    expect(r.readLong(), -0x8000000000000000);
    expect(r.readLong(), 0x7FFFFFFFFFFFFFFF);
    expect(r.readLong(), -2);
    expect(r.readByte(), -128);
    expect(r.readByte(), 127);
    expect(r.readByte(), -1);
    expect(r.readDouble(), 3.141592653589793);
    expect(r.readDouble().isNegative, isTrue);
    expect(r.readDouble(), double.infinity);
    expect(r.readString(), '');
    expect(r.readString(), 'Высота 312 🏔 日本');
    expect(r.readBytes(5), raw);
    expect(r.remaining, 0);
  });

  test('writes big-endian', () {
    final bytes = (BinaryWriter()..writeInt(0x01020304)).toBytes();
    expect(bytes, [1, 2, 3, 4]);
  });

  test('string length is in UTF-8 bytes', () {
    final bytes = (BinaryWriter()..writeString('я')).toBytes();
    expect(bytes, [0, 0, 0, 2, 0xD1, 0x8F]);
  });

  test('position, remaining and skip', () {
    final r = BinaryReader(Uint8List(10));
    r.skip(3);
    expect(r.position, 3);
    expect(r.remaining, 7);
    r.readInt();
    expect(r.position, 7);
  });

  group('reading past the end throws with the position', () {
    test('readInt', () {
      final r = BinaryReader(Uint8List(6))..readInt();
      expect(r.readInt, throwsA(isA<SerializationException>().having((e) => e.position, 'position', 4)));
    });

    test('readLong, readDouble, readByte, readBytes, skip', () {
      expect(BinaryReader(Uint8List(7)).readLong, throwsA(isA<SerializationException>()));
      expect(BinaryReader(Uint8List(7)).readDouble, throwsA(isA<SerializationException>()));
      expect(BinaryReader(Uint8List(0)).readByte, throwsA(isA<SerializationException>()));
      expect(() => BinaryReader(Uint8List(2)).readBytes(3), throwsA(isA<SerializationException>()));
      expect(() => BinaryReader(Uint8List(2)).skip(3), throwsA(isA<SerializationException>()));
    });

    test('readString with a length beyond the buffer', () {
      final bytes = (BinaryWriter()..writeInt(100)..writeBytes(Uint8List(3))).toBytes();
      expect(BinaryReader(bytes).readString, throwsA(isA<SerializationException>()));
    });

    test('readString with a negative length', () {
      final bytes = (BinaryWriter()..writeInt(-5)).toBytes();
      expect(BinaryReader(bytes).readString, throwsA(isA<SerializationException>()));
    });
  });

  test('out-of-range values are rejected on write', () {
    expect(() => BinaryWriter().writeInt(0x80000000), throwsA(isA<SerializationException>()));
    expect(() => BinaryWriter().writeByte(128), throwsA(isA<SerializationException>()));
    expect(() => BinaryWriter().writeByte(-129), throwsA(isA<SerializationException>()));
  });
}

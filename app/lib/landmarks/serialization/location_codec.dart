import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/models/landmark_location.dart';

import 'binary_reader.dart';
import 'binary_writer.dart';

/// Запись и чтение [LandmarkLocation].
///
/// ```text
/// Location:
///   int size                  — размер структуры в байтах
///   int longitude * 1e7       — round
///   int latitude  * 1e7       — round
///   LocationValue * (пока не исчерпан size)
///
/// LocationValue:
///   byte type
///   data                      — по типу, см. LocationValueType
/// ```
///
/// Decision: `size` считает байты после самого поля `size` (координаты и
/// значения), без его собственных 4 байт.
abstract final class LocationCodec {
  static const double _scale = 1e7;

  /// Записывает [location] в [w].
  static void write(BinaryWriter w, LandmarkLocation location) {
    final body = BinaryWriter()
      ..writeInt(_toFixed(location.longitude, 'longitude', w.length))
      ..writeInt(_toFixed(location.latitude, 'latitude', w.length));
    for (final value in location.values) {
      _writeValue(body, value);
    }
    w.writeInt(body.length);
    w.writeBytes(body.toBytes());
  }

  /// Читает точку из [r].
  static LandmarkLocation read(BinaryReader r) {
    final sizeAt = r.position;
    final size = r.readInt();
    if (size < 8) throw SerializationException('Invalid location size $size', position: sizeAt);
    if (size > r.remaining) {
      throw SerializationException('Location size $size exceeds remaining ${r.remaining} byte(s)', position: sizeAt);
    }
    final end = r.position + size;
    final longitude = r.readInt() / _scale;
    final latitude = r.readInt() / _scale;
    final values = <LocationValue>[];
    while (r.position < end) {
      values.add(_readValue(r));
    }
    if (r.position != end) {
      throw SerializationException('Location value overruns declared size $size', position: r.position);
    }
    return LandmarkLocation(longitude: longitude, latitude: latitude, values: values);
  }

  /// Список точек: `int count` + Location * count.
  static void writeList(BinaryWriter w, List<LandmarkLocation> locations) {
    w.writeInt(locations.length);
    for (final location in locations) {
      write(w, location);
    }
  }

  /// Читает список, записанный [writeList].
  static List<LandmarkLocation> readList(BinaryReader r) {
    final count = readCount(r, 'location');
    return [for (var i = 0; i < count; i++) read(r)];
  }

  /// Точка одним буфером.
  static Uint8List encode(LandmarkLocation location) {
    final w = BinaryWriter();
    write(w, location);
    return w.toBytes();
  }

  /// Точка из буфера; лишние байты в конце — ошибка.
  static LandmarkLocation decode(Uint8List bytes) {
    final r = BinaryReader(bytes);
    final location = read(r);
    if (r.remaining != 0) {
      throw SerializationException('${r.remaining} unexpected trailing byte(s)', position: r.position);
    }
    return location;
  }

  /// Неотрицательный счётчик элементов.
  static int readCount(BinaryReader r, String what) {
    final at = r.position;
    final count = r.readInt();
    if (count < 0) throw SerializationException('Invalid $what count $count', position: at);
    return count;
  }

  static int _toFixed(double degrees, String what, int position) {
    if (!degrees.isFinite) throw SerializationException('Non-finite $what $degrees', position: position);
    final limit = what == 'latitude' ? 90.0 : 180.0;
    if (degrees.abs() > limit) throw SerializationException('$what $degrees is out of range', position: position);
    return (degrees * _scale).round();
  }

  /// Размер данных значения по типу; null — тип неизвестен.
  static int? _sizeOf(int type) => switch (type) {
    LocationValueType.battery => 1,
    LocationValueType.cellular => 2,
    LocationValueType.accuracy ||
    LocationValueType.elevation ||
    LocationValueType.pressure ||
    LocationValueType.verticalAcc => 4,
    LocationValueType.satellites || LocationValueType.utcTime => 8,
    _ => null,
  };

  static void _writeValue(BinaryWriter w, LocationValue v) {
    final size = _sizeOf(v.type);
    if (size == null) {
      throw SerializationException('Unknown location value type 0x${v.type.toRadixString(16)}', position: w.length);
    }
    w.writeByte(v.type);
    switch ((v.type, v.value)) {
      case (LocationValueType.battery, int x):
        w.writeByte(x);
      case (LocationValueType.utcTime, int x):
        w.writeLong(x);
      case (LocationValueType.cellular || LocationValueType.satellites, Uint8List x) when x.length == size:
        w.writeBytes(x);
      case (_, int x) when size == 4:
        w.writeInt(x);
      default:
        throw SerializationException(
          'Location value 0x${v.type.toRadixString(16)} has invalid value ${v.value}',
          position: w.length,
        );
    }
  }

  static LocationValue _readValue(BinaryReader r) {
    final at = r.position;
    final type = r.readByte();
    final size = _sizeOf(type);
    if (size == null) throw SerializationException('Unknown location value type 0x${type.toRadixString(16)}', position: at);
    final Object value = switch (type) {
      LocationValueType.battery => r.readByte(),
      LocationValueType.utcTime => r.readLong(),
      LocationValueType.cellular || LocationValueType.satellites => r.readBytes(size),
      _ => r.readInt(),
    };
    return LocationValue(type: type, value: value);
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';

import 'binary_reader.dart';
import 'binary_writer.dart';

/// Запись и чтение [LandmarkMetadata].
///
/// ```text
/// MetadataContent:
///   int count                 — число записей, либо -1 (метаданных нет)
///   if count != -1:
///     Entry * count
///     int metadataVersion
///     MetadataExtensions:
///       int extCount          — либо -1
///       if extCount != -1:
///         MetadataExtension * extCount
///
/// Entry:
///   string name
///   int type                  — -1 bool, -2 long, -3 double, -4 raw,
///                               >= 0 string (type — длина в байтах UTF-8)
///   if type == -4: int size
///   data
/// ```
abstract final class MetadataCodec {
  static const int typeBool = -1;
  static const int typeLong = -2;
  static const int typeDouble = -3;
  static const int typeRaw = -4;

  /// Записывает [metadata] в [w].
  ///
  /// Decision: всегда пишем count (0 для пустого набора), чтобы версия
  /// сохранялась; расширений не пишем (extCount = -1).
  static void write(BinaryWriter w, LandmarkMetadata metadata) {
    w.writeInt(metadata.entries.length);
    for (final MapEntry(:key, :value) in metadata.entries.entries) {
      w.writeString(key);
      _writeValue(w, key, value);
    }
    w.writeInt(metadata.version);
    w.writeInt(-1);
  }

  /// Читает метаданные из [r].
  static LandmarkMetadata read(BinaryReader r) {
    final countAt = r.position;
    final count = r.readInt();
    if (count == -1) return const LandmarkMetadata();
    if (count < 0) throw SerializationException('Invalid metadata entry count $count', position: countAt);

    final entries = <String, dynamic>{};
    for (var i = 0; i < count; i++) {
      final name = r.readString();
      entries[name] = _readValue(r);
    }
    final version = r.readInt();

    final extAt = r.position;
    final extCount = r.readInt();
    if (extCount < -1) throw SerializationException('Invalid metadata extension count $extCount', position: extAt);
    // Decision: расширение = string name + вложенный MetadataContent.
    // Модель их не хранит: читаем, чтобы пройти структуру, и отбрасываем.
    for (var i = 0; i < extCount; i++) {
      r.readString();
      read(r);
    }
    return LandmarkMetadata(entries: entries, version: version);
  }

  /// Метаданные одним буфером.
  static Uint8List encode(LandmarkMetadata metadata) {
    final w = BinaryWriter();
    write(w, metadata);
    return w.toBytes();
  }

  /// Метаданные из буфера; лишние байты в конце — ошибка.
  static LandmarkMetadata decode(Uint8List bytes) {
    final r = BinaryReader(bytes);
    final metadata = read(r);
    if (r.remaining != 0) {
      throw SerializationException('${r.remaining} unexpected trailing byte(s)', position: r.position);
    }
    return metadata;
  }

  static void _writeValue(BinaryWriter w, String key, Object? value) {
    switch (value) {
      case bool v:
        w.writeInt(typeBool);
        w.writeByte(v ? 1 : 0);
      case int v:
        w.writeInt(typeLong);
        w.writeLong(v);
      case double v:
        w.writeInt(typeDouble);
        w.writeDouble(v);
      case Uint8List v:
        w.writeInt(typeRaw);
        w.writeInt(v.length);
        w.writeBytes(v);
      case String v:
        final bytes = utf8.encode(v);
        w.writeInt(bytes.length);
        w.writeBytes(bytes);
      default:
        throw SerializationException(
          'Unsupported metadata value type ${value.runtimeType} for key "$key"',
          position: w.length,
        );
    }
  }

  static Object _readValue(BinaryReader r) {
    final typeAt = r.position;
    final type = r.readInt();
    if (type >= 0) return r.readUtf8(type);
    switch (type) {
      case typeBool:
        return r.readByte() != 0;
      case typeLong:
        return r.readLong();
      case typeDouble:
        return r.readDouble();
      case typeRaw:
        final sizeAt = r.position;
        final size = r.readInt();
        if (size < 0) throw SerializationException('Negative raw size $size', position: sizeAt);
        return r.readBytes(size);
      default:
        throw SerializationException('Unknown metadata value type $type', position: typeAt);
    }
  }
}

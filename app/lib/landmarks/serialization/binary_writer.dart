import 'dart:convert';
import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';

/// Последовательная запись big-endian значений; пара к [BinaryReader].
///
/// Значения вне диапазона типа не обрезаются молча, а бросают
/// [SerializationException].
class BinaryWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);
  final ByteData _scratch = ByteData(8);

  static const int _intMin = -0x80000000;
  static const int _intMax = 0x7FFFFFFF;

  /// Сколько байт уже записано.
  int get length => _b.length;

  /// Всё записанное одним буфером.
  Uint8List toBytes() => _b.toBytes();

  /// 4 байта, знаковое.
  void writeInt(int v) {
    if (v < _intMin || v > _intMax) {
      throw SerializationException('Value $v does not fit into int32', position: length);
    }
    _scratch.setInt32(0, v);
    _b.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 4)));
  }

  /// 8 байт, знаковое.
  void writeLong(int v) {
    _scratch.setInt64(0, v);
    _b.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 8)));
  }

  /// 1 байт, знаковое (-128..127).
  void writeByte(int v) {
    if (v < -128 || v > 127) {
      throw SerializationException('Value $v does not fit into a signed byte', position: length);
    }
    _b.addByte(v & 0xFF);
  }

  /// 8 байт, IEEE 754.
  void writeDouble(double v) {
    _scratch.setFloat64(0, v);
    _b.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 8)));
  }

  /// Длина в байтах (int) и затем UTF-8.
  void writeString(String s) {
    final bytes = utf8.encode(s);
    writeInt(bytes.length);
    _b.add(bytes);
  }

  /// Сырые байты без префикса длины.
  void writeBytes(Uint8List bytes) {
    _b.add(Uint8List.fromList(bytes));
  }
}

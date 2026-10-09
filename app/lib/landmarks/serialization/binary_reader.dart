import 'dart:convert';
import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';

/// Последовательное чтение big-endian значений из буфера.
///
/// Любая попытка прочитать за концом буфера бросает
/// [SerializationException] с позицией, на которой это случилось.
class BinaryReader {
  BinaryReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _pos = 0;

  /// Текущее смещение от начала буфера.
  int get position => _pos;

  /// Сколько байт осталось непрочитанными.
  int get remaining => _bytes.length - _pos;

  /// 4 байта, знаковое.
  int readInt() {
    _require(4);
    final v = _data.getInt32(_pos);
    _pos += 4;
    return v;
  }

  /// 8 байт, знаковое.
  int readLong() {
    _require(8);
    final v = _data.getInt64(_pos);
    _pos += 8;
    return v;
  }

  /// 1 байт, знаковое (-128..127).
  int readByte() {
    _require(1);
    final v = _data.getInt8(_pos);
    _pos += 1;
    return v;
  }

  /// 8 байт, IEEE 754.
  double readDouble() {
    _require(8);
    final v = _data.getFloat64(_pos);
    _pos += 8;
    return v;
  }

  /// Длина (int, в байтах) и затем столько байт UTF-8.
  String readString() {
    final start = _pos;
    final length = readInt();
    if (length < 0) {
      throw SerializationException('Negative string length $length', position: start);
    }
    return readUtf8(length);
  }

  /// [length] байт UTF-8 без префикса длины.
  String readUtf8(int length) {
    final start = _pos;
    final bytes = readBytes(length);
    try {
      return utf8.decode(bytes);
    } on FormatException catch (e) {
      throw SerializationException('Invalid UTF-8 string', position: start, cause: e);
    }
  }

  /// Ровно [n] байт (копия).
  Uint8List readBytes(int n) {
    if (n < 0) throw SerializationException('Negative byte count $n', position: _pos);
    _require(n);
    final out = Uint8List.fromList(Uint8List.sublistView(_bytes, _pos, _pos + n));
    _pos += n;
    return out;
  }

  /// Пропустить [n] байт.
  void skip(int n) {
    if (n < 0) throw SerializationException('Negative skip $n', position: _pos);
    _require(n);
    _pos += n;
  }

  void _require(int n) {
    if (n > remaining) {
      throw SerializationException(
        'Unexpected end of data: need $n byte(s), $remaining left',
        position: _pos,
      );
    }
  }
}

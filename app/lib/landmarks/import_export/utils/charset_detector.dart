import 'dart:convert';
import 'dart:typed_data';

/// Определение кодировки текстового файла и перевод байтов в текст и
/// обратно для поддерживаемых кодировок: utf-8, utf-16le, utf-16be,
/// cp1251, latin1.
abstract final class CharsetDetector {
  static const String utf8Name = 'utf-8';
  static const String utf16le = 'utf-16le';
  static const String utf16be = 'utf-16be';
  static const String cp1251 = 'cp1251';
  static const String latin1Name = 'latin1';

  /// Кодировка [bytes]: BOM; затем объявление XML; затем строгий UTF-8;
  /// затем cp1251 или latin1. Пустые данные — utf-8.
  ///
  /// Decision: cp1251 и latin1 различаются эвристикой — в русском тексте
  /// буквы (0xC0–0xFF в cp1251) идут подряд по три и больше, а в
  /// западноевропейском тексте символы с диакритикой обычно одиночные.
  static String detect(Uint8List bytes) {
    if (bytes.isEmpty) return utf8Name;
    if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) return utf8Name;
    if (_startsWith(bytes, const [0xFF, 0xFE])) return utf16le;
    if (_startsWith(bytes, const [0xFE, 0xFF])) return utf16be;
    final declared = xmlDeclaredEncoding(bytes);
    if (declared != null) return declared;
    try {
      utf8.decode(bytes);
      return utf8Name;
    } on FormatException {
      return _looksCyrillic(bytes) ? cp1251 : latin1Name;
    }
  }

  /// Кодировка из `<?xml ... encoding="..."?>` в начале файла, если она
  /// из поддерживаемых.
  static String? xmlDeclaredEncoding(Uint8List bytes) {
    final head = latin1.decode(bytes.sublist(0, bytes.length < 200 ? bytes.length : 200));
    final match = RegExp(r'''^\s*<\?xml[^>]*encoding\s*=\s*["']([^"']+)["']''').firstMatch(head);
    return match == null ? null : normalize(match.group(1)!);
  }

  /// Каноническое имя кодировки; неизвестная — null.
  static String? normalize(String? name) => switch (name?.trim().toLowerCase().replaceAll('_', '-')) {
    'utf-8' || 'utf8' => utf8Name,
    'utf-16le' || 'utf-16' => utf16le,
    'utf-16be' => utf16be,
    'cp1251' || 'windows-1251' || 'win-1251' || 'cp-1251' => cp1251,
    'latin1' || 'latin-1' || 'iso-8859-1' || 'iso8859-1' || 'cp1252' || 'windows-1252' => latin1Name,
    _ => null,
  };

  /// Текст из [bytes] в кодировке [charset] (по умолчанию — [detect]).
  /// BOM отбрасывается. Неизвестная кодировка — [FormatException].
  static String decode(Uint8List bytes, {String? charset}) {
    final name = charset == null ? detect(bytes) : normalize(charset);
    switch (name) {
      case utf8Name:
        final body = _startsWith(bytes, const [0xEF, 0xBB, 0xBF]) ? bytes.sublist(3) : bytes;
        return utf8.decode(body, allowMalformed: charset != null);
      case utf16le || utf16be:
        return _decodeUtf16(bytes, littleEndian: name == utf16le);
      case cp1251:
        return String.fromCharCodes([for (final b in bytes) b < 0x80 ? b : _cp1251High[b - 0x80]]);
      case latin1Name:
        return latin1.decode(bytes);
      default:
        throw FormatException('Unsupported charset: $charset');
    }
  }

  /// Байты [text] в кодировке [charset] (по умолчанию utf-8). Символ, которого
  /// нет в однобайтовой кодировке, заменяется на `?`.
  static Uint8List encode(String text, {String? charset}) {
    final name = charset == null ? utf8Name : normalize(charset);
    switch (name) {
      case utf8Name:
        return utf8.encode(text);
      case cp1251:
        return Uint8List.fromList([for (final c in text.runes) c < 0x80 ? c : (_cp1251Reverse[c] ?? 0x3F)]);
      case latin1Name:
        return Uint8List.fromList([for (final c in text.runes) c <= 0xFF ? c : 0x3F]);
      case utf16le || utf16be:
        final units = [0xFEFF, ...text.codeUnits];
        final out = ByteData(units.length * 2);
        for (final (i, u) in units.indexed) {
          out.setUint16(i * 2, u, name == utf16le ? Endian.little : Endian.big);
        }
        return out.buffer.asUint8List();
      default:
        throw FormatException('Unsupported charset: $charset');
    }
  }

  static bool _looksCyrillic(Uint8List bytes) {
    var run = 0;
    for (final b in bytes) {
      if (b >= 0xC0) {
        if (++run >= 3) return true;
      } else {
        run = 0;
      }
    }
    return false;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final data = ByteData.sublistView(bytes);
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(data.getUint16(i, littleEndian ? Endian.little : Endian.big));
    }
    if (units.isNotEmpty && units.first == 0xFEFF) units.removeAt(0);
    return String.fromCharCodes(units);
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  /// cp1251, байты 0x80–0xFF.
  static final List<int> _cp1251High = [
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
    0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
    0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
    for (var c = 0x0410; c <= 0x044F; c++) c,
  ];

  static final Map<int, int> _cp1251Reverse = {
    for (final (i, c) in _cp1251High.indexed)
      if (c != 0xFFFD) c: 0x80 + i,
  };
}

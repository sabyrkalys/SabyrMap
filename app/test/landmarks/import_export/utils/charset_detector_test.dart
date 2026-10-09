import 'dart:convert';
import 'dart:typed_data';

import 'package:app/landmarks/import_export/utils/charset_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UTF-8 BOM is utf-8 and the BOM is dropped', () {
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Привет')]);
    expect(CharsetDetector.detect(bytes), 'utf-8');
    expect(CharsetDetector.decode(bytes), 'Привет');
  });

  test('UTF-16 BOMs', () {
    final le = CharsetDetector.encode('Ёж', charset: 'utf-16le');
    final be = CharsetDetector.encode('Ёж', charset: 'utf-16be');
    expect(CharsetDetector.detect(le), 'utf-16le');
    expect(CharsetDetector.detect(be), 'utf-16be');
    expect(CharsetDetector.decode(le), 'Ёж');
    expect(CharsetDetector.decode(be), 'Ёж');
  });

  test('plain UTF-8 without BOM', () {
    expect(CharsetDetector.detect(utf8.encode('Высота 312, café')), 'utf-8');
  });

  test('cp1251 without BOM', () {
    final bytes = CharsetDetector.encode('Привет, мир! Ёлка №5', charset: 'cp1251');
    expect(CharsetDetector.detect(bytes), 'cp1251');
    expect(CharsetDetector.decode(bytes), 'Привет, мир! Ёлка №5');
  });

  test('latin1', () {
    final bytes = Uint8List.fromList(latin1.encode('Café naïve, señor'));
    expect(CharsetDetector.detect(bytes), 'latin1');
    expect(CharsetDetector.decode(bytes), 'Café naïve, señor');
  });

  test('an empty file is utf-8', () {
    expect(CharsetDetector.detect(Uint8List(0)), 'utf-8');
  });

  test('the XML declaration wins over guessing', () {
    final bytes = Uint8List.fromList([
      ...ascii.encode('<?xml version="1.0" encoding="windows-1251"?><a>'),
      ...CharsetDetector.encode('Да', charset: 'cp1251'),
      ...ascii.encode('</a>'),
    ]);
    expect(CharsetDetector.detect(bytes), 'cp1251');
  });

  test('names are normalised; unknown is rejected', () {
    expect(CharsetDetector.normalize('Windows-1251'), 'cp1251');
    expect(CharsetDetector.normalize('ISO-8859-1'), 'latin1');
    expect(CharsetDetector.normalize('koi8-r'), isNull);
    expect(() => CharsetDetector.decode(Uint8List(1), charset: 'koi8-r'), throwsFormatException);
  });
}

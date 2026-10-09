import 'package:app/landmarks/import_export/utils/coord_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decimal degrees', () {
    expect(CoordParser.parseValue('55.7558'), 55.7558);
    expect(CoordParser.parseValue('-37.6173'), -37.6173);
    expect(CoordParser.parse('55.7558, 37.6173'), (55.7558, 37.6173));
    expect(CoordParser.parse('55.7558 37.6173'), (55.7558, 37.6173));
    expect(CoordParser.parse('55.7558;37.6173'), (55.7558, 37.6173));
  });

  test('hemisphere letters, in any order', () {
    expect(CoordParser.parse('55.7558N, 37.6173E'), (55.7558, 37.6173));
    expect(CoordParser.parse('33.9S 18.4W'), (-33.9, -18.4));
    expect(CoordParser.parse('37.6173E, 55.7558N'), (55.7558, 37.6173));
    expect(CoordParser.parseValue('S 33.9'), -33.9);
  });

  test('degrees, minutes, seconds', () {
    final (lat, lon) = CoordParser.parse('''55°45'21"N 37°37'2"E''');
    expect(lat, closeTo(55 + 45 / 60 + 21 / 3600, 1e-9));
    expect(lon, closeTo(37 + 37 / 60 + 2 / 3600, 1e-9));
    expect(CoordParser.parseValue('''33°52'S'''), closeTo(-(33 + 52 / 60), 1e-9));
    expect(CoordParser.parseValue('55 45 21.5'), closeTo(55 + 45 / 60 + 21.5 / 3600, 1e-9));
  });

  test('invalid strings throw FormatException', () {
    for (final bad in ['', 'abc', '95.0, 30', '55.7, 190', '55°75\'N', '55.7N 37.6N', '-55S', '1,2,3']) {
      expect(() => CoordParser.parse(bad), throwsFormatException, reason: bad);
    }
    expect(() => CoordParser.parseValue('91', isLatitude: true), throwsFormatException);
    expect(() => CoordParser.parseValue('55E', isLatitude: true), throwsFormatException);
  });

  test('UTM is not supported', () {
    expect(() => CoordParser.parse('37U 412345 6178901'), throwsUnsupportedError);
  });
}

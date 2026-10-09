import 'package:app/maps/on_demand/zoom_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('includes within 1-17', () {
    const r = ZoomRange(1, 17);
    expect(r.includes(1), isTrue);
    expect(r.includes(17), isTrue);
    expect(r.includes(18), isFalse);
    expect(r.includes(0), isFalse);
  });

  test('parse', () {
    expect(ZoomRange.parse('1-17'), const ZoomRange(1, 17));
    expect(ZoomRange.parse(' 5 '), const ZoomRange(5, 5));
    expect(() => ZoomRange.parse('17-1'), throwsFormatException);
    expect(() => ZoomRange.parse('a'), throwsFormatException);
  });
}

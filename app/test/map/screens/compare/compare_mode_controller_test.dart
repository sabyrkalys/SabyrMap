import 'package:app/map/screens/compare/compare_mode_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setIndex moves the slider to the ends', () {
    final c = CompareModeController(['a', 'b', 'c']);
    c.setIndex(2);
    expect(c.sliderValue, 1);
    c.setIndex(0);
    expect(c.sliderValue, 0);
  });

  test('the slider picks the nearest layer', () {
    final c = CompareModeController(['a', 'b', 'c']);
    c.sliderValue = 0.5;
    expect(c.currentIndex, 1);
    expect(c.currentLayerId, 'b');
    c.sliderValue = 0.8;
    expect(c.currentLayerId, 'c');
    c.sliderValue = 0.2;
    expect(c.currentLayerId, 'a');
  });

  test('next and previous stop at the ends; listeners hear only real changes', () {
    final c = CompareModeController(['a', 'b']);
    var notified = 0;
    c.addListener(() => notified++);
    c.previous();
    expect(c.currentLayerId, 'a');
    c.next();
    c.next();
    expect(c.currentLayerId, 'b');
    expect(c.count, 2);
    expect(notified, 1);
  });
}

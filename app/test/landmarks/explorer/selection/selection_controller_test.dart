import 'package:app/landmarks/explorer/selection/selection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SelectionController c;
  late int notified;
  setUp(() {
    c = SelectionController();
    notified = 0;
    c.addListener(() => notified++);
  });

  test('activate turns the mode on', () {
    expect(c.state.isActive, isFalse);
    c.activate();
    expect(c.state.isActive, isTrue);
    expect(notified, 1);
    c.activate();
    expect(notified, 1);
  });

  test('toggle adds and removes', () {
    c.toggle('/a');
    expect(c.contains('/a'), isTrue);
    c.toggle('/a');
    expect(c.contains('/a'), isFalse);
    c.select('/b');
    c.deselect('/b');
    expect(c.state.count, 0);
  });

  test('selectAll and clear', () {
    c.selectAll(['/a', '/b', '/c']);
    expect(c.state.count, 3);
    c.clear();
    expect(c.state.count, 0);
  });

  test('deactivate turns the mode off and clears the selection', () {
    c.activate();
    c.selectAll(['/a', '/b']);
    c.deactivate();
    expect(c.state.isActive, isFalse);
    expect(c.state.count, 0);
  });

  test('snapshot is an immutable copy', () {
    c.selectAll(['/a']);
    final snap = c.snapshot();
    expect(() => snap.add('/b'), throwsUnsupportedError);
    c.select('/b');
    expect(snap, {'/a'});
  });
}

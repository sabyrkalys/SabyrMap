import 'package:app/landmarks/explorer/clipboard/clipboard_entry.dart';
import 'package:app/landmarks/explorer/clipboard/landmarks_clipboard.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = ClipboardEntry(sourcePath: '/a.wpt', type: LandmarkType.waypoint, originalName: 'A');
  const b = ClipboardEntry(sourcePath: '/b.trk', type: LandmarkType.track, originalName: 'B');
  late LandmarksClipboard clipboard;
  setUp(() => clipboard = LandmarksClipboard());

  test('starts empty', () {
    expect(clipboard.isEmpty, isTrue);
    expect(clipboard.isCut, isFalse);
  });

  test('copy fills entries, not cut', () {
    clipboard.copy([a, b]);
    expect(clipboard.entries, [a, b]);
    expect(clipboard.isCut, isFalse);
    expect(clipboard.isEmpty, isFalse);
  });

  test('cut fills entries, cut', () {
    clipboard.cut([a]);
    expect(clipboard.entries, [a]);
    expect(clipboard.isCut, isTrue);
  });

  test('empty clears', () {
    clipboard.cut([a, b]);
    clipboard.empty();
    expect(clipboard.isEmpty, isTrue);
    expect(clipboard.isCut, isFalse);
  });

  test('removeOne drops one entry', () {
    clipboard.cut([a, b]);
    clipboard.removeOne('/a.wpt');
    expect(clipboard.entries, [b]);
    expect(clipboard.isCut, isTrue);
    clipboard.removeOne('/b.trk');
    expect(clipboard.isEmpty, isTrue);
  });

  test('entries cannot be changed from outside', () {
    final source = [a];
    clipboard.copy(source);
    source.add(b);
    expect(clipboard.entries, [a]);
    expect(() => clipboard.entries.add(b), throwsUnsupportedError);
  });
}

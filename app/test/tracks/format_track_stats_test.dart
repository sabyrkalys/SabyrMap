import 'package:app/tracks/format_track_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatTrackLength', () {
    test('shows meters under 1 km', () {
      expect(formatTrackLength(850), '850 м');
    });

    test('shows kilometers with one decimal at or above 1 km', () {
      expect(formatTrackLength(4200), '4.2 км');
    });
  });

  group('formatTrackDuration', () {
    test('shows dash when null', () {
      expect(formatTrackDuration(null), '—');
    });

    test('shows minutes only under an hour', () {
      expect(formatTrackDuration(25 * 60), '25 мин');
    });

    test('shows hours and minutes at or above an hour', () {
      expect(formatTrackDuration(85 * 60), '1 ч 25 мин');
    });
  });

  group('formatElevationGain', () {
    test('shows dash when null', () {
      expect(formatElevationGain(null), '—');
    });

    test('shows a rounded value with a plus sign', () {
      expect(formatElevationGain(320.4), '+320 м');
    });
  });

  group('formatTrackDate', () {
    test('formats as dd.mm.yyyy in local time', () {
      final date = DateTime(2026, 9, 13, 10, 0);
      expect(formatTrackDate(date), '13.09.2026');
    });
  });
}

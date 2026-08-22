import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/track_recording_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_location_source.dart';

void main() {
  test('initial state is idle', () {
    final source = FakeLocationSource();
    final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);
    addTearDown(source.dispose);

    expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
  });

  group('start', () {
    test('transitions to active and requests a 5-meter distance filter', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);

      await container.read(trackRecordingControllerProvider.notifier).start();

      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingActive>());
      expect(source.lastDistanceFilterMeters, 5);
    });

    test('accumulates points as the location source emits them', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();

      source.emit(const TrackPoint(lat: 1.0, lng: 2.0));
      await Future<void>.delayed(Duration.zero);
      source.emit(const TrackPoint(lat: 1.1, lng: 2.1));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(trackRecordingControllerProvider) as TrackRecordingActive;
      expect(state.points, hasLength(2));
      expect(state.points[0].lat, 1.0);
      expect(state.points[1].lat, 1.1);
    });

    test('stays idle with an error message when permission is denied', () async {
      final source = FakeLocationSource(permissionGranted: false);
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);

      await container.read(trackRecordingControllerProvider.notifier).start();

      final state = container.read(trackRecordingControllerProvider);
      expect(state, isA<TrackRecordingIdle>());
      expect((state as TrackRecordingIdle).errorMessage, isNotNull);
    });

    test('is a no-op when already recording', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();
      source.emit(const TrackPoint(lat: 1.0, lng: 2.0));
      await Future<void>.delayed(Duration.zero);

      await container.read(trackRecordingControllerProvider.notifier).start();

      final state = container.read(trackRecordingControllerProvider) as TrackRecordingActive;
      expect(state.points, hasLength(1));
    });
  });

  group('stop', () {
    test('returns the accumulated points and transitions back to idle', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();
      source.emit(const TrackPoint(lat: 1.0, lng: 2.0));
      await Future<void>.delayed(Duration.zero);
      source.emit(const TrackPoint(lat: 1.1, lng: 2.1));
      await Future<void>.delayed(Duration.zero);

      final points = container.read(trackRecordingControllerProvider.notifier).stop();

      expect(points, hasLength(2));
      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
    });

    test('further emissions after stop are not accumulated', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();
      container.read(trackRecordingControllerProvider.notifier).stop();

      source.emit(const TrackPoint(lat: 9.0, lng: 9.0));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
    });

    test('returns an empty list and is a no-op when already idle', () {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);

      final points = container.read(trackRecordingControllerProvider.notifier).stop();

      expect(points, isEmpty);
      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
    });
  });
}

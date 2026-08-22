import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_source.dart';
import 'track_models.dart';

sealed class TrackRecordingState {
  const TrackRecordingState();
}

class TrackRecordingIdle extends TrackRecordingState {
  const TrackRecordingIdle({this.errorMessage});

  final String? errorMessage;
}

class TrackRecordingActive extends TrackRecordingState {
  const TrackRecordingActive({required this.points, required this.startedAt});

  final List<TrackPoint> points;
  final DateTime startedAt;
}

final locationSourceProvider = Provider<LocationSource>((ref) => GeolocatorLocationSource());

final trackRecordingControllerProvider =
    NotifierProvider<TrackRecordingController, TrackRecordingState>(TrackRecordingController.new);

class TrackRecordingController extends Notifier<TrackRecordingState> {
  StreamSubscription<TrackPoint>? _subscription;

  @override
  TrackRecordingState build() {
    ref.onDispose(() {
      _subscription?.cancel();
    });
    return const TrackRecordingIdle();
  }

  LocationSource get _location => ref.read(locationSourceProvider);

  Future<void> start() async {
    if (state is TrackRecordingActive) return;
    final granted = await _location.ensurePermission();
    if (!granted) {
      state = const TrackRecordingIdle(
        errorMessage: 'Нужен доступ к геолокации, чтобы записать трек',
      );
      return;
    }
    state = TrackRecordingActive(points: const [], startedAt: DateTime.now());
    _subscription = _location.positionStream(distanceFilterMeters: 5).listen((point) {
      final current = state;
      if (current is! TrackRecordingActive) return;
      state = TrackRecordingActive(points: [...current.points, point], startedAt: current.startedAt);
    });
  }

  List<TrackPoint> stop() {
    final current = state;
    _subscription?.cancel();
    _subscription = null;
    state = const TrackRecordingIdle();
    return current is TrackRecordingActive ? current.points : const [];
  }
}

import 'package:app/landmarks/composite/services/track_service.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_track.dart';
import 'package:app/navigation/position/position_snapshot.dart';
import 'package:app/navigation/position/position_source.dart';
import 'package:app/navigation/signals/audio_signaler.dart';
import 'package:flutter/foundation.dart';

import 'deviation_detector.dart';
import 'follow_path_calculator.dart';
import 'follow_path_dashboard.dart';
import 'follow_path_signal.dart';
import 'follow_path_state.dart';

/// Следование по треку: ближайшая точка, панель, отклонение и сигналы,
/// автоматическая цель впереди.
class FollowPathController extends ChangeNotifier {
  FollowPathController(
    this._tracks,
    this._position,
    this._signaler,
    this._emitter, {
    DeviationDetector detector = const DeviationDetector(),
  }) : _detector = detector;

  final TrackService _tracks;
  final PositionSource _position;
  final AudioSignaler _signaler;
  final FollowPathSignalEmitter _emitter;
  final DeviationDetector _detector;

  FollowPathState _state = const FollowPathState();

  /// Трек как в файле (до разворота).
  TrackObject? _original;
  PositionSnapshot? _last;
  double? _previousDistance;
  LandmarkLocation? _autoTarget;

  FollowPathState get state => _state;

  /// Точка впереди на [FollowPathState.autoTargetDistanceMeters]; null —
  /// не задано или трек кончился раньше.
  LandmarkLocation? get autoTarget => _autoTarget;

  /// Загружает трек и начинает следование. Ошибка чтения или трек без
  /// точек — [FollowPathState.errorMessage], следование не начинается.
  Future<void> start(
    String trackFilePath, {
    bool reverseOrder = false,
    bool loop = false,
    double? autoTargetDistanceMeters,
    double deviationThresholdMeters = FollowPathState.defaultThreshold,
  }) async {
    await _emitter.stop();
    _reset();
    final TrackObject loaded;
    try {
      loaded = await _tracks.load(trackFilePath);
    } on Exception catch (e) {
      _state = FollowPathState(errorMessage: 'Cannot open the track: $e');
      notifyListeners();
      return;
    }
    if (loaded.segments.every((s) => s.locations.isEmpty)) {
      _state = const FollowPathState(errorMessage: 'The track has no points');
      notifyListeners();
      return;
    }
    _original = loaded;
    _state = FollowPathState(
      trackPath: trackFilePath,
      track: _oriented(loaded, reverseOrder),
      reverseOrder: reverseOrder,
      loop: loop,
      autoTargetDistanceMeters: autoTargetDistanceMeters,
      deviationThresholdMeters: deviationThresholdMeters,
    );
    final position = await _position.getCurrent();
    if (position != null && position.isValid) {
      await updatePosition(position);
    } else {
      _refreshFromStart();
    }
  }

  /// Останавливает следование и сигналы; состояние очищается.
  Future<void> stop() async {
    await _emitter.stop();
    await _signaler.stop();
    _reset();
    _state = const FollowPathState();
    notifyListeners();
  }

  /// Обратный порядок: трек разворачивается, отсчёт — с начала нового порядка.
  void setReverseOrder(bool value) {
    final original = _original;
    if (original == null || value == _state.reverseOrder) {
      _state = _state.copyWith(reverseOrder: value);
      notifyListeners();
      return;
    }
    _state = _state.copyWith(
      reverseOrder: value,
      track: _oriented(original, value),
      currentSegmentIndex: 0,
      currentPointIndex: 0,
    );
    _previousDistance = null;
    _recompute();
  }

  void setLoop(bool value) {
    _state = _state.copyWith(loop: value);
    notifyListeners();
  }

  void setAutoTargetDistanceMeters(double? value) {
    _state = _state.copyWith(autoTargetDistanceMeters: value);
    _updateAutoTarget();
    notifyListeners();
  }

  void setDeviationThreshold(double value) {
    _state = _state.copyWith(deviationThresholdMeters: value);
    notifyListeners();
  }

  /// Новое положение: ближайшая точка, панель, отклонение и сигнал,
  /// цель впереди. В конце трека — к началу ([FollowPathState.loop]) или
  /// остановка.
  ///
  /// Decision: конец трека — когда ближайшая точка последняя и до неё не
  /// дальше порога отклонения.
  Future<void> updatePosition(PositionSnapshot snapshot) async {
    final track = _state.track;
    if (track == null || !snapshot.isValid) return;
    _last = snapshot;
    final (segment, point, distance) = FollowPathCalculator.findClosestPoint(track: track, position: snapshot.location);

    final lastSegment = track.segments.lastIndexWhere((s) => s.locations.isNotEmpty);
    final atEnd =
        segment == lastSegment &&
        point == track.segments[segment].locations.length - 1 &&
        distance <= _state.deviationThresholdMeters;
    if (atEnd && !_state.loop) {
      await stop();
      return;
    }

    final deviation = _detector.evaluate(
      currentDistance: distance,
      previousDistance: _previousDistance ?? distance,
      threshold: _state.deviationThresholdMeters,
      wasSignaled: _state.deviationSignaled,
    );
    _previousDistance = distance;
    _emitter.update(deviation);
    _state = _state.copyWith(
      currentSegmentIndex: atEnd ? 0 : segment,
      currentPointIndex: atEnd ? 0 : point,
      deviationSignaled: deviation != DeviationState.onTrack,
    );
    _recompute();
  }

  void _refreshFromStart() {
    _state = _state.copyWith(currentSegmentIndex: 0, currentPointIndex: 0);
    _recompute();
  }

  void _recompute() {
    final track = _state.track;
    if (track == null) return;
    final position = _last?.location;
    final dashboard = FollowPathCalculator.computeDashboard(
      track: track,
      position: position ?? track.segments[_state.currentSegmentIndex].locations[_state.currentPointIndex],
      currentSegmentIndex: _state.currentSegmentIndex,
      currentPointIndex: _state.currentPointIndex,
      currentSpeedMps: _last?.speedMps,
    );
    _state = _state.copyWith(
      dashboard: position != null
          ? dashboard
          : FollowPathDashboard(
              remainingDistanceMeters: dashboard.remainingDistanceMeters,
              remainingGainMeters: dashboard.remainingGainMeters,
              remainingLossMeters: dashboard.remainingLossMeters,
              etaSeconds: dashboard.etaSeconds,
              currentSegmentIndex: dashboard.currentSegmentIndex,
            ),
    );
    _updateAutoTarget();
    notifyListeners();
  }

  void _updateAutoTarget() {
    final track = _state.track;
    final distance = _state.autoTargetDistanceMeters;
    _autoTarget = track == null || distance == null
        ? null
        : FollowPathCalculator.autoTargetAhead(
            track: track,
            segmentIndex: _state.currentSegmentIndex,
            pointIndex: _state.currentPointIndex,
            distanceMeters: distance,
          );
  }

  void _reset() {
    _original = null;
    _last = null;
    _previousDistance = null;
    _autoTarget = null;
  }

  /// Трек в порядке следования: при [reverse] — сегменты и точки наоборот,
  /// пустые сегменты отброшены.
  static TrackObject _oriented(TrackObject track, bool reverse) {
    final segments = [for (final s in track.segments) if (s.locations.isNotEmpty) s];
    return TrackObject(
      waypoints: track.waypoints,
      userMetadata: track.userMetadata,
      technicalMetadata: track.technicalMetadata,
      segments: reverse
          ? [
              for (final s in segments.reversed)
                TrackSegment(userMetadata: s.userMetadata, locations: s.locations.reversed.toList()),
            ]
          : segments,
    );
  }

  @override
  void dispose() {
    _emitter.stop();
    super.dispose();
  }
}

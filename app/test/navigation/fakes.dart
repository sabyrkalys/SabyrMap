import 'dart:async';

import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/navigation/position/position_snapshot.dart';
import 'package:app/navigation/position/position_source.dart';
import 'package:app/navigation/signals/audio_signaler.dart';
import 'package:app/navigation/signals/signal_kind.dart';

/// Точка; [ele] — метры.
LandmarkLocation loc(double lat, double lon, {double? ele}) => LandmarkLocation(
  latitude: lat,
  longitude: lon,
  values: [if (ele != null) LocationValue(type: LocationValueType.elevation, value: (ele * 1000).round())],
);

PositionSnapshot at(double lat, double lon, {double? speed}) =>
    PositionSnapshot(location: LandmarkLocation(latitude: lat, longitude: lon), speedMps: speed);

/// Источник положения, которым управляет тест.
class FakePositionSource extends PositionSource {
  PositionSnapshot? current;
  final StreamController<PositionSnapshot> controller = StreamController.broadcast();
  int watchCalls = 0;

  @override
  Future<PositionSnapshot?> getCurrent() async => current;

  @override
  Stream<PositionSnapshot> watch({Duration interval = const Duration(seconds: 1)}) {
    watchCalls++;
    return controller.stream;
  }
}

/// Записывает поданные сигналы.
class RecordingSignaler extends AudioSignaler {
  final List<SignalKind> played = [];
  int stops = 0;

  @override
  Future<void> play(SignalKind kind) async => played.add(kind);

  @override
  Future<void> stop() async => stops++;
}

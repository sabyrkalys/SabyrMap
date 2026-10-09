import 'proximity_zone.dart';

/// Текущие зоны оповещений.
class ProximityAlertState {
  const ProximityAlertState({this.currentZones = const {}});

  /// id оповещения → зона.
  final Map<String, ProximityZone> currentZones;

  ProximityAlertState copyWith({Map<String, ProximityZone>? currentZones}) =>
      ProximityAlertState(currentZones: Map.unmodifiable(currentZones ?? this.currentZones));
}

import 'package:app/landmarks/models/landmark_location.dart';
import 'package:uuid/uuid.dart';

/// Оповещение о приближении к точке.
class ProximityAlert {
  const ProximityAlert({
    required this.id,
    required this.name,
    required this.center,
    required this.radiusMeters,
    this.repeatNotifications = false,
    this.setAsTarget = false,
    this.isActive = true,
  });

  /// Новое оповещение со случайным UUID.
  factory ProximityAlert.create({
    required String name,
    required LandmarkLocation center,
    required double radiusMeters,
    bool repeatNotifications = false,
    bool setAsTarget = false,
  }) => ProximityAlert(
    id: const Uuid().v4(),
    name: name,
    center: center,
    radiusMeters: radiusMeters,
    repeatNotifications: repeatNotifications,
    setAsTarget: setAsTarget,
  );

  final String id;
  final String name;
  final LandmarkLocation center;
  final double radiusMeters;

  /// Повторять сигнал, пока зона не сменится; нет — один раз при переходе.
  final bool repeatNotifications;

  /// Во внутренней зоне сделать центр целью.
  final bool setAsTarget;
  final bool isActive;

  ProximityAlert copyWith({
    String? name,
    LandmarkLocation? center,
    double? radiusMeters,
    bool? repeatNotifications,
    bool? setAsTarget,
    bool? isActive,
  }) => ProximityAlert(
    id: id,
    name: name ?? this.name,
    center: center ?? this.center,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    repeatNotifications: repeatNotifications ?? this.repeatNotifications,
    setAsTarget: setAsTarget ?? this.setAsTarget,
    isActive: isActive ?? this.isActive,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'lat': center.latitude,
    'lon': center.longitude,
    'radius': radiusMeters,
    'repeat': repeatNotifications,
    'target': setAsTarget,
    'active': isActive,
  };

  /// Из [toJson]; неверная запись — [FormatException].
  factory ProximityAlert.fromJson(Map<String, dynamic> json) {
    try {
      return ProximityAlert(
        id: json['id'] as String,
        name: json['name'] as String,
        center: LandmarkLocation(
          latitude: (json['lat'] as num).toDouble(),
          longitude: (json['lon'] as num).toDouble(),
        ),
        radiusMeters: (json['radius'] as num).toDouble(),
        repeatNotifications: json['repeat'] as bool? ?? false,
        setAsTarget: json['target'] as bool? ?? false,
        isActive: json['active'] as bool? ?? true,
      );
    } on TypeError catch (e) {
      throw FormatException('Invalid proximity alert: $e');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProximityAlert &&
      other.id == id &&
      other.name == name &&
      other.center == center &&
      other.radiusMeters == radiusMeters &&
      other.repeatNotifications == repeatNotifications &&
      other.setAsTarget == setAsTarget &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, name, center, radiusMeters, repeatNotifications, setAsTarget, isActive);
}

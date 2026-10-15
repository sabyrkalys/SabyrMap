import 'landmark_location.dart';
import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';

/// Круг (файл `.cir`): центр и радиус в метрах.
class CircleObject extends LandmarkObject {
  const CircleObject({
    required this.center,
    required this.radiusMeters,
    this.userMetadata = const LandmarkMetadata(),
    this.technicalMetadata = const LandmarkMetadata(),
  });

  final LandmarkLocation center;

  /// Радиус по земле, м; больше нуля.
  final double radiusMeters;

  @override
  final LandmarkMetadata userMetadata;

  @override
  final LandmarkMetadata technicalMetadata;

  @override
  LandmarkType get type => LandmarkType.circle;

  CircleObject copyWith({LandmarkLocation? center, double? radiusMeters}) => CircleObject(
    center: center ?? this.center,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    userMetadata: userMetadata,
    technicalMetadata: technicalMetadata,
  );

  @override
  CircleObject withUserMetadata(LandmarkMetadata userMetadata) => CircleObject(
    center: center,
    radiusMeters: radiusMeters,
    userMetadata: userMetadata,
    technicalMetadata: technicalMetadata,
  );

  @override
  CircleObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) => CircleObject(
    center: center,
    radiusMeters: radiusMeters,
    userMetadata: userMetadata,
    technicalMetadata: technicalMetadata,
  );

  @override
  bool operator ==(Object other) =>
      other is CircleObject &&
      other.center == center &&
      other.radiusMeters == radiusMeters &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata;

  @override
  int get hashCode => Object.hash(center, radiusMeters, userMetadata, technicalMetadata);
}

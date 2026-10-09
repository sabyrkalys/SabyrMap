import 'landmark_location.dart';
import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';

/// Одиночная путевая точка (файл `.wpt`) или точка внутри набора,
/// маршрута, трека.
///
/// Decision: у вложенных точек в файле хранятся только пользовательские
/// метаданные и координата, поэтому после чтения их [technicalMetadata]
/// пустые.
class WaypointObject extends LandmarkObject {
  const WaypointObject({
    required this.location,
    this.userMetadata = const LandmarkMetadata(),
    this.technicalMetadata = const LandmarkMetadata(),
  });

  final LandmarkLocation location;

  @override
  final LandmarkMetadata userMetadata;

  @override
  final LandmarkMetadata technicalMetadata;

  @override
  LandmarkType get type => LandmarkType.waypoint;

  @override
  WaypointObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) =>
      WaypointObject(location: location, userMetadata: userMetadata, technicalMetadata: technicalMetadata);

  @override
  bool operator ==(Object other) =>
      other is WaypointObject &&
      other.location == location &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata;

  @override
  int get hashCode => Object.hash(location, userMetadata, technicalMetadata);
}

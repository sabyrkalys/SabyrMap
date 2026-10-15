import 'landmark_object.dart';
import 'landmark_type.dart';

export 'landmark_area.dart';
export 'landmark_circle.dart';
export 'landmark_ldk.dart';
export 'landmark_location.dart';
export 'landmark_metadata.dart';
export 'landmark_object.dart';
export 'landmark_route.dart';
export 'landmark_set.dart';
export 'landmark_text.dart';
export 'landmark_track.dart';
export 'landmark_type.dart';
export 'landmark_waypoint.dart';

/// Содержимое одного файла метки.
///
/// [type] должен совпадать с `content.type`; кодек проверяет это при записи.
class LandmarkFile {
  const LandmarkFile({required this.type, required this.content});

  /// Файл с типом, взятым из содержимого.
  LandmarkFile.of(LandmarkObject content) : this(type: content.type, content: content);

  final LandmarkType type;
  final LandmarkObject content;

  LandmarkFile withContent(LandmarkObject content) => LandmarkFile(type: type, content: content);

  @override
  bool operator ==(Object other) => other is LandmarkFile && other.type == type && other.content == content;

  @override
  int get hashCode => Object.hash(type, content);

  @override
  String toString() => 'LandmarkFile($type, ${content.userMetadata.name})';
}

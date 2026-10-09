import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_waypoint.dart';

/// Правка объекта в режиме редактирования. Применяет
/// [EditModeController.execute].
sealed class EditCommand {
  const EditCommand();
}

/// Путевая точка набора, маршрута или трека; [atIndex] null — в конец.
class AddWaypointCommand extends EditCommand {
  const AddWaypointCommand({required this.waypoint, this.atIndex});
  final WaypointObject waypoint;
  final int? atIndex;
}

class RemoveWaypointCommand extends EditCommand {
  const RemoveWaypointCommand({required this.index});
  final int index;
}

class UpdateWaypointCommand extends EditCommand {
  const UpdateWaypointCommand({required this.index, required this.waypoint});
  final int index;
  final WaypointObject waypoint;
}

class ReorderWaypointsCommand extends EditCommand {
  const ReorderWaypointsCommand({required this.fromIndex, required this.toIndex});
  final int fromIndex;
  final int toIndex;
}

/// Точка трека; [atIndex] null — в конец сегмента.
class AddTrackLocationCommand extends EditCommand {
  const AddTrackLocationCommand({required this.segmentIndex, required this.location, this.atIndex});
  final int segmentIndex;
  final int? atIndex;
  final LandmarkLocation location;
}

class RemoveTrackLocationCommand extends EditCommand {
  const RemoveTrackLocationCommand({required this.segmentIndex, required this.index});
  final int segmentIndex;
  final int index;
}

class MoveTrackLocationCommand extends EditCommand {
  const MoveTrackLocationCommand({required this.segmentIndex, required this.index, required this.newLocation});
  final int segmentIndex;
  final int index;
  final LandmarkLocation newLocation;
}

class SplitTrackSegmentCommand extends EditCommand {
  const SplitTrackSegmentCommand({required this.segmentIndex, required this.locIndex});
  final int segmentIndex;
  final int locIndex;
}

class DeleteTrackSegmentCommand extends EditCommand {
  const DeleteTrackSegmentCommand({required this.segmentIndex});
  final int segmentIndex;
}

class MergeTrackSegmentsCommand extends EditCommand {
  const MergeTrackSegmentsCommand({required this.firstIndex, required this.secondIndex});
  final int firstIndex;
  final int secondIndex;
}

/// Точка контура области; [atIndex] null — в конец.
class AddAreaOutlinePointCommand extends EditCommand {
  const AddAreaOutlinePointCommand({required this.polygonIndex, required this.location, this.atIndex});
  final int polygonIndex;
  final int? atIndex;
  final LandmarkLocation location;
}

class RemoveAreaOutlinePointCommand extends EditCommand {
  const RemoveAreaOutlinePointCommand({required this.polygonIndex, required this.index});
  final int polygonIndex;
  final int index;
}

class MoveAreaOutlinePointCommand extends EditCommand {
  const MoveAreaOutlinePointCommand({required this.polygonIndex, required this.index, required this.newLocation});
  final int polygonIndex;
  final int index;
  final LandmarkLocation newLocation;
}

class AddHoleCommand extends EditCommand {
  const AddHoleCommand({required this.polygonIndex, required this.outline});
  final int polygonIndex;
  final List<LandmarkLocation> outline;
}

class RemoveHoleCommand extends EditCommand {
  const RemoveHoleCommand({required this.polygonIndex, required this.holeIndex});
  final int polygonIndex;
  final int holeIndex;
}

/// Пользовательские метаданные объекта (версия растёт при сохранении).
class UpdateMetadataCommand extends EditCommand {
  const UpdateMetadataCommand({required this.patch});
  final MetadataPatch patch;
}

class UpdateSegmentMetadataCommand extends EditCommand {
  const UpdateSegmentMetadataCommand({required this.segmentIndex, required this.patch});
  final int segmentIndex;
  final MetadataPatch patch;
}

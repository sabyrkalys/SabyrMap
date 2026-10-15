
import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'waypoint_color.dart';
import 'waypoint_models.dart';
import 'waypoint_types.dart';
import 'waypoints_repository.dart';

/// Путевые точки — файлы `.wpt` в папке меток на устройстве.
///
/// id точки — абсолютный путь файла. Поля приложения хранятся в
/// пользовательских метаданных: тип метки — `type`, заметка — `description`,
/// цвет — `color` (ARGB), комментарий и иконка из диалога — `comment` и
/// `icon`.
class FileWaypointsRepository implements WaypointsRepository {
  FileWaypointsRepository(this._services);

  final LandmarkServices _services;

  /// Ключ типа метки приложения в метаданных.
  static const String typeKey = 'type';

  /// Файл, которому принадлежит точка [id]: у точки из файла меток — сам
  /// `.ldk`, у отдельной точки — её `.wpt` ([LandmarkItem.fileOf]).
  static String fileOf(String id) => LandmarkItem.fileOf(id);

  /// Индекс меток: точки для карты берутся из него, без обхода диска.
  Listenable get changes => _services.index;

  /// Все точки из индекса меток (и внутри файлов меток — только для
  /// показа, [Waypoint.canEdit] false), по времени создания.
  @override
  Future<List<Waypoint>> list() async {
    final out = [for (final item in _services.index.byType(LandmarkType.waypoint)) fromItem(item)];
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  /// Точка карты из записи индекса.
  static Waypoint fromItem(LandmarkItem item) => Waypoint(
    id: item.path,
    orgId: '',
    ownerId: '',
    name: item.name,
    type: item.kind ?? defaultWaypointType,
    note: item.description,
    color: item.colorValue == null ? null : colorToHex(Color(item.colorValue!)),
    lat: item.latitude ?? 0,
    lng: item.longitude ?? 0,
    canEdit: !item.isNested,
    createdAt: DateTime.fromMillisecondsSinceEpoch(item.createdAt),
  );

  @override
  Future<Waypoint> create({
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
    String? folder,
    Map<String, Object> extra = const {},
  }) async {
    try {
      final path = await _services.creation.create(
        MarkerDraft(
          type: LandmarkType.waypoint,
          longitude: lng,
          latitude: lat,
          name: name,
          description: note,
          colorValue: _argb(color),
          targetFolder: folder,
          extraMetadata: {typeKey: type, ...extra},
        ),
      );
      return _fromIndex(path);
    } on ValidationException catch (e) {
      throw WaypointException(e.errors.join('; '));
    } on Exception catch (e) {
      throw WaypointException('Could not create waypoint: $e');
    }
  }

  @override
  Future<Waypoint> update(
    String id, {
    required String name,
    required String type,
    required String note,
    required String? color,
  }) async {
    try {
      await _services.waypoints.update(
        id,
        WaypointPatch(
          name: name,
          description: note,
          extra: {typeKey: type, LandmarkMetadata.colorKey: _argb(color)},
        ),
      );
      return _fromIndex(id);
    } on ValidationException catch (e) {
      throw WaypointException(e.errors.join('; '));
    } on Exception catch (e) {
      throw WaypointException('Could not update waypoint: $e');
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _services.waypoints.delete(id);
    } on Exception catch (e) {
      throw WaypointException('Could not delete waypoint: $e');
    }
  }

  /// Точка [path] из индекса: запись в файл его уже обновила.
  Waypoint _fromIndex(String path) {
    final item = _services.index.byPath(path);
    if (item == null) throw WaypointException('Waypoint is not in the index: $path');
    return fromItem(item);
  }

  /// `#RRGGBB` → непрозрачный ARGB; null — без своего цвета.
  static int? _argb(String? hex) => hex == null ? null : colorFromHex(hex).toARGB32();
}

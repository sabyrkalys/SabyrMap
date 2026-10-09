import 'dart:io';

import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

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

  /// Все точки папки меток с подпапками, по времени создания.
  @override
  Future<List<Waypoint>> list() async {
    final root = Directory(_services.repository.storage.paths.landmarks);
    if (!await root.exists()) return const [];
    final out = <Waypoint>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.wpt') continue;
      try {
        out.add(_toModel(entity.path, await _services.waypoints.load(entity.path)));
      } on Exception {
        // Чужой или повреждённый файл — в список не попадает.
      }
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

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
      return _toModel(path, await _services.waypoints.load(path));
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
      final updated = await _services.waypoints.update(
        id,
        WaypointPatch(
          name: name,
          description: note,
          extra: {typeKey: type, LandmarkMetadata.colorKey: _argb(color)},
        ),
      );
      return _toModel(id, updated);
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

  static Waypoint _toModel(String path, WaypointObject w) {
    final m = w.userMetadata;
    final type = m.entries[typeKey];
    final created = m.createdAtMs;
    return Waypoint(
      id: path,
      orgId: '',
      ownerId: '',
      name: m.name ?? p.basenameWithoutExtension(path),
      type: type is String && type.isNotEmpty ? type : defaultWaypointType,
      note: m.description,
      color: m.colorValue == null ? null : colorToHex(Color(m.colorValue!)),
      lat: w.location.latitude,
      lng: w.location.longitude,
      canEdit: true,
      createdAt: created == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.fromMillisecondsSinceEpoch(created),
    );
  }

  /// `#RRGGBB` → непрозрачный ARGB; null — без своего цвета.
  static int? _argb(String? hex) => hex == null ? null : colorFromHex(hex).toARGB32();
}

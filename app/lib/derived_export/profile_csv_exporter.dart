import 'dart:convert';
import 'dart:io';

import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/landmarks/composite/statistics/elevation_profile.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_track.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:csv/csv.dart';

/// Профиль трека в CSV `<основа>_profile.csv`: строка на точку,
/// `distance_m,elevation_m,lat,lon,time_ms`. Расстояние копится по
/// гаверсинусу; между сегментами не прибавляется. Нет высоты или времени —
/// пустая ячейка.
class ProfileCsvExporter {
  ProfileCsvExporter(this._paths, this._storage);

  final StoragePaths _paths;
  final StorageService _storage;

  static const List<String> header = ['distance_m', 'elevation_m', 'lat', 'lon', 'time_ms'];

  Future<String> export(TrackObject track, String targetFolder, {String? preferredFilename}) async {
    final rows = <List<String>>[header];
    var distance = 0.0;
    for (final segment in track.segments) {
      LandmarkLocation? previous;
      for (final l in segment.locations) {
        if (previous != null) distance += Haversine.distance(previous, l);
        previous = l;
        final ele = ElevationProfileBuilder.elevationOf(l);
        final time = l.valueOf(LocationValueType.utcTime)?.value;
        rows.add([
          distance.toStringAsFixed(1),
          ele == null ? '' : ele.toStringAsFixed(1),
          l.latitude.toStringAsFixed(7),
          l.longitude.toStringAsFixed(7),
          time is int ? '$time' : '',
        ]);
      }
    }
    final folder = targetFolder.isEmpty ? _paths.landmarks : targetFolder;
    await Directory(folder).create(recursive: true);
    final base = FileNaming.baseFromName(preferredFilename ?? track.userMetadata.name ?? '');
    final path = await FileNaming.resolveCollision(folder, '${base}_profile.csv');
    await _storage.atomicWriteBytes(path, utf8.encode(Csv(lineDelimiter: '\n').encode(rows)));
    return path;
  }
}

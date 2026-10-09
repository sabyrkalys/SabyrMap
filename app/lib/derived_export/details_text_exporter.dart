import 'dart:convert';
import 'dart:io';

import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/models/landmark_object.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';

import 'details_renderer.dart';

/// Сведения об объекте в текстовый файл `<основа>_details.txt` (UTF-8).
class DetailsTextExporter {
  DetailsTextExporter(
    this._paths,
    this._storage, {
    String Function()? locale,
    CompositeCalculator calculator = const CompositeCalculator(),
  }) : _locale = locale ?? _ru,
       _calculator = calculator;

  final StoragePaths _paths;
  final StorageService _storage;
  final String Function() _locale;
  final CompositeCalculator _calculator;

  static String _ru() => 'ru';

  /// Записывает файл в [targetFolder] (по умолчанию — `<корень>/landmarks`)
  /// и возвращает абсолютный путь.
  Future<String> export(LandmarkObject object, String targetFolder, {String? preferredFilename}) async {
    final text = DetailsRenderer.render(object, _calculator.forObject(object), locale: _locale());
    final folder = targetFolder.isEmpty ? _paths.landmarks : targetFolder;
    await Directory(folder).create(recursive: true);
    final base = FileNaming.baseFromName(preferredFilename ?? object.userMetadata.name ?? '');
    final path = await FileNaming.resolveCollision(folder, '${base}_details.txt');
    await _storage.atomicWriteBytes(path, utf8.encode(text));
    return path;
  }
}

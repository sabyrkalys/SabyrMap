import 'dart:typed_data';

import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/export/export_options_schema.dart';
import 'package:app/landmarks/models/landmark_object.dart';

import 'import_adapter.dart';

/// Запись объектов меток в файл одного формата.
abstract class ExportAdapter {
  const ExportAdapter();

  String get formatId;
  ExportOptionsSchema get optionsSchema;

  /// Все [objects] в одном файле.
  ///
  /// Decision: принимает список, а не один объект — экспорт нескольких
  /// объектов в один файл (multiObjectPerFile) иначе невозможен.
  Future<Uint8List> serialize(List<LandmarkObject> objects, ExportOptions options, {WarningSink? onWarning});

  /// Расширение файла (без точки) при этих опциях.
  String extensionFor(ExportOptions options);
}

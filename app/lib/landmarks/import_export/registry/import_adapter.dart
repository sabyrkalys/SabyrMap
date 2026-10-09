import 'dart:typed_data';

import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/import/import_options_schema.dart';
import 'package:app/landmarks/models/landmark_object.dart';

/// Обработчик предупреждений адаптера (объект пропущен, опция не
/// поддерживается...).
typedef WarningSink = void Function(String warning);

/// Чтение файла одного формата в объекты меток.
abstract class ImportAdapter {
  const ImportAdapter();

  String get formatId;
  ImportOptionsSchema get optionsSchema;

  /// Объекты из [bytes]. Файл, который нельзя разобрать целиком, —
  /// [FormatException]; отдельный неразборчивый объект пропускается с
  /// сообщением в [onWarning].
  ///
  /// Decision: [onWarning] добавлен к описанной сигнатуре — иначе
  /// предупреждения о пропущенных объектах не дойти до [ImportResult].
  Future<List<LandmarkObject>> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning});
}

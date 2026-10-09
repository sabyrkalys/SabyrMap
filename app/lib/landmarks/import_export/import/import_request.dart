import 'dart:typed_data';

import 'package:app/landmarks/import_export/registry/format_descriptor.dart';

import 'import_options.dart';

/// Что импортировать и куда.
class ImportRequest {
  const ImportRequest({
    required this.bytes,
    required this.sourcePath,
    required this.format,
    required this.targetFolder,
    this.options = const ImportOptions(),
  });

  /// Содержимое исходного файла (сам файл не меняется).
  final Uint8List bytes;
  final String sourcePath;
  final FormatDescriptor format;
  final ImportOptions options;

  /// Папка для новых файлов, если в [options] не задана своя.
  final String targetFolder;
}

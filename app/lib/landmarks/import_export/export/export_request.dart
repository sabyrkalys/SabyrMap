import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/models/landmark_object.dart';

import 'export_options.dart';

/// Что экспортировать и куда.
class ExportRequest {
  const ExportRequest({
    required this.objects,
    required this.format,
    required this.targetFolder,
    this.options = const ExportOptions(),
    this.preferredFilename,
  });

  final List<LandmarkObject> objects;
  final FormatDescriptor format;
  final ExportOptions options;
  final String targetFolder;

  /// Имя файла; без расширения — оно добавляется. null — из имени объекта.
  final String? preferredFilename;
}

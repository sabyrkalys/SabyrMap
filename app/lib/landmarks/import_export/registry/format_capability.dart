import 'package:app/landmarks/models/landmark_type.dart';

/// Что умеет формат файлов.
enum FormatCapability {
  importWaypoint,
  importSet,
  importRoute,
  importTrack,
  importArea,
  exportWaypoint,
  exportSet,
  exportRoute,
  exportTrack,
  exportArea,
  hasOptions,
  requiresCharset,
  supportsAttachments,
  supportsStyle,
  multiObjectPerFile;

  /// Возможность импортировать объекты типа [type]. null — у типа нет
  /// своей возможности: файл меток — контейнер, переносятся его объекты;
  /// у круга и текста соответствия в GPX/KML/CSV нет — форматы их пропускают.
  static FormatCapability? importOf(LandmarkType type) => switch (type) {
    LandmarkType.waypoint => importWaypoint,
    LandmarkType.set => importSet,
    LandmarkType.route => importRoute,
    LandmarkType.track => importTrack,
    LandmarkType.area => importArea,
    LandmarkType.ldkFile || LandmarkType.circle || LandmarkType.text => null,
  };

  /// Возможность экспортировать объекты типа [type]; null — см. [importOf].
  static FormatCapability? exportOf(LandmarkType type) => switch (type) {
    LandmarkType.waypoint => exportWaypoint,
    LandmarkType.set => exportSet,
    LandmarkType.route => exportRoute,
    LandmarkType.track => exportTrack,
    LandmarkType.area => exportArea,
    LandmarkType.ldkFile || LandmarkType.circle || LandmarkType.text => null,
  };
}

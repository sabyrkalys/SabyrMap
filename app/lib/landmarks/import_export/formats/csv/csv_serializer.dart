import 'dart:typed_data';

import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/import_export/utils/charset_detector.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:csv/csv.dart';

/// Запись CSV/TSV: путевая точка — строка, трек — по строке на точку
/// (name — имя трека, segment — номер сегмента). Остальные типы
/// пропускаются с предупреждением.
class CsvSerializer {
  const CsvSerializer();

  static const String separator = 'separator';
  static const String headersInFirstRow = 'headersInFirstRow';
  static const String columns = 'columns';

  /// Опция: формат времени `iso` или `unix` (мс).
  static const String timeFormat = 'timeFormat';

  /// Все колонки, которые умеет писать сериализатор.
  static const List<String> knownColumns = [
    'name',
    'latitude',
    'longitude',
    'elevation',
    'time',
    'comment',
    'accuracy',
    'segment',
  ];

  static const List<String> defaultColumns = ['name', 'latitude', 'longitude', 'elevation', 'time', 'comment'];

  Uint8List serialize(List<LandmarkObject> objects, ExportOptions options, {WarningSink? onWarning}) {
    final cols = [
      for (final c in options.extra<List<Object?>>(columns, defaultColumns))
        if (knownColumns.contains('$c'.toLowerCase())) '$c'.toLowerCase() else ?_unknown('$c', onWarning),
    ];
    final unix = options.extra<String>(timeFormat, 'iso') == 'unix';
    final sep = switch (options.extra<String>(separator, ',')) {
      'tab' || '\\t' => '\t',
      final s => s,
    };

    String value(String column, LandmarkLocation l, LandmarkMetadata m, int? segment) {
      switch (column) {
        case 'name':
          return m.name ?? '';
        case 'latitude':
          return _n(l.latitude);
        case 'longitude':
          return _n(l.longitude);
        case 'elevation':
          final e = FormatSupport.elevationOf(l);
          return e == null ? '' : _n(e);
        case 'time':
          final t = FormatSupport.timeOf(l);
          return t == null ? '' : (unix ? '$t' : FormatSupport.isoTime(t));
        case 'comment':
          return m.comment ?? m.description ?? '';
        case 'accuracy':
          final a = FormatSupport.accuracyOf(l);
          return a == null ? '' : _n(a);
        case 'segment':
          return segment == null ? '' : '$segment';
      }
      return '';
    }

    final rows = <List<String>>[
      if (options.extra(headersInFirstRow, true)) cols,
    ];
    for (final o in objects) {
      switch (o) {
        case WaypointObject():
          rows.add([for (final c in cols) value(c, o.location, o.userMetadata, null)]);
        case TrackObject():
          for (final (s, segment) in o.segments.indexed) {
            for (final l in segment.locations) {
              rows.add([for (final c in cols) value(c, l, o.userMetadata, options.includeSegments ? s : 0)]);
            }
          }
          if (options.includeWaypoints) {
            for (final w in o.waypoints) {
              rows.add([for (final c in cols) value(c, w.location, w.userMetadata, null)]);
            }
          }
        default:
          onWarning?.call('CSV export does not support ${o.type.extension} objects; skipped');
      }
    }
    final text = Csv(fieldDelimiter: sep, lineDelimiter: '\n').encode(rows);
    return CharsetDetector.encode(text.endsWith('\n') ? text : '$text\n', charset: options.charset);
  }

  static String? _unknown(String column, WarningSink? onWarning) {
    onWarning?.call('Unknown CSV column "$column" skipped');
    return null;
  }

  static String _n(double v) => v.toStringAsFixed(7).replaceFirst(RegExp(r'\.?0+$'), '');
}

import 'dart:typed_data';

import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/import_export/utils/charset_detector.dart';
import 'package:app/landmarks/import_export/utils/coord_parser.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:csv/csv.dart';

/// Разбор CSV/TSV: строка — точка.
///
/// Колонки: latitude, longitude (или одна coordinates), elevation, time,
/// name, comment, accuracy. Заголовки узнаются по-английски без учёта
/// регистра, с синонимами (lat, lon, lng, ele, alt...).
class CsvParser {
  const CsvParser();

  /// Опция: разделитель `,` `;` `\t` или `auto`.
  static const String separator = 'separator';

  /// Опция: первая строка — заголовки.
  static const String headersInFirstRow = 'headersInFirstRow';

  /// Опция: порядок колонок, если заголовков нет.
  static const String columns = 'columns';

  /// Опция: что создавать — `auto`, `waypoints`, `track`.
  static const String importAs = 'importAs';

  /// Колонки по умолчанию для файла без заголовков.
  static const List<String> defaultColumns = ['latitude', 'longitude', 'elevation', 'time', 'name', 'comment'];

  static const Map<String, String> _aliases = {
    'lat': 'latitude',
    'latitude': 'latitude',
    'широта': 'latitude',
    'lon': 'longitude',
    'lng': 'longitude',
    'long': 'longitude',
    'longitude': 'longitude',
    'долгота': 'longitude',
    'ele': 'elevation',
    'elevation': 'elevation',
    'alt': 'elevation',
    'altitude': 'elevation',
    'высота': 'elevation',
    'time': 'time',
    'timestamp': 'time',
    'date': 'time',
    'datetime': 'time',
    'время': 'time',
    'name': 'name',
    'title': 'name',
    'имя': 'name',
    'название': 'name',
    'comment': 'comment',
    'cmt': 'comment',
    'description': 'comment',
    'desc': 'comment',
    'комментарий': 'comment',
    'accuracy': 'accuracy',
    'hdop': 'accuracy',
    'точность': 'accuracy',
    'coordinates': 'coordinates',
    'coords': 'coordinates',
    'coordinate': 'coordinates',
    'position': 'coordinates',
    'координаты': 'coordinates',
  };

  /// Decision: при `importAs` = `auto` файл с колонкой name даёт путевые
  /// точки, без неё — один трек.
  List<LandmarkObject> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning}) {
    final text = CharsetDetector.decode(bytes, charset: options.charset);
    if (text.trim().isEmpty) return const [];
    final sep = _separator(options.extra<String>(separator, 'auto'), text);
    final rows = Csv(fieldDelimiter: sep, autoDetect: false, lineDelimiter: '\n').decode(text);
    if (rows.isEmpty) return const [];

    final hasHeaders = options.extra(headersInFirstRow, true);
    final names = hasHeaders
        ? [for (final h in rows.first) _aliases[h.toString().trim().toLowerCase()] ?? h.toString().trim().toLowerCase()]
        : options.extra<List<Object?>>(columns, defaultColumns).map((c) => '$c'.toLowerCase()).toList();
    final hasPair = names.contains('latitude') && names.contains('longitude');
    if (!hasPair && !names.contains('coordinates')) {
      throw const FormatException('CSV needs a coordinates column or latitude and longitude columns');
    }

    final mode = options.extra<String>(importAs, 'auto');
    final asTrack = mode == 'track' || (mode == 'auto' && !names.contains('name'));
    final waypoints = <WaypointObject>[];
    final locations = <LandmarkLocation>[];
    final dataRows = hasHeaders ? rows.skip(1) : rows;
    for (final (i, row) in dataRows.indexed) {
      final line = i + (hasHeaders ? 2 : 1);
      String? cell(String column) {
        final index = names.indexOf(column);
        if (index < 0 || index >= row.length) return null;
        final v = row[index].toString().trim();
        return v.isEmpty ? null : v;
      }

      try {
        final (lat, lon) = hasPair
            ? (
                CoordParser.parseValue(cell('latitude') ?? '', isLatitude: true),
                CoordParser.parseValue(cell('longitude') ?? '', isLatitude: false),
              )
            : CoordParser.parse(cell('coordinates') ?? '');
        final location = FormatSupport.location(
          lat,
          lon,
          elevation: _number(cell('elevation')),
          timeMs: _time(cell('time')),
          accuracyMeters: _number(cell('accuracy')),
          options: options,
        );
        if (asTrack) {
          locations.add(location);
        } else {
          waypoints.add(
            WaypointObject(
              location: location,
              userMetadata: FormatSupport.metadata(name: cell('name'), comment: cell('comment')),
            ),
          );
        }
      } on FormatException catch (e) {
        onWarning?.call('Line $line: ${e.message}, skipped');
      } on UnsupportedError catch (e) {
        onWarning?.call('Line $line: ${e.message}, skipped');
      }
    }
    if (asTrack) {
      return locations.isEmpty ? const [] : [TrackObject(segments: [TrackSegment(locations: locations)])];
    }
    return waypoints;
  }

  /// `auto`: табуляция, если она есть в первой строке; иначе `;`, если их
  /// больше, чем запятых; иначе `,`.
  static String _separator(String option, String text) {
    if (option == '\\t' || option == 'tab') return '\t';
    if (option != 'auto') return option;
    final first = text.split('\n').first;
    if (first.contains('\t')) return '\t';
    return ';'.allMatches(first).length > ','.allMatches(first).length ? ';' : ',';
  }

  static double? _number(String? v) => v == null ? null : double.tryParse(v.replaceAll(',', '.'));

  /// ISO 8601 или число (Unix ms; меньше 1e11 — секунды).
  static int? _time(String? v) {
    if (v == null) return null;
    final n = num.tryParse(v);
    if (n != null) return n.abs() < 1e11 ? (n * 1000).round() : n.round();
    return FormatSupport.parseIsoTime(v);
  }
}

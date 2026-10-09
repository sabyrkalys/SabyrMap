import 'package:app/landmarks/composite/statistics/composite_statistics.dart';
import 'package:app/landmarks/composite/statistics/elevation_profile.dart';
import 'package:app/landmarks/models/landmark_file.dart';

/// Текстовые сведения об объекте. Подписи на русском (`ru`) или английском
/// (`en`); язык — из общих настроек.
///
/// Decision: в Dart нет перегрузки, поэтому по методу на тип и общий
/// [render].
abstract final class DetailsRenderer {
  static String renderTrack(TrackObject track, CompositeStatistics stats, {String locale = 'ru'}) {
    final l = _Labels.of(locale);
    final points = track.segments.fold(0, (n, s) => n + s.locations.length);
    final times = [
      for (final s in track.segments)
        for (final p in s.locations) ?_time(p),
    ];
    return _doc(l, l.track, track.userMetadata, [
      _section(l.statistics, [
        (l.length, _distance(stats.totalLengthMeters)),
        (l.segments, '${track.segments.length}'),
        (l.points, '$points'),
        (l.waypoints, '${track.waypoints.length}'),
        if (stats.durationMs != null) (l.duration, _duration(stats.durationMs!)),
      ]),
      _elevation(l, stats),
      if (stats.durationMs != null && stats.durationMs! > 0)
        _section(l.speeds, [(l.averageSpeed, _speed(stats.totalLengthMeters / (stats.durationMs! / 1000)))]),
      if (times.isNotEmpty)
        _section(l.events, [(l.start, _date(times.first)), (l.finish, _date(times.last))]),
    ]);
  }

  static String renderRoute(RouteObject route, CompositeStatistics stats, {String locale = 'ru'}) {
    final l = _Labels.of(locale);
    return _doc(l, l.route, route.userMetadata, [
      _section(l.statistics, [(l.length, _distance(stats.totalLengthMeters)), (l.points, '${route.waypoints.length}')]),
      _elevation(l, stats),
    ]);
  }

  static String renderSet(SetObject set, CompositeStatistics stats, {String locale = 'ru'}) {
    final l = _Labels.of(locale);
    return _doc(l, l.set, set.userMetadata, [
      _section(l.statistics, [(l.points, '${set.waypoints.length}'), (l.length, _distance(stats.totalLengthMeters))]),
    ]);
  }

  static String renderArea(AreaObject area, CompositeStatistics stats, {String locale = 'ru'}) {
    final l = _Labels.of(locale);
    return _doc(l, l.areaKind, area.userMetadata, [
      _section(l.statistics, [
        (l.area, _area(stats.areaSquareMeters ?? 0)),
        (l.perimeter, _distance(stats.perimeterMeters ?? stats.totalLengthMeters)),
        (l.polygons, '${area.polygons.length}'),
      ]),
    ]);
  }

  static String renderWaypoint(WaypointObject wp, {String locale = 'ru'}) {
    final l = _Labels.of(locale);
    final loc = wp.location;
    final ele = ElevationProfileBuilder.elevationOf(loc);
    return _doc(l, l.waypoint, wp.userMetadata, [
      _section(l.position, [
        (l.latitude, loc.latitude.toStringAsFixed(6)),
        (l.longitude, loc.longitude.toStringAsFixed(6)),
        if (ele != null) (l.elevation, '${ele.toStringAsFixed(1)} m'),
      ]),
    ]);
  }

  /// Любой объект; статистика нужна составным.
  static String render(LandmarkObject object, CompositeStatistics stats, {String locale = 'ru'}) => switch (object) {
    WaypointObject o => renderWaypoint(o, locale: locale),
    TrackObject o => renderTrack(o, stats, locale: locale),
    RouteObject o => renderRoute(o, stats, locale: locale),
    SetObject o => renderSet(o, stats, locale: locale),
    AreaObject o => renderArea(o, stats, locale: locale),
    _ => throw ArgumentError('Unsupported object ${object.runtimeType}'),
  };

  static String _doc(_Labels l, String kind, LandmarkMetadata m, List<String?> sections) {
    final b = StringBuffer()
      ..writeln(m.name ?? l.untitled)
      ..writeln(kind);
    final created = m.createdAtMs;
    if (created != null) b.writeln('${l.date}: ${_date(created)}');
    if (m.description != null) b.writeln(m.description);
    if (m.comment != null) b.writeln(m.comment);
    for (final s in sections) {
      if (s == null) continue;
      b
        ..writeln()
        ..write(s);
    }
    return b.toString();
  }

  static String? _elevation(_Labels l, CompositeStatistics s) => s.minElevationMeters == null
      ? null
      : _section(l.elevations, [
          (l.minimum, '${s.minElevationMeters!.toStringAsFixed(0)} m'),
          (l.maximum, '${s.maxElevationMeters!.toStringAsFixed(0)} m'),
          (l.gain, '${s.elevationGainMeters.toStringAsFixed(0)} m'),
          (l.loss, '${s.elevationLossMeters.toStringAsFixed(0)} m'),
        ]);

  static String _section(String title, List<(String, String)> rows) {
    final b = StringBuffer()..writeln(title);
    for (final (k, v) in rows) {
      b.writeln('  $k: $v');
    }
    return b.toString();
  }

  static int? _time(LandmarkLocation l) => switch (l.valueOf(LocationValueType.utcTime)?.value) {
    final int t => t,
    _ => null,
  };

  static String _distance(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.toStringAsFixed(0)} m';
  static String _area(double m2) =>
      m2 >= 1e6 ? '${(m2 / 1e6).toStringAsFixed(3)} km²' : '${m2.toStringAsFixed(0)} m²';
  static String _speed(double mps) => '${(mps * 3.6).toStringAsFixed(1)} km/h';

  static String _duration(int ms) {
    final d = Duration(milliseconds: ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  static String _date(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} UTC';
  }
}

class _Labels {
  const _Labels({
    required this.track,
    required this.route,
    required this.set,
    required this.areaKind,
    required this.waypoint,
    required this.untitled,
    required this.date,
    required this.statistics,
    required this.length,
    required this.segments,
    required this.points,
    required this.waypoints,
    required this.duration,
    required this.elevations,
    required this.minimum,
    required this.maximum,
    required this.gain,
    required this.loss,
    required this.speeds,
    required this.averageSpeed,
    required this.events,
    required this.start,
    required this.finish,
    required this.area,
    required this.perimeter,
    required this.polygons,
    required this.position,
    required this.latitude,
    required this.longitude,
    required this.elevation,
  });

  static _Labels of(String locale) => locale == 'en' ? _en : _ru;

  static const _ru = _Labels(
    track: 'Трек',
    route: 'Маршрут',
    set: 'Набор точек',
    areaKind: 'Область',
    waypoint: 'Путевая точка',
    untitled: 'Без названия',
    date: 'Дата',
    statistics: 'Статистика',
    length: 'Длина',
    segments: 'Сегменты',
    points: 'Точки',
    waypoints: 'Путевые точки',
    duration: 'Длительность',
    elevations: 'Высоты',
    minimum: 'Минимум',
    maximum: 'Максимум',
    gain: 'Набор',
    loss: 'Сброс',
    speeds: 'Скорости',
    averageSpeed: 'Средняя',
    events: 'События',
    start: 'Начало',
    finish: 'Конец',
    area: 'Площадь',
    perimeter: 'Периметр',
    polygons: 'Многоугольники',
    position: 'Положение',
    latitude: 'Широта',
    longitude: 'Долгота',
    elevation: 'Высота',
  );

  static const _en = _Labels(
    track: 'Track',
    route: 'Route',
    set: 'Waypoint set',
    areaKind: 'Area',
    waypoint: 'Waypoint',
    untitled: 'Untitled',
    date: 'Date',
    statistics: 'Statistics',
    length: 'Length',
    segments: 'Segments',
    points: 'Points',
    waypoints: 'Waypoints',
    duration: 'Duration',
    elevations: 'Elevation',
    minimum: 'Minimum',
    maximum: 'Maximum',
    gain: 'Gain',
    loss: 'Loss',
    speeds: 'Speed',
    averageSpeed: 'Average',
    events: 'Events',
    start: 'Start',
    finish: 'Finish',
    area: 'Area',
    perimeter: 'Perimeter',
    polygons: 'Polygons',
    position: 'Position',
    latitude: 'Latitude',
    longitude: 'Longitude',
    elevation: 'Elevation',
  );

  final String track, route, set, areaKind, waypoint, untitled, date, statistics, length, segments, points;
  final String waypoints, duration, elevations, minimum, maximum, gain, loss, speeds, averageSpeed, events;
  final String start, finish, area, perimeter, polygons, position, latitude, longitude, elevation;
}

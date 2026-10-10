import 'package:app/landmarks/composite/distance/bearing.dart';
import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/composite/statistics/elevation_profile.dart';
import 'package:app/landmarks/composite/statistics/energy_estimate.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../map/map_focus.dart';
import '../../map/sk42.dart';
import '../../waypoints/waypoint_dialog/coords_system.dart';
import '../details/landmark_details_format.dart';
import '../details/landmark_geometry.dart';
import '../details/landmark_previews.dart';
import '../item_menu/item_menu_entries.dart';
import '../section_menu/section_context_menu.dart';
import '../sheet_menu.dart';
import 'context_menu_action.dart';
import 'context_menu_section.dart';
import 'detail_field.dart';
import 'detail_section.dart';
import 'landmark_type_descriptor.dart';

/// Дескрипторы шести типов меток.
///
/// Decision: наборы пунктов для точки, маршрута и области и секции их
/// детализации взяты из постановки «по аналогии» — их уточнят по
/// скриншотам, меняя только этот файл.
abstract final class TypeDescriptors {
  static const int _accent = 0xFF00A38E;

  /// В порядке секций списка.
  static List<LandmarkTypeDescriptor> all() => [waypoint, set, route, track, area, ldkFile];

  // ── Общие части ──────────────────────────────────────────────────────

  /// Меню элемента: базовые, буфер, выбор, «Изменить».
  static List<ContextMenuSection> _itemMenu(
    LandmarkItem item, {
    required List<ContextMenuAction> base,
    required List<ContextMenuAction> edit,
  }) => [
    ContextMenuSection(actions: base),
    ContextMenuSection(
      title: 'Буфер обмена',
      actions: [ItemMenuEntries.copy(item), ItemMenuEntries.cut(item)],
    ),
    ContextMenuSection(title: 'Мультивыбор', actions: [ItemMenuEntries.select(item)]),
    ContextMenuSection(title: 'Изменить', actions: edit),
  ];

  static DetailSection _fileSection() => DetailSection(
    title: 'ФАЙЛ',
    fields: [
      DetailField(label: 'Имя', valueResolver: (d) => d.item.name),
      DetailField(label: 'Папка', valueResolver: (d) => d.folder, isMultiline: true),
      DetailField(label: 'Размер', valueResolver: (d) => d.sizeBytes == null ? '—' : DetailsFormat.size(d.sizeBytes!)),
      DetailField(label: 'Дата', valueResolver: (d) => d.modified == null ? '—' : DetailsFormat.dateTime(d.modified!)),
    ],
  );

  static String _orDash(double? v, String Function(double) format) => v == null ? '—' : format(v);

  /// Список строк для своего тела секции.
  static Widget _rows(List<(String, String)> rows, {String empty = 'Нет данных'}) => rows.isEmpty
      ? Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(empty, style: const TextStyle(fontSize: 13, color: SheetMenuColors.secondary)),
        )
      : Column(
          children: [
            for (final (title, subtitle) in rows)
              ListTile(
                dense: true,
                title: Text(title, style: const TextStyle(fontSize: 14, color: SheetMenuColors.text)),
                subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: SheetMenuColors.secondary)),
              ),
          ],
        );

  /// Точки набора: тап — карта на точке.
  static Widget _pointsBody(BuildContext context, List<WaypointObject> points) => points.isEmpty
      ? _rows(const [], empty: 'Точек нет')
      : Column(
          children: [
            for (final (i, w) in points.indexed)
              ListTile(
                key: Key('details_point_$i'),
                dense: true,
                leading: const Icon(Icons.location_on_outlined, color: Color(_accent)),
                title: Text(w.userMetadata.name ?? 'Точка ${i + 1}'),
                subtitle: Text(
                  '${formatLatitude(w.location.latitude)}  ${formatLongitude(w.location.longitude)}',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  ProviderScope.containerOf(
                    context,
                    listen: false,
                  ).read(mapFocusProvider.notifier).focus(LatLng(w.location.latitude, w.location.longitude));
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
          ],
        );

  /// «N элем.» и суммы длины и подъёма: «2 элем. 34,6 км +399 м».
  static String _trackSubtitle(List<LandmarkItem> items) {
    final length = items.fold<double>(0, (sum, i) => sum + (i.lengthMeters ?? 0));
    final gain = items.fold<double>(0, (sum, i) => sum + (i.elevationGainMeters ?? 0));
    final km = (length / 1000).toStringAsFixed(1).replaceAll('.', ',');
    return '${items.length} элем. $km км +${gain.round()} м';
  }

  // ── Путевая точка ────────────────────────────────────────────────────

  static final LandmarkTypeDescriptor waypoint = LandmarkTypeDescriptor(
    type: LandmarkType.waypoint,
    displayName: 'Путевая точка',
    sectionTitle: 'ПУТЕВЫЕ ТОЧКИ',
    icon: Icons.location_on_sharp,
    iconColor: _accent,
    buildItemMenu: (context, item) => _itemMenu(
      item,
      base: [
        ItemMenuEntries.details(item),
        ItemMenuEntries.display(item),
        ItemMenuEntries.setTarget(item),
        ItemMenuEntries.share(item),
        ItemMenuEntries.export(item),
      ],
      edit: [ItemMenuEntries.color(item), ItemMenuEntries.properties(item), ItemMenuEntries.delete(item)],
    ),
    buildSectionMenu: (context) => SectionMenuEntries.build(
      LandmarkType.waypoint,
      exportName: 'путевые_точки',
      sorts: [...SectionMenuEntries.byName, ...SectionMenuEntries.byDate, ...SectionMenuEntries.byDistance],
    ),
    buildDetailsSections: (context, data) {
      final location = switch (data.object) {
        final WaypointObject o => o.location,
        _ => null,
      };
      final lat = location?.latitude ?? data.item.latitude;
      final lon = location?.longitude ?? data.item.longitude;
      final sk = lat == null || lon == null ? null : toSk42(lat, lon);
      final elevation = location == null ? null : ElevationProfileBuilder.elevationOf(location);
      return [
        _fileSection(),
        DetailSection(
          title: 'КООРДИНАТЫ',
          fields: [
            DetailField(label: 'X', valueResolver: (_) => sk == null ? '—' : '${sk.x.round()}'),
            DetailField(label: 'Y', valueResolver: (_) => sk == null ? '—' : '${sk.y.round()}'),
            DetailField(label: 'Широта', valueResolver: (_) => lat == null ? '—' : formatLatitude(lat)),
            DetailField(label: 'Долгота', valueResolver: (_) => lon == null ? '—' : formatLongitude(lon)),
            DetailField(label: 'Высота', valueResolver: (_) => _orDash(elevation, DetailsFormat.elevation)),
          ],
        ),
        DetailSection(
          title: 'АВТОР И ВРЕМЯ',
          fields: [
            DetailField(label: 'Дата создания', valueResolver: (d) => DetailsFormat.dateTimeMs(d.item.createdAt)),
            DetailField(label: 'Дата изменения', valueResolver: (d) => DetailsFormat.dateTimeMs(d.item.updatedAt)),
          ],
        ),
      ];
    },
  );

  // ── Набор точек ──────────────────────────────────────────────────────

  static final LandmarkTypeDescriptor set = LandmarkTypeDescriptor(
    type: LandmarkType.set,
    displayName: 'Набор точек',
    sectionTitle: 'НАБОРЫ ТОЧЕК',
    icon: Icons.share_location_sharp,
    iconColor: _accent,
    buildItemMenu: (context, item) => _itemMenu(
      item,
      base: [
        ItemMenuEntries.details(item),
        ItemMenuEntries.display(item),
        ItemMenuEntries.stub(item, id: 'auto_target', label: 'Автомат. цель — ближ. точка', icon: Icons.near_me_outlined),
        ItemMenuEntries.share(item),
        ItemMenuEntries.export(item),
      ],
      edit: [
        ItemMenuEntries.color(item),
        ItemMenuEntries.properties(item),
        ItemMenuEntries.stub(
          item,
          id: 'ungroup',
          label: 'Разгруппировать точки',
          icon: Icons.scatter_plot_outlined,
          iconColor: MenuColors.edit,
        ),
        ItemMenuEntries.delete(item),
      ],
    ),
    buildSectionMenu: (context) => SectionMenuEntries.build(
      LandmarkType.set,
      exportName: 'наборы_точек',
      sorts: [...SectionMenuEntries.byName, ...SectionMenuEntries.byDate],
    ),
    buildDetailsSections: (context, data) {
      final points = switch (data.object) {
        final SetObject o => o.waypoints,
        _ => const <WaypointObject>[],
      };
      return [
        _fileSection(),
        DetailSection(
          title: 'СТАТИСТИКА',
          fields: [
            DetailField(label: 'Количество точек', valueResolver: (_) => '${points.length}'),
            DetailField(
              label: 'Длина',
              valueResolver: (d) => _orDash(d.stats?.totalLengthMeters, DetailsFormat.distance),
            ),
          ],
        ),
        DetailSection(title: 'ТОЧКИ', customBody: (context, _) => _pointsBody(context, points)),
      ];
    },
  );

  // ── Маршрут ──────────────────────────────────────────────────────────

  /// Скорость для оценки времени в пути по маршруту, м/с (4 км/ч пешком).
  static const double walkingSpeedMps = 4 / 3.6;

  static final LandmarkTypeDescriptor route = LandmarkTypeDescriptor(
    type: LandmarkType.route,
    displayName: 'Маршрут',
    sectionTitle: 'МАРШРУТЫ',
    icon: Icons.route_sharp,
    iconColor: _accent,
    buildItemMenu: (context, item) => _itemMenu(
      item,
      base: [
        ItemMenuEntries.details(item),
        ItemMenuEntries.display(item),
        ItemMenuEntries.stub(item, id: 'follow_route', label: 'Движение по маршруту', icon: Icons.directions_walk),
        ItemMenuEntries.reverseRoute(item),
        ItemMenuEntries.share(item),
        ItemMenuEntries.export(item),
        ItemMenuEntries.stub(item, id: 'convert', label: 'Конвертировать в...', icon: Icons.transform),
      ],
      edit: [ItemMenuEntries.color(item), ItemMenuEntries.properties(item), ItemMenuEntries.delete(item)],
    ),
    buildSectionMenu: (context) => SectionMenuEntries.build(
      LandmarkType.route,
      exportName: 'маршруты',
      sorts: [...SectionMenuEntries.byName, ...SectionMenuEntries.byDate, ...SectionMenuEntries.byDistance],
    ),
    buildDetailsHeader: (context, data) => GeometryPreview(
      points: LandmarkGeometry.pointsOf(data.object),
      color: Color(data.item.colorValue | 0xFF000000),
    ),
    buildDetailsSections: (context, data) {
      final points = switch (data.object) {
        final RouteObject o => o.waypoints,
        _ => const <WaypointObject>[],
      };
      String nameOf(int i) => points[i].userMetadata.name ?? '${i + 1}';
      final legs = [
        for (var i = 0; i + 1 < points.length; i++)
          (
            '${nameOf(i)} → ${nameOf(i + 1)}',
            '${DetailsFormat.distance(Haversine.distance(points[i].location, points[i + 1].location))} · '
                'азимут ${DetailsFormat.azimuth(Bearing.fromTo(points[i].location, points[i + 1].location))}',
          ),
      ];
      return [
        _fileSection(),
        DetailSection(
          title: 'СТАТИСТИКА',
          fields: [
            DetailField(label: 'Количество точек', valueResolver: (_) => '${points.length}'),
            DetailField(
              label: 'Длина',
              valueResolver: (d) => _orDash(d.stats?.totalLengthMeters, DetailsFormat.distance),
            ),
            DetailField(
              label: 'В пути (4 км/ч)',
              valueResolver: (d) => d.stats == null
                  ? '—'
                  : DetailsFormat.duration((d.stats!.totalLengthMeters / walkingSpeedMps * 1000).round()),
            ),
          ],
        ),
        DetailSection(title: 'ПЛЕЧИ', customBody: (_, _) => _rows(legs, empty: 'Плеч нет')),
      ];
    },
  );

  // ── Трек (путь) ──────────────────────────────────────────────────────

  static final LandmarkTypeDescriptor track = LandmarkTypeDescriptor(
    type: LandmarkType.track,
    displayName: 'Путь',
    sectionTitle: 'ТРЕКИ',
    icon: Icons.polyline_sharp,
    iconColor: _accent,
    buildSectionSubtitle: _trackSubtitle,
    buildItemMenu: (context, item) => _itemMenu(
      item,
      base: [
        ItemMenuEntries.details(item),
        ItemMenuEntries.display(item),
        ItemMenuEntries.stub(item, id: 'follow_track', label: 'Движение по треку', icon: Icons.directions_walk),
        ItemMenuEntries.stub(item, id: 'dynamic_profile', label: 'Динамический профиль', icon: Icons.area_chart_outlined),
        ItemMenuEntries.share(item),
        ItemMenuEntries.export(item),
        ItemMenuEntries.stub(item, id: 'convert', label: 'Конвертировать в...', icon: Icons.transform),
      ],
      edit: [
        ItemMenuEntries.color(item),
        ItemMenuEntries.properties(item),
        ItemMenuEntries.stub(
          item,
          id: 'edit_profile',
          label: 'Изменить профиль',
          icon: Icons.show_chart,
          iconColor: MenuColors.edit,
        ),
        ItemMenuEntries.delete(item),
      ],
    ),
    buildSectionMenu: (context) => SectionMenuEntries.build(
      LandmarkType.track,
      exportName: 'треки',
      extraEdit: [SectionMenuEntries.stub(LandmarkType.track, id: 'group_all', label: 'Сгруппировать все', icon: Icons.merge)],
      sorts: [...SectionMenuEntries.byName, ...SectionMenuEntries.byDate, ...SectionMenuEntries.byDistance],
      statisticsSorts: SectionMenuEntries.trackStatistics,
    ),
    buildDetailsHeader: (context, data) => ElevationProfilePreview(
      locations: [
        if (data.object case final TrackObject o)
          for (final s in o.segments) ...s.locations,
      ],
    ),
    buildDetailsSections: (context, data) {
      final track = switch (data.object) {
        final TrackObject o => o,
        _ => null,
      };
      final stats = data.stats;
      final speed = stats?.durationMs == null || stats!.durationMs! <= 0
          ? null
          : stats.totalLengthMeters / (stats.durationMs! / 1000);
      final segments = [
        for (final (i, s) in (track?.segments ?? const <TrackSegment>[]).indexed)
          (
            s.userMetadata.name ?? 'Сегмент ${i + 1}',
            '${s.locations.length} точ. · ${DetailsFormat.distance(_lengthOf(s.locations))}',
          ),
      ];
      final events = [
        for (final w in track?.waypoints ?? const <WaypointObject>[])
          (w.userMetadata.name ?? 'Точка', '${formatLatitude(w.location.latitude)}  ${formatLongitude(w.location.longitude)}'),
        if (stats?.maxElevationMeters case final max?) ('Наибольшая высота', DetailsFormat.elevation(max)),
        if (stats?.minElevationMeters case final min?) ('Наименьшая высота', DetailsFormat.elevation(min)),
      ];
      return [
        _fileSection(),
        DetailSection(
          title: 'СТАТИСТИКА',
          fields: [
            DetailField(label: 'Длина', valueResolver: (_) => _orDash(stats?.totalLengthMeters, DetailsFormat.distance)),
            DetailField(
              label: 'Продолжительность',
              valueResolver: (_) => stats?.durationMs == null ? '—' : DetailsFormat.duration(stats!.durationMs!),
            ),
            DetailField(label: 'Подъём', valueResolver: (_) => _orDash(stats?.elevationGainMeters, DetailsFormat.elevation)),
            DetailField(label: 'Спуск', valueResolver: (_) => _orDash(stats?.elevationLossMeters, DetailsFormat.elevation)),
            DetailField(
              label: 'Мин/Макс высота',
              valueResolver: (_) => stats?.minElevationMeters == null || stats?.maxElevationMeters == null
                  ? '—'
                  : '${DetailsFormat.elevation(stats!.minElevationMeters!)} / ${DetailsFormat.elevation(stats.maxElevationMeters!)}',
            ),
            DetailField(label: 'Средняя скорость', valueResolver: (_) => _orDash(speed, DetailsFormat.speed)),
            DetailField(
              label: 'Калории',
              valueResolver: (_) => stats == null
                  ? '—'
                  : '≈ ${EnergyEstimate.kcal(stats.totalLengthMeters, gainMeters: stats.elevationGainMeters).round()} ккал',
            ),
          ],
        ),
        DetailSection(title: 'СЕГМЕНТЫ', customBody: (_, _) => _rows(segments, empty: 'Сегментов нет')),
        DetailSection(title: 'СОБЫТИЯ', customBody: (_, _) => _rows(events, empty: 'Событий нет')),
      ];
    },
  );

  static double _lengthOf(List<LandmarkLocation> locations) {
    var sum = 0.0;
    for (var i = 1; i < locations.length; i++) {
      sum += Haversine.distance(locations[i - 1], locations[i]);
    }
    return sum;
  }

  // ── Область ──────────────────────────────────────────────────────────

  static final LandmarkTypeDescriptor area = LandmarkTypeDescriptor(
    type: LandmarkType.area,
    displayName: 'Область',
    sectionTitle: 'ОБЛАСТИ',
    icon: Icons.pentagon_outlined,
    iconColor: _accent,
    buildItemMenu: (context, item) => _itemMenu(
      item,
      base: [
        ItemMenuEntries.details(item),
        ItemMenuEntries.display(item),
        ItemMenuEntries.stub(item, id: 'area_tools', label: 'Инструменты области', icon: Icons.handyman_outlined),
        ItemMenuEntries.share(item),
        ItemMenuEntries.export(item),
      ],
      edit: [
        ItemMenuEntries.color(item),
        ItemMenuEntries.properties(item),
        ItemMenuEntries.toggleClosed(item),
        ItemMenuEntries.delete(item),
      ],
    ),
    buildSectionMenu: (context) => SectionMenuEntries.build(
      LandmarkType.area,
      exportName: 'области',
      sorts: [
        ...SectionMenuEntries.byName,
        ...SectionMenuEntries.byDate,
        ...SectionMenuEntries.byDistance,
        ...SectionMenuEntries.byArea,
      ],
    ),
    buildDetailsHeader: (context, data) => GeometryPreview(
      points: LandmarkGeometry.pointsOf(data.object),
      color: Color(data.item.colorValue | 0xFF000000),
      closed: switch (data.object) {
        final AreaObject o => CompositeCalculator.isClosed(o),
        _ => true,
      },
    ),
    buildDetailsSections: (context, data) => [
      _fileSection(),
      DetailSection(
        title: 'СТАТИСТИКА',
        fields: [
          DetailField(label: 'Площадь', valueResolver: (d) => _orDash(d.stats?.areaSquareMeters, DetailsFormat.area)),
          DetailField(label: 'Периметр', valueResolver: (d) => _orDash(d.stats?.perimeterMeters, DetailsFormat.distance)),
        ],
      ),
    ],
  );

  // ── Файл меток ───────────────────────────────────────────────────────

  static final LandmarkTypeDescriptor ldkFile = LandmarkTypeDescriptor(
    type: LandmarkType.ldkFile,
    displayName: 'Файл меток',
    sectionTitle: 'ФАЙЛЫ МЕТОК',
    icon: Icons.description_outlined,
    iconColor: 0xFF333333,
    hasLocation: false,
    defaultViewMode: SectionViewMode.preview,
    buildItemMenu: (context, item) => _itemMenu(
      item,
      base: [
        ItemMenuEntries.open(item),
        ItemMenuEntries.display(item),
        ItemMenuEntries.share(item),
        ItemMenuEntries.export(item),
      ],
      edit: [ItemMenuEntries.rename(item), ItemMenuEntries.properties(item), ItemMenuEntries.delete(item)],
    ),
    buildSectionMenu: (context) => SectionMenuEntries.build(
      LandmarkType.ldkFile,
      exportName: 'файлы_меток',
      defaultViewMode: SectionViewMode.preview,
      sorts: [...SectionMenuEntries.byName, ...SectionMenuEntries.byDate],
    ),
    buildDetailsSections: (context, data) => [
      _fileSection(),
      DetailSection(
        title: 'СОДЕРЖИМОЕ',
        customBody: (_, _) => _rows(const [], empty: 'Файл пока не содержит объектов'),
      ),
    ],
  );
}

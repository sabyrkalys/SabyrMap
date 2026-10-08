import 'package:flutter/material.dart';

/// Which section of the «Новая метка» sheet a type is listed in.
enum MarkerCategory { local, tool }

/// One row of the «Новая метка» sheet.
class MarkerType {
  const MarkerType({required this.id, required this.title, this.subtitle, required this.icon, required this.category});

  final String id;
  final String title;

  /// Explanation under the title, if any.
  final String? subtitle;
  final IconData icon;
  final MarkerCategory category;
}

/// Ids the map screen acts on; the other types are not implemented yet.
abstract final class MarkerTypeIds {
  static const waypoint = 'waypoint';
}

/// Everything the sheet lists, in display order. Material Icons in their
/// sharp variant, the family of the app's own icons (Material Symbols Sharp).
const List<MarkerType> markerTypes = [
  MarkerType(
    id: MarkerTypeIds.waypoint,
    title: 'Путевая точка',
    subtitle: 'Создать путевую точку на карте.',
    icon: Icons.location_on_sharp,
    category: MarkerCategory.local,
  ),
  MarkerType(id: 'photo', title: 'Фототочка', icon: Icons.photo_camera_sharp, category: MarkerCategory.local),
  MarkerType(id: 'audio', title: 'Аудиоточка', icon: Icons.volume_up_sharp, category: MarkerCategory.local),
  MarkerType(
    id: 'waypoint_set',
    title: 'Набор точек',
    subtitle: 'Создать набор путевых точек на карте.',
    icon: Icons.share_location_sharp,
    category: MarkerCategory.local,
  ),
  MarkerType(
    id: 'route',
    title: 'Маршрут',
    subtitle: 'Проложить маршрут на карте по заданным точкам.',
    icon: Icons.route_sharp,
    category: MarkerCategory.local,
  ),
  MarkerType(
    id: 'path',
    title: 'Путь',
    subtitle: 'Начертить путь на карте.',
    icon: Icons.polyline_sharp,
    category: MarkerCategory.local,
  ),
  MarkerType(
    id: 'area',
    title: 'Область',
    subtitle: 'Начертить область на карте.',
    icon: Icons.pentagon_outlined,
    category: MarkerCategory.local,
  ),
  MarkerType(
    id: 'circle',
    title: 'Круг',
    subtitle: 'Создать круговую область с заданным радиусом.',
    icon: Icons.radio_button_unchecked_sharp,
    category: MarkerCategory.local,
  ),
  MarkerType(
    id: 'text',
    title: 'Текст',
    subtitle: 'Добавить текст на карту.',
    icon: Icons.title_sharp,
    category: MarkerCategory.local,
  ),
  MarkerType(
    id: 'map_search',
    title: 'Поиск на карте',
    subtitle: 'Искать названия, координаты и прочее.',
    icon: Icons.search_sharp,
    category: MarkerCategory.tool,
  ),
  MarkerType(id: 'name_search', title: 'Поиск по имени', icon: Icons.abc_sharp, category: MarkerCategory.tool),
  MarkerType(
    id: 'project_location',
    title: 'Спроектировать местоположение',
    icon: Icons.how_to_reg_sharp,
    category: MarkerCategory.tool,
  ),
  MarkerType(
    id: 'auto_routing',
    title: 'Автомаршрутизация',
    subtitle: 'Проложить маршрут по дорогам на карте в автоматическом режиме.',
    icon: Icons.alt_route_sharp,
    category: MarkerCategory.tool,
  ),
  MarkerType(id: 'fast_routing', title: 'Быстрая маршрутизация', icon: Icons.bolt_sharp, category: MarkerCategory.tool),
  MarkerType(
    id: 'measure',
    title: 'Измерение',
    subtitle: 'Измерить расстояние и азимут между точками.',
    icon: Icons.straighten_sharp,
    category: MarkerCategory.tool,
  ),
  MarkerType(
    id: 'slope',
    title: 'Уклон',
    subtitle: 'Рассчитать уклоны между точками.',
    icon: Icons.trending_up_sharp,
    category: MarkerCategory.tool,
  ),
  MarkerType(
    id: 'proximity_alert',
    title: 'Оповещение о сближении',
    subtitle: 'Получать звуковые уведомления о приближении к этому месту.',
    icon: Icons.notifications_active_sharp,
    category: MarkerCategory.tool,
  ),
];

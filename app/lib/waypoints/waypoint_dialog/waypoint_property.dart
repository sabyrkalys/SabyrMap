import 'package:flutter/material.dart';

/// What the «Ещё...» sheet can add to a waypoint.
enum WaypointPropertyType { icon, style, image, gallery, audio, course, website, keywords, description, comment }

/// One row of the «Ещё...» sheet.
class WaypointProperty {
  const WaypointProperty({required this.type, required this.title, required this.icon});

  final WaypointPropertyType type;
  final String title;
  final IconData icon;
}

/// The «Ещё...» rows, in order. Комментарий is not among them: the pencil
/// in the dialog opens it.
const List<WaypointProperty> waypointProperties = [
  WaypointProperty(type: WaypointPropertyType.icon, title: 'Иконка', icon: Icons.flag_sharp),
  WaypointProperty(type: WaypointPropertyType.style, title: 'Стиль', icon: Icons.text_fields_sharp),
  WaypointProperty(type: WaypointPropertyType.image, title: 'Изображение', icon: Icons.photo_camera_sharp),
  WaypointProperty(type: WaypointPropertyType.gallery, title: 'Галерея', icon: Icons.photo_library_sharp),
  WaypointProperty(type: WaypointPropertyType.audio, title: 'Аудио', icon: Icons.volume_up_sharp),
  WaypointProperty(type: WaypointPropertyType.course, title: 'Курс', icon: Icons.explore_sharp),
  WaypointProperty(type: WaypointPropertyType.website, title: 'Сайт', icon: Icons.link_sharp),
  WaypointProperty(type: WaypointPropertyType.keywords, title: 'Ключевые слова', icon: Icons.local_offer_sharp),
  WaypointProperty(type: WaypointPropertyType.description, title: 'Описание', icon: Icons.article_sharp),
];

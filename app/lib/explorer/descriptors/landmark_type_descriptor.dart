import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/widgets.dart';

import 'context_menu_section.dart';
import 'detail_data.dart';
import 'detail_section.dart';

/// Режим показа секции в списке.
enum SectionViewMode {
  /// Компактные строки.
  list,

  /// Карточки со значком.
  preview,
}

/// Всё о типе метки для проводника: подписи, меню элемента и секции,
/// секции детализации.
class LandmarkTypeDescriptor {
  const LandmarkTypeDescriptor({
    required this.type,
    required this.displayName,
    required this.sectionTitle,
    required this.icon,
    required this.iconColor,
    required this.buildItemMenu,
    required this.buildSectionMenu,
    required this.buildDetailsSections,
    this.buildDetailsHeader,
    this.buildSectionSubtitle,
    this.hasLocation = true,
    this.defaultViewMode = SectionViewMode.list,
  });

  final LandmarkType type;

  /// Вид одного элемента: «Путь», «Набор точек».
  final String displayName;

  /// Заголовок секции в списке: «ТРЕКИ».
  final String sectionTitle;
  final IconData icon;

  /// ARGB.
  final int iconColor;

  final List<ContextMenuSection> Function(BuildContext context, LandmarkItem item) buildItemMenu;
  final List<ContextMenuSection> Function(BuildContext context) buildSectionMenu;
  final List<DetailSection> Function(BuildContext context, LandmarkDetailsData data) buildDetailsSections;

  /// Шапка детализации над секциями (профиль, контур); null — без шапки.
  final Widget? Function(BuildContext context, LandmarkDetailsData data)? buildDetailsHeader;

  /// Подпись под заголовком секции; null — «N элем.».
  final String Function(List<LandmarkItem> items)? buildSectionSubtitle;

  /// У объектов есть координаты («ЦЕНТРИРОВАТЬ»).
  final bool hasLocation;
  final SectionViewMode defaultViewMode;

  /// Ключ секции в настройках.
  String get sectionId => type.extension;

  /// Заголовок шторки секции: «Треки».
  String get sectionMenuTitle =>
      sectionTitle.isEmpty ? '' : sectionTitle[0] + sectionTitle.substring(1).toLowerCase();

  /// «N элем.» или своя подпись.
  String subtitleFor(List<LandmarkItem> items) => buildSectionSubtitle?.call(items) ?? '${items.length} элем.';
}

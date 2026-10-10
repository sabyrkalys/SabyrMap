import 'package:app/landmarks/explorer/listing/sort_options.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/landmark_services_provider.dart';
import '../../dialogs/confirm_dialog.dart';
import '../context_menu_sheet.dart';
import '../descriptors/context_menu_action.dart';
import '../descriptors/context_menu_section.dart';
import '../descriptors/descriptor_registry.dart';
import '../descriptors/landmark_type_descriptor.dart';
import '../descriptors/menu_env.dart';
import '../dialogs/color_picker_sheet.dart';
import '../export/landmark_export_flow.dart';
import '../item_menu/item_actions.dart';
import '../item_menu/item_menu_entries.dart';
import 'section_actions.dart';

/// Меню секции списка (⋮ у заголовка) — из дескриптора типа.
abstract final class SectionContextMenu {
  static Future<void> show(BuildContext context, LandmarkType type) {
    final container = ProviderScope.containerOf(context, listen: false);
    final descriptor = container.read(descriptorRegistryProvider).of(type);
    return ContextMenuSheet.show(
      context,
      key: const Key('section_context_menu'),
      title: descriptor.sectionMenuTitle,
      sections: descriptor.buildSectionMenu(context),
      env: MenuEnv(services: container.read(landmarkServicesProvider)),
      keyPrefix: 'section_menu',
    );
  }
}

/// Пункт сортировки секции.
typedef SectionSort = ({String id, String label, SortOptions sort});

/// Пункты меню секции: общий каркас и варианты сортировки.
abstract final class SectionMenuEntries {
  static LandmarkServices _s(BuildContext c) => ItemMenuEntries.services(c);

  static const List<SectionSort> byName = [
    (id: 'sort_name_asc', label: 'Имя (a-z)', sort: SortOptions(field: SortField.name)),
    (
      id: 'sort_name_desc',
      label: 'Имя (z-a)',
      sort: SortOptions(field: SortField.name, direction: SortDirection.descending),
    ),
  ];

  static const List<SectionSort> byDate = [
    (id: 'sort_date_asc', label: 'Дата (1-9)', sort: SortOptions(field: SortField.date)),
    (
      id: 'sort_date_desc',
      label: 'Дата (9-1)',
      sort: SortOptions(field: SortField.date, direction: SortDirection.descending),
    ),
  ];

  static List<SectionSort> pair(String id, String label, SortField field) => [
    (id: 'sort_${id}_asc', label: '$label (1-9)', sort: SortOptions(field: field)),
    (
      id: 'sort_${id}_desc',
      label: '$label (9-1)',
      sort: SortOptions(field: field, direction: SortDirection.descending),
    ),
  ];

  static final List<SectionSort> byDistance = pair(
    'distance',
    'Расстояние от центра экрана',
    SortField.distanceFromScreenCenter,
  );
  static final List<SectionSort> byArea = pair('area', 'Площадь', SortField.area);

  /// «СОРТИРОВАТЬ ПО (СТАТИСТИКА)» треков.
  static final List<SectionSort> trackStatistics = [
    ...pair('length', 'Длина', SortField.length),
    ...pair('elevation', 'Высота', SortField.maxElevation),
    ...pair('gain', 'Подъём', SortField.elevationGain),
    ...pair('slope', 'Средние уклоны', SortField.slope),
    ...pair('duration', 'Продолжительность', SortField.duration),
    ...pair('speed', 'Скорость', SortField.speed),
    ...pair('calories', 'Калории', SortField.calories),
  ];

  /// Меню секции [type]: базовые пункты, буфер, «Изменить» ([extraEdit] —
  /// пункты типа перед общими), режим показа, выбор, сортировка.
  /// [exportName] — имя файла экспорта всей секции.
  static List<ContextMenuSection> build(
    LandmarkType type, {
    List<ContextMenuAction> extraEdit = const [],
    required List<SectionSort> sorts,
    List<SectionSort> statisticsSorts = const [],
    required String exportName,
    SectionViewMode defaultViewMode = SectionViewMode.list,
  }) => [
    ContextMenuSection(
      actions: [
        _action('show_all', 'Показать все', Icons.visibility_outlined, MenuColors.base, (c) async {
          ItemMenuEntries.say(c, SectionActions.showAll(_s(c), type));
        }),
        _action('hide_all', 'Убрать все', Icons.visibility_off_outlined, MenuColors.base, (c) async {
          ItemMenuEntries.say(c, SectionActions.hideAll(_s(c), type));
        }),
        _action('export', 'Экспортировать как...', Icons.file_download_outlined, MenuColors.base, (c) async {
          final paths = SectionActions.pathsOf(_s(c), type).toList();
          if (paths.isEmpty) return ItemMenuEntries.say(c, 'В секции нет файлов');
          await LandmarkExportFlow.startMany(c, paths, name: exportName);
        }),
      ],
    ),
    ContextMenuSection(
      title: 'Буфер обмена',
      actions: [
        _action('copy_all', 'Копировать все', Icons.copy_outlined, MenuColors.clipboard, (c) async {
          final s = _s(c);
          final text = await SectionActions.copyAll(s, type);
          if (c.mounted) ItemMenuEntries.say(c, text);
          await s.explorerController.refresh();
        }),
        _action('cut_all', 'Вырезать все', Icons.content_cut, MenuColors.clipboard, (c) async {
          final s = _s(c);
          final text = await SectionActions.cutAll(s, type);
          if (c.mounted) ItemMenuEntries.say(c, text);
          await s.explorerController.refresh();
        }),
      ],
    ),
    ContextMenuSection(
      title: 'Изменить',
      actions: [
        ...extraEdit,
        _action('properties', 'Изменить свойства', Icons.edit_outlined, MenuColors.edit, (c) async {
          final s = _s(c);
          final color = await ColorPickerSheet.show(c);
          if (color == null || !c.mounted) return;
          final text = await SectionActions.setColorAll(s, type, color);
          if (!c.mounted) return;
          ItemMenuEntries.say(c, text);
          await ItemMenuEntries.changed(c);
        }),
        _action('delete_all', 'Удалить все', Icons.delete_outline, MenuColors.edit, (c) async {
          final s = _s(c);
          final count = SectionActions.pathsOf(s, type).length;
          final ok = await showConfirmDialog(
            c,
            title: 'Удалить все ($count)?',
            message: 'Файлы секции будут удалены без возможности восстановления.',
            confirmLabel: 'Удалить',
            cancelLabel: 'Отмена',
          );
          if (!ok || !c.mounted) return;
          final text = await SectionActions.deleteAll(s, type);
          if (!c.mounted) return;
          ItemMenuEntries.say(c, text);
          await ItemMenuEntries.changed(c);
        }),
      ],
    ),
    ContextMenuSection(
      title: 'Режим отображения',
      isRadio: true,
      actions: [
        for (final (mode, label) in [(SectionViewMode.list, 'Список'), (SectionViewMode.preview, 'Предварительный просмотр')])
          ContextMenuAction(
            id: 'view_${mode.name}',
            label: label,
            icon: Icons.view_list,
            iconColor: MenuColors.select,
            isSelected: (env) {
              final s = (env as MenuEnv).services;
              final saved = s.settings.getString(SectionActions.viewModeKey(type));
              return (saved ?? defaultViewMode.name) == mode.name;
            },
            onTap: (c) async {
              final s = _s(c);
              await SectionActions.setViewMode(s, type, mode);
              await s.explorerController.refresh();
            },
          ),
      ],
    ),
    ContextMenuSection(
      title: 'Мультивыбор',
      actions: [
        _action('select_all', 'Выбрать все', Icons.check_box, MenuColors.select, (c) async {
          SectionActions.selectAll(_s(c), type);
        }),
        _action('clear_selection', 'Отменить все', Icons.check_box_outline_blank, MenuColors.select, (c) async {
          SectionActions.clearSelection(_s(c));
        }),
      ],
    ),
    _sortSection('Сортировать по', type, sorts),
    if (statisticsSorts.isNotEmpty) _sortSection('Сортировать по (статистика)', type, statisticsSorts),
  ];

  /// Пункт без реализации у секции.
  static ContextMenuAction stub(LandmarkType type, {required String id, required String label, required IconData icon}) =>
      _action(id, label, icon, MenuColors.edit, (c) async {
        ItemMenuEntries.say(c, ItemActions.stub(label, type.extension));
      });

  static ContextMenuSection _sortSection(String title, LandmarkType type, List<SectionSort> sorts) => ContextMenuSection(
    title: title,
    isRadio: true,
    keepsOpen: true,
    actions: [
      for (final option in sorts)
        ContextMenuAction(
          id: option.id,
          label: option.label,
          icon: Icons.sort,
          iconColor: MenuColors.select,
          isSelected: (env) => SectionActions.effectiveSort((env as MenuEnv).services, type) == option.sort,
          onTap: (c) async {
            final s = _s(c);
            await SectionActions.setSort(s, type, option.sort);
            await s.explorerController.refresh();
          },
        ),
    ],
  );

  static ContextMenuAction _action(
    String id,
    String label,
    IconData icon,
    int color,
    Future<void> Function(BuildContext) onTap,
  ) => ContextMenuAction(id: id, label: label, icon: icon, iconColor: color, onTap: onTap);
}

import 'dart:io';
import 'dart:math';

import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/on_screen/on_screen_registry.dart';
import 'package:app/landmarks/on_screen/on_screen_saver.dart';
import 'package:app/landmarks/on_screen/on_screen_sort.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../app/landmark_services_provider.dart';
import '../dialogs/confirm_dialog.dart';
import '../map/map_crosshair.dart';
import '../map/screens/layers_panel.dart' show onScreenPanelBackground;
import 'context_menu_sheet.dart';
import 'descriptors/context_menu_action.dart';
import 'descriptors/context_menu_section.dart';
import 'details/landmark_details_format.dart';
import 'details/landmark_details_screen.dart';
import 'item_menu/item_context_menu.dart';
import 'item_menu/item_hooks.dart';
import 'item_menu/item_menu_entries.dart' show MenuColors;
import 'item_row.dart';
import 'ldk/ldk_create_dialog.dart';
import '../waypoints/waypoints_controller.dart';

/// «Метки на экране»: все метки, что сейчас на экране — новые и
/// загруженные попадают сюда сами. Глаз прячет метку на карте, оставляя её
/// в списке; «Убрать все» снимает метки с экрана (файлы не трогаются).
class OnScreenLandmarksPanel extends ConsumerStatefulWidget {
  const OnScreenLandmarksPanel({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black12,
    builder: (_) => const OnScreenLandmarksPanel(),
  );

  /// Все файлы меток папки меток (с подпапками), что на экране.
  static Future<List<LandmarkItem>> loadItems(LandmarkServices services, OnScreenRegistry onScreen) async {
    final root = Directory(services.paths.landmarks);
    if (!await root.exists()) return const [];
    final paths = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          LandmarkType.fromExtension(p.extension(entity.path)) != null &&
          onScreen.isOnScreen(entity.path)) {
        paths.add(entity.path);
      }
    }
    final reader = LandmarkItemReader(services.storage);
    return (await Future.wait(paths.map(reader.read))).whereType<LandmarkItem>().toList();
  }

  @override
  ConsumerState<OnScreenLandmarksPanel> createState() => _OnScreenLandmarksPanelState();
}

class _OnScreenLandmarksPanelState extends ConsumerState<OnScreenLandmarksPanel> {
  static const Color _ink = Color(0xFF333333);
  static const Color _faded = Color(0xFF9E9E9E);

  late final LandmarkServices _services = ref.read(landmarkServicesProvider);
  late final OnScreenRegistry _onScreen = ref.read(onScreenRegistryProvider);
  late OnScreenSort _sort =
      OnScreenSort.decode(_services.settings.getString(SettingsKeys.onScreenSort)) ?? const OnScreenSort();
  List<LandmarkItem>? _items;

  /// Контекст под [ItemHooks]: меню метки находит хуки в нём.
  BuildContext? _hooksContext;

  @override
  void initState() {
    super.initState();
    _onScreen.addListener(_onRegistry);
    _reload();
  }

  @override
  void dispose() {
    _onScreen.removeListener(_onRegistry);
    super.dispose();
  }

  void _onRegistry() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final items = await OnScreenLandmarksPanel.loadItems(_services, _onScreen);
    if (mounted) setState(() => _items = items);
  }

  ({double latitude, double longitude})? get _center {
    final c = ref.read(mapCrosshairProvider);
    return c == null ? null : (latitude: c.latitude, longitude: c.longitude);
  }

  Future<void> _openDetails(String path) async {
    await LandmarkDetailsScreen.open(context, path);
    await _reload();
  }

  Future<void> _openMenu(LandmarkItem item) async {
    await ItemContextMenu.show(_hooksContext ?? context, item);
    await _reload();
  }

  Future<void> _removeAll() async {
    final items = _items ?? const <LandmarkItem>[];
    if (items.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Убрать все',
      message: 'Вы уверены?',
      confirmLabel: 'ДА',
      cancelLabel: 'НЕТ',
    );
    if (!ok) return;
    _onScreen.removeAll(items.map((i) => i.path));
    await _reload();
  }

  /// «Сохранить все»: метки на экране — в один файл меток (.ldk).
  Future<void> _saveAll() async {
    final paths = [for (final i in _items ?? const <LandmarkItem>[]) i.path];
    if (paths.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final props = await LdkCreateDialog.show(context);
    if (props == null) return;
    try {
      final path = await OnScreenSaver.saveAll(
        _services,
        paths,
        name: props.name,
        comment: props.comment,
        description: props.description,
      );
      await _services.explorerController.refresh();
      // Точки нового файла — на карту.
      await ref.read(waypointsControllerProvider.notifier).loadWaypoints();
      messenger.showSnackBar(
        SnackBar(content: Text('Сохранено в ${ref.read(markerGroupFoldersProvider).display(path)}')),
      );
      await _reload();
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
    }
  }

  void _openAllMarkers() {
    final navigator = Navigator.of(context);
    final open = ref.read(allMarkersOpenerProvider);
    navigator.pop();
    open(navigator.context);
  }

  void _setSort(OnScreenSort sort) {
    setState(() => _sort = sort);
    _services.settings.setString(SettingsKeys.onScreenSort, sort.encode());
  }

  Future<void> _openSectionMenu() {
    final paths = [for (final i in _items ?? const <LandmarkItem>[]) i.path];
    final anyVisible = paths.any(_onScreen.isVisible);
    final anyHidden = paths.any((path) => !_onScreen.isVisible(path));
    ContextMenuAction sortAction(String id, String label, OnScreenSort sort) => ContextMenuAction(
      id: id,
      label: label,
      icon: Icons.sort,
      iconColor: MenuColors.select,
      isSelected: (_) => _sort == sort,
      onTap: (_) async => _setSort(sort),
    );
    List<ContextMenuAction> pair(String id, String label, OnScreenSortField field, {bool alpha = false}) => [
      sortAction('sort_${id}_asc', '$label ${alpha ? '(a-z)' : '(1-9)'}', OnScreenSort(field: field)),
      sortAction(
        'sort_${id}_desc',
        '$label ${alpha ? '(z-a)' : '(9-1)'}',
        OnScreenSort(field: field, ascending: false),
      ),
    ];
    return ContextMenuSheet.show(
      context,
      key: const Key('on_screen_section_menu'),
      title: 'Метки',
      keyPrefix: 'on_screen_menu',
      env: this,
      sections: [
        ContextMenuSection(
          actions: [
            ContextMenuAction(
              id: 'save_all',
              label: 'Сохранить все',
              icon: Icons.save,
              iconColor: MenuColors.base,
              isEnabled: (_) => paths.isNotEmpty,
              onTap: (_) => _saveAll(),
            ),
            ContextMenuAction(
              id: 'remove_all',
              label: 'Убрать все',
              icon: Icons.playlist_remove,
              iconColor: MenuColors.base,
              isEnabled: (_) => paths.isNotEmpty,
              onTap: (_) => _removeAll(),
            ),
          ],
        ),
        // Только то, что изменит состояние: все видны — «Скрыть все», все
        // скрыты — «Показать все», часть скрыта — оба.
        if (anyHidden || anyVisible)
          ContextMenuSection(
            title: 'Показать',
            actions: [
              if (anyHidden)
                ContextMenuAction(
                  id: 'show_all',
                  label: 'Показать все',
                  icon: Icons.visibility,
                  iconColor: MenuColors.select,
                  onTap: (_) async => _onScreen.showAll(paths),
                ),
              if (anyVisible)
                ContextMenuAction(
                  id: 'hide_all',
                  label: 'Скрыть все',
                  icon: Icons.visibility_off_outlined,
                  iconColor: MenuColors.select,
                  onTap: (_) async => _onScreen.hideAll(paths),
                ),
            ],
          ),
        ContextMenuSection(
          title: 'Сортировать по',
          isRadio: true,
          actions: [
            ...pair('type', 'Тип', OnScreenSortField.type, alpha: true),
            ...pair('name', 'Имя', OnScreenSortField.name, alpha: true),
            ...pair('date', 'Дата', OnScreenSortField.date),
            ...pair('distance', 'Расстояние от центра экрана', OnScreenSortField.distance),
            ...pair('altitude', 'Высота', OnScreenSortField.altitude),
            ...pair('icon', 'Иконка', OnScreenSortField.icon),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _center;
    final items = _items == null ? null : _sort.apply(_items!, center: center);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      child: Container(
        decoration: const BoxDecoration(
          color: onScreenPanelBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 12)],
        ),
        child: SafeArea(
          top: false,
          child: ItemHooks(
            onOpen: _openDetails,
            onDeleted: _reload,
            onRenamed: (_) => _reload(),
            child: Builder(
              builder: (hooksContext) {
                _hooksContext = hooksContext;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      _sectionHeader(items?.length),
                      Flexible(
                        child: items == null
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : items.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'На экране нет меток',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _faded),
                                ),
                              )
                            : ListView(shrinkWrap: true, children: [for (final item in items) _row(item, center)]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      const Icon(Icons.view_list, size: 24, color: _ink),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          'Метки на экране',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
        ),
      ),
      IconButton(
        key: const Key('on_screen_all_markers'),
        tooltip: 'Все метки',
        icon: const Icon(Icons.folder_special_outlined, size: 22, color: _ink),
        onPressed: _openAllMarkers,
      ),
      IconButton(
        key: const Key('on_screen_remove_all'),
        tooltip: 'Убрать все',
        icon: const Icon(Icons.playlist_remove, size: 22, color: _ink),
        onPressed: _removeAll,
      ),
      IconButton(
        key: const Key('on_screen_close'),
        icon: const Icon(Icons.close, size: 22, color: _ink),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );

  Widget _sectionHeader(int? count) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'МЕТКИ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF616161)),
              ),
              if (count != null) Text('$count элем.', style: const TextStyle(fontSize: 13, color: _faded)),
            ],
          ),
        ),
        IconButton(
          key: const Key('on_screen_section_menu_button'),
          icon: const Icon(Icons.more_vert, color: _ink),
          onPressed: _openSectionMenu,
        ),
      ],
    ),
  );

  Widget _row(LandmarkItem item, ({double latitude, double longitude})? center) {
    final visible = _onScreen.isVisible(item.path);
    final distance = OnScreenSort.distanceFrom(center, item);
    final bearing = OnScreenSort.bearingFrom(center, item);
    final color = visible ? Color(item.colorValue | 0xFF000000) : _faded;
    return InkWell(
      key: ValueKey(item.path),
      onTap: () => _openDetails(item.path),
      onLongPress: () => _openMenu(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(ItemRow.iconFor(item.type), color: color, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, color: visible ? const Color(0xFF212121) : _faded),
                  ),
                  if (distance != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          DetailsFormat.distance(distance),
                          style: const TextStyle(fontSize: 13, color: Color(0xFF757575)),
                        ),
                        const SizedBox(width: 4),
                        Transform.rotate(
                          angle: (bearing ?? 0) * pi / 180,
                          child: const Icon(Icons.arrow_upward, size: 16, color: Color(0xFF757575)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            IconButton(
              key: Key('on_screen_eye_${item.name}'),
              tooltip: visible ? 'Скрыть' : 'Показать',
              icon: Icon(visible ? Icons.visibility : Icons.visibility_off_outlined, color: visible ? _ink : _faded),
              onPressed: () => _onScreen.toggle(item.path),
            ),
          ],
        ),
      ),
    );
  }
}

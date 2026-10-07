import 'package:flutter/material.dart';

import 'online_maps_models.dart';
import 'widgets/dropdown_menu.dart';
import 'widgets/map_source_accordion.dart';
import 'widgets/online_maps_app_bar.dart';
import 'widgets/side_drawer.dart';
import 'widgets/storage_bar.dart';

/// «Онлайн-карты»: online map sources as independent accordions of map
/// cards. Runs on mock data ([mockMapSources]) and keeps all state local.
class OnlineMapsScreen extends StatefulWidget {
  const OnlineMapsScreen({
    super.key,
    this.sources = mockMapSources,
    this.storage = mockStorageUsage,
    this.folders = mockDeviceFolders,
  });

  final List<OnlineMapSource> sources;
  final StorageUsage storage;
  final List<DeviceFolder> folders;

  @override
  State<OnlineMapsScreen> createState() => _OnlineMapsScreenState();
}

class _OnlineMapsScreenState extends State<OnlineMapsScreen> {
  Map<String, bool> _openSources = const {'google': true};
  bool _isDrawerOpen = false;
  bool _isDropdownOpen = false;
  OnlineMapsSection _activeSection = OnlineMapsSection.installed;
  OnlineMapsFilter _filter = const OnlineMapsFilter();

  void _toggleSource(String id) => setState(() => _openSources = {..._openSources, id: !(_openSources[id] ?? false)});

  void _toggleDrawer() => setState(() {
    _isDrawerOpen = !_isDrawerOpen;
    _isDropdownOpen = false;
  });

  void _toggleDropdown() => setState(() {
    _isDropdownOpen = !_isDropdownOpen;
    _isDrawerOpen = false;
  });

  void _selectSection(OnlineMapsSection section) => setState(() {
    _activeSection = section;
    _isDrawerOpen = false;
  });

  void _onMenuAction(OnlineMapsMenuAction action) {
    setState(() => _isDropdownOpen = false);
    switch (action) {
      case OnlineMapsMenuAction.filter:
        _openFilter();
      case OnlineMapsMenuAction.settings:
        showDialog<void>(context: context, builder: (_) => const _MapSettingsDialog());
      case OnlineMapsMenuAction.help:
        showDialog<void>(context: context, builder: (_) => const _HelpDialog());
    }
  }

  Future<void> _openFilter() async {
    final filter = await showDialog<OnlineMapsFilter>(
      context: context,
      builder: (_) => _FilterDialog(initial: _filter),
    );
    if (filter != null && mounted) setState(() => _filter = filter);
  }

  void _onMapMore(OnlineMap map) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${map.name}: действия в разработке')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          OnlineMapsAppBar(
            subtitle: _activeSection.label,
            onMenu: _toggleDrawer,
            onClose: () => Navigator.of(context).maybePop(),
            onMore: _toggleDropdown,
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _body()),
                Positioned.fill(
                  child: SideDrawer(
                    isOpen: _isDrawerOpen,
                    activeSection: _activeSection,
                    storage: widget.storage,
                    folders: widget.folders,
                    onSectionSelected: _selectSection,
                    onClose: () => setState(() => _isDrawerOpen = false),
                  ),
                ),
                Positioned.fill(
                  child: OnlineMapsDropdownMenu(
                    isOpen: _isDropdownOpen,
                    onSelected: _onMenuAction,
                    onDismiss: () => setState(() => _isDropdownOpen = false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_activeSection == OnlineMapsSection.altitude) {
      return const Center(
        child: Card(
          child: Padding(padding: EdgeInsets.all(24), child: Text('Раздел в разработке')),
        ),
      );
    }
    final visible = [
      for (final source in widget.sources) (source: source, maps: source.maps.where(_filter.accepts).toList()),
    ].where((entry) => entry.maps.isNotEmpty).toList();
    return Column(
      children: [
        StorageBar(
          key: const Key('online_maps_storage'),
          usage: widget.storage,
          onSettings: () => _onMenuAction(OnlineMapsMenuAction.settings),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('Нет карт, подходящих под фильтр'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    for (final entry in visible)
                      MapSourceAccordion(
                        key: Key('source_${entry.source.id}'),
                        source: entry.source,
                        maps: entry.maps,
                        isOpen: _openSources[entry.source.id] ?? false,
                        onToggle: () => _toggleSource(entry.source.id),
                        onMapMore: _onMapMore,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.initial});

  final OnlineMapsFilter initial;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late bool _onlyDownloaded = widget.initial.onlyDownloaded;
  late bool _onlySatellite = widget.initial.onlySatellite;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Фильтр'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            key: const Key('filter_only_downloaded'),
            title: const Text('Только скачанные'),
            value: _onlyDownloaded,
            onChanged: (v) => setState(() => _onlyDownloaded = v ?? false),
          ),
          CheckboxListTile(
            key: const Key('filter_only_satellite'),
            title: const Text('Только спутниковые'),
            value: _onlySatellite,
            onChanged: (v) => setState(() => _onlySatellite = v ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        TextButton(
          key: const Key('filter_apply'),
          onPressed: () => Navigator.of(
            context,
          ).pop(OnlineMapsFilter(onlyDownloaded: _onlyDownloaded, onlySatellite: _onlySatellite)),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

enum _CoordinateFormat { wgs84, sk42 }

/// Stub: the options are not stored anywhere yet.
class _MapSettingsDialog extends StatefulWidget {
  const _MapSettingsDialog();

  @override
  State<_MapSettingsDialog> createState() => _MapSettingsDialogState();
}

class _MapSettingsDialogState extends State<_MapSettingsDialog> {
  _CoordinateFormat _format = _CoordinateFormat.wgs84;
  bool _cacheTiles = true;
  bool _autoDownload = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Настройки карт'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: RadioGroup<_CoordinateFormat>(
        groupValue: _format,
        onChanged: (v) => setState(() => _format = v ?? _format),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(dense: true, title: Text('Формат координат')),
            const RadioListTile(value: _CoordinateFormat.wgs84, title: Text('WGS84')),
            const RadioListTile(value: _CoordinateFormat.sk42, title: Text('СК-42')),
            SwitchListTile(
              title: const Text('Кэшировать тайлы'),
              value: _cacheTiles,
              onChanged: (v) => setState(() => _cacheTiles = v),
            ),
            SwitchListTile(
              title: const Text('Автозагрузка карт'),
              value: _autoDownload,
              onChanged: (v) => setState(() => _autoDownload = v),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть'))],
    );
  }
}

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Помощь'),
      content: const Text(
        'Нажмите на название источника, чтобы раскрыть или свернуть его карты. '
        'Источники раскрываются независимо друг от друга.\n\n'
        'Справа на карточке — размер сохранённого кэша карты («Нет» — карта не сохранялась).\n\n'
        '«Фильтр» в меню ⋮ оставляет только скачанные или только спутниковые карты.',
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Понятно'))],
    );
  }
}

import 'package:flutter/material.dart';

import 'available_maps_models.dart';

/// «Фильтр»: pops the chosen [MapsFilter], or null on «Отмена».
class MapsFilterDialog extends StatefulWidget {
  const MapsFilterDialog({super.key, required this.initial});

  final MapsFilter initial;

  @override
  State<MapsFilterDialog> createState() => _MapsFilterDialogState();
}

class _MapsFilterDialogState extends State<MapsFilterDialog> {
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
          onPressed: () =>
              Navigator.of(context).pop(MapsFilter(onlyDownloaded: _onlyDownloaded, onlySatellite: _onlySatellite)),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

enum _CoordinateFormat { wgs84, sk42 }

/// Stub: the options are not stored anywhere yet.
class MapsSettingsDialog extends StatefulWidget {
  const MapsSettingsDialog({super.key});

  @override
  State<MapsSettingsDialog> createState() => _MapsSettingsDialogState();
}

class _MapsSettingsDialogState extends State<MapsSettingsDialog> {
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

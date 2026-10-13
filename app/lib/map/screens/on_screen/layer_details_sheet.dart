import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../explorer/sheet_menu.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/map_models.dart';
import '../available_maps_screen.dart';
import '../layers_panel.dart';

/// Сведения о карте слоя: поставщик, формат, хранение, масштабы, адрес.
class LayerDetailsSheet extends ConsumerWidget {
  const LayerDetailsSheet({super.key, required this.sourceId});

  final String sourceId;

  static Future<void> show(BuildContext context, String sourceId) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LayerDetailsSheet(sourceId: sourceId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = catalogIndex(ref.watch(catalogProvider).value ?? const [])[sourceId];
    final source = entry?.source;
    final rows = <(String, String)>[
      if (entry != null) ('Поставщик', entry.provider.name),
      if (source != null) ...[
        ('Формат', source.format == TileFormat.raster ? 'Растровая' : 'Векторная'),
        ('Хранение', storageModeLabel(source.storageMode)),
        ('Масштабы', '${source.minZoom}–${source.maxZoom}'),
        if (source.version != null) ('Версия', source.version!),
        if ((source.tileUrlTemplate ?? source.styleUrl) != null) ('Адрес', (source.tileUrlTemplate ?? source.styleUrl)!),
        if (source.attribution != null) ('Авторство', source.attribution!),
      ],
    ];
    return SheetMenu(
      title: source?.name ?? sourceId,
      children: [
        if (rows.isEmpty) const Text('Карта не найдена в каталоге', style: TextStyle(color: SheetMenuColors.secondary)),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: SheetMenuColors.secondary)),
                SelectableText(value, style: const TextStyle(fontSize: 15, color: SheetMenuColors.text)),
              ],
            ),
          ),
        SheetMenuCancel(onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

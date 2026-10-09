import 'package:flutter/material.dart';

import '../map/screens/available_maps/available_maps_models.dart';
import 'explorer_style.dart';
import 'storage_meter.dart';

/// Заголовок места в боковом меню: название, путь и, для памяти
/// устройства, полоса занятого места.
class StoragePathBlock extends StatelessWidget {
  const StoragePathBlock({super.key, required this.title, required this.path, this.usage});

  final String title;
  final String path;

  /// Занятое место; null — полоса не показывается.
  final StorageUsage? usage;

  @override
  Widget build(BuildContext context) {
    final u = usage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, color: ExplorerStyle.text)),
          const SizedBox(height: 2),
          Text(path.endsWith('/') ? path : '$path/', style: ExplorerStyle.small),
          if (u != null) ...[
            const SizedBox(height: 8),
            StorageMeter(usedBytes: u.usedBytes, totalBytes: u.totalBytes),
            const SizedBox(height: 4),
            Center(child: Text(u.label, style: const TextStyle(fontSize: 11, color: Color(0xFF424242)))),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../app_icons.dart';
import '../../widgets/app_icon.dart';
import '../online_maps_models.dart';

/// Used / total device storage as a green-on-gray bar. Shows the storage
/// path when [showPath] and a settings button when [onSettings] is given.
class StorageBar extends StatelessWidget {
  const StorageBar({super.key, required this.usage, this.showPath = false, this.onSettings});

  final StorageUsage usage;
  final bool showPath;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: usage.fraction,
                    minHeight: 8,
                    color: Colors.green.shade600,
                    backgroundColor: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (showPath)
                      Expanded(
                        child: Text(usage.path, style: caption, overflow: TextOverflow.ellipsis),
                      ),
                    if (!showPath) const Spacer(),
                    Text('${usage.usedGb} ГБ / ${usage.totalGb} ГБ', style: caption),
                  ],
                ),
              ],
            ),
          ),
          if (onSettings != null)
            IconButton(
              key: const Key('storage_settings_button'),
              icon: const AppIcon(AppIcons.settings),
              onPressed: onSettings,
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../app_icons.dart';
import '../../../widgets/app_icon.dart';
import 'available_maps_models.dart';

/// Used / total device storage as a green-on-gray bar (empty while
/// [usage] is unknown). Shows the storage
/// path when [showPath] (else [caption], e.g. the cache size) and a settings
/// button when [onSettings] is given.
class StorageBar extends StatelessWidget {
  const StorageBar({super.key, required this.usage, this.showPath = false, this.caption, this.onSettings});

  final StorageUsage? usage;
  final bool showPath;
  final String? caption;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final usage = this.usage;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
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
                    value: usage?.fraction ?? 0,
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
                        child: Text(usage?.path ?? '', style: small, overflow: TextOverflow.ellipsis),
                      ),
                    if (!showPath)
                      Expanded(
                        child: Text(caption ?? '', style: small, overflow: TextOverflow.ellipsis),
                      ),
                    if (usage != null) Text(usage.label, style: small),
                  ],
                ),
              ],
            ),
          ),
          if (onSettings != null)
            IconButton(
              key: const Key('storage_settings_button'),
              icon: const AppIcon(AppIcons.gear),
              onPressed: onSettings,
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

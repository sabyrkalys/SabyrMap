import 'package:flutter/material.dart';

import '../../app_icons.dart';
import '../../widgets/app_icon.dart';

/// Top bar: menu | «Онлайн-карты» over the active section | close, more.
class OnlineMapsAppBar extends StatelessWidget {
  const OnlineMapsAppBar({
    super.key,
    required this.subtitle,
    required this.onMenu,
    required this.onClose,
    required this.onMore,
  });

  final String subtitle;
  final VoidCallback onMenu;
  final VoidCallback onClose;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(key: const Key('online_maps_menu_button'), icon: const Icon(Icons.menu), onPressed: onMenu),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Онлайн-карты', style: theme.textTheme.titleMedium, maxLines: 1),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('online_maps_close_button'),
                icon: const AppIcon(AppIcons.close),
                onPressed: onClose,
              ),
              IconButton(
                key: const Key('online_maps_more_button'),
                icon: const AppIcon(AppIcons.dotsVertical),
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../app_icons.dart';
import '../../../widgets/app_icon.dart';

/// Top bar: menu | [title] over an optional [subtitle] | close, more.
/// With [search] set it is a search field instead: back | 🔍 query | ×.
class MapsAppBar extends StatelessWidget {
  const MapsAppBar({
    super.key,
    required this.title,
    this.subtitle,
    required this.onMenu,
    required this.onClose,
    required this.onMore,
    this.search,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onMenu;
  final VoidCallback onClose;
  final VoidCallback onMore;
  final MapsSearch? search;

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
          child: search != null
              ? _SearchRow(search: search!)
              : Row(
                  children: [
                    IconButton(key: const Key('maps_menu_button'), icon: const Icon(Icons.menu), onPressed: onMenu),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium, maxLines: 1),
                          if (subtitle case final subtitle?)
                            Text(
                              subtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('maps_close_button'),
                      icon: const AppIcon(AppIcons.close),
                      onPressed: onClose,
                    ),
                    IconButton(
                      key: const Key('maps_more_button'),
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

/// The search mode of [MapsAppBar]: the query in [controller]; [onExit]
/// leaves the mode (back, or × on the field).
class MapsSearch {
  const MapsSearch({required this.controller, required this.onExit});

  final TextEditingController controller;
  final VoidCallback onExit;
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.search});

  final MapsSearch search;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(key: const Key('maps_search_back'), icon: const Icon(Icons.arrow_back), onPressed: search.onExit),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              key: const Key('maps_search_field'),
              controller: search.controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск карт',
                isDense: true,
                border: InputBorder.none,
                prefixIcon: const Padding(padding: EdgeInsets.all(12), child: AppIcon(AppIcons.search, size: 20)),
                suffixIcon: ListenableBuilder(
                  listenable: search.controller,
                  builder: (_, _) => search.controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          key: const Key('maps_search_clear'),
                          icon: const AppIcon(AppIcons.close, size: 20),
                          onPressed: search.onExit,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

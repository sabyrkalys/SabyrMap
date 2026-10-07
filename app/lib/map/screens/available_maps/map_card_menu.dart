import 'package:flutter/material.dart';

import '../../../app_icons.dart';
import '../../../widgets/app_icon.dart';

enum MapCardAction { remove, show, addOverlay, favorite, details, clearCache }

const Color _teal = Color(0xFF00897B);

/// The ⋮ menu of a map card: a centred dialog titled with the map's name.
/// A map on screen ([active]) offers «Убрать», any other «Показать» and
/// «Добавить как слой». Pops the chosen action, or null on «Отмена» or a tap
/// outside.
Future<MapCardAction?> showMapCardMenu(
  BuildContext context, {
  required String mapName,
  required bool active,
  required bool favorite,
  required bool canOverlay,
  required bool canClearCache,
}) {
  return showGeneralDialog<MapCardAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => MapCardMenu(
      mapName: mapName,
      active: active,
      favorite: favorite,
      canOverlay: canOverlay,
      canClearCache: canClearCache,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class MapCardMenu extends StatelessWidget {
  const MapCardMenu({
    super.key,
    required this.mapName,
    required this.active,
    required this.favorite,
    required this.canOverlay,
    required this.canClearCache,
  });

  final String mapName;
  final bool active;
  final bool favorite;
  final bool canOverlay;
  final bool canClearCache;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = (MediaQuery.sizeOf(context).width * 0.8).clamp(0.0, 384.0);
    void pick(MapCardAction action) => Navigator.of(context).pop(action);
    return Center(
      child: Material(
        key: const Key('map_card_menu'),
        color: theme.colorScheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  mapName,
                  style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                if (active)
                  _Item(
                    action: MapCardAction.remove,
                    icon: const AppIcon(AppIcons.layers, color: _teal),
                    label: 'Убрать',
                    onTap: pick,
                  )
                else ...[
                  _Item(
                    action: MapCardAction.show,
                    icon: const AppIcon(AppIcons.eye, color: _teal),
                    label: 'Показать',
                    onTap: pick,
                  ),
                  _Item(
                    action: MapCardAction.addOverlay,
                    icon: const AppIcon(AppIcons.layers, color: _teal),
                    label: 'Добавить как слой',
                    onTap: canOverlay ? pick : null,
                  ),
                ],
                _Item(
                  action: MapCardAction.favorite,
                  icon: AppIcon(favorite ? AppIcons.star : AppIcons.bookmarkPlus, color: _teal),
                  label: favorite ? 'Убрать из избранных' : 'Сохранить в избранные',
                  onTap: pick,
                ),
                _Item(
                  action: MapCardAction.details,
                  icon: const Icon(Icons.image_search, color: _teal),
                  label: 'Детали',
                  onTap: pick,
                ),
                if (canClearCache)
                  _Item(
                    action: MapCardAction.clearCache,
                    icon: AppIcon(AppIcons.trash, color: theme.colorScheme.error),
                    label: 'Очистить кэш',
                    onTap: pick,
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('map_card_menu_cancel'),
                    style: TextButton.styleFrom(foregroundColor: _teal),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.action, required this.icon, required this.label, required this.onTap});

  final MapCardAction action;
  final Widget icon;
  final String label;

  /// Null greys the item out.
  final ValueChanged<MapCardAction>? onTap;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: InkWell(
        key: Key('map_card_menu_${action.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap == null ? null : () => onTap(action),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              SizedBox(width: 24, child: IconTheme(data: const IconThemeData(size: 24), child: icon)),
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
            ],
          ),
        ),
      ),
    );
  }
}

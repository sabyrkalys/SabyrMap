import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dialogs/confirm_dialog.dart';
import '../../../explorer/sheet_menu.dart';
import '../../../home/home_nav_scope.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/map_models.dart';
import '../../services/map_previews.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';
import 'favorite_set_save_dialog.dart';

const Color _secondary = Color(0xFF757575);

/// [preset] — то, что сейчас на экране: та же карта и те же слои в том же
/// порядке.
bool isOnScreen(MapState state, MapPreset preset) =>
    state.baseSourceId == preset.baseSourceId &&
    state.overlaysUnderMap == preset.overlaysUnderMap &&
    state.overlays.map((l) => l.sourceId).join('|') == preset.overlays.map((l) => l.sourceId).join('|');

/// «ИЗБРАННЫЕ КАРТЫ И НАБОРЫ КАРТ» в меню «Карты»: сохранённые наборы
/// (карта, слои и их вид) и избранные карты — карточками по две в ряд.
/// Тап по набору применяет его и вызывает [onApplied] (меню закрывается).
class FavoriteSetsSection extends ConsumerWidget {
  const FavoriteSetsSection({super.key, this.onApplied});

  final VoidCallback? onApplied;

  /// Ширина к высоте карточки.
  static const double cardAspect = 2.7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mapLayersProvider);
    final index = catalogIndex(ref.watch(catalogProvider).value ?? const []);
    final favoriteMaps = [
      for (final id in state.favoriteIds)
        if (index[id] case final entry?) entry.source,
    ];

    MapSource? pictureOf(MapPreset preset) =>
        index[preset.baseSourceId]?.source ??
        [for (final l in preset.overlays.reversed) index[l.sourceId]?.source].nonNulls.firstOrNull;

    final cards = <Widget>[
      for (final preset in state.presets)
        FavoriteCard(
          key: Key('favorite_set_${preset.id}'),
          source: pictureOf(preset),
          label: preset.name,
          selected: isOnScreen(state, preset),
          onTap: () {
            applyFavoriteSet(context, ref, preset);
            onApplied?.call();
          },
          onLongPress: () => FavoriteSetContextMenu.show(context, preset, onApplied: onApplied),
        ),
      for (final source in favoriteMaps)
        FavoriteCard(
          key: Key('favorite_map_${source.id}'),
          source: source,
          label: source.name,
          selected: state.baseSourceId == source.id && state.overlays.isEmpty,
          onTap: () {
            runLayerChange(context, () => ref.read(mapLayersProvider.notifier).setBase(source));
            onApplied?.call();
          },
          onLongPress: () => FavoriteMapMenu.show(context, source, onApplied: onApplied),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Flexible(
                flex: 4,
                child: Text(
                  'ИЗБРАННЫЕ КАРТЫ И НАБОРЫ КАРТ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: _secondary, letterSpacing: 0.5, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Divider(color: SheetMenuColors.divider, height: 1)),
              IconButton(
                key: const Key('favorite_sets_add'),
                tooltip: 'Сохранить в избранные',
                icon: const Icon(Icons.bookmark_add, size: 22, color: Color(0xFFBDBDBD)),
                onPressed: () => FavoriteSetSaveDialog.show(context),
              ),
            ],
          ),
          if (cards.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 12),
              child: Text(
                'Избранные карты и наборы карт не созданы',
                style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: _secondary),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final width = (constraints.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final card in cards) SizedBox(width: width, height: width / cardAspect, child: card),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Применяет [preset]; что не удалось показать — SnackBar.
Future<void> applyFavoriteSet(BuildContext context, WidgetRef ref, MapPreset preset) =>
    runLayerChange(context, () async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final result = await ref.read(mapLayersProvider.notifier).applyPreset(preset);
      if (!result.ok) messenger?.showSnackBar(SnackBar(content: Text(result.problems.join('\n'))));
    });

/// Карточка избранного: картинка карты, подпись курсивом внизу; то, что
/// сейчас на экране, — в серой рамке.
class FavoriteCard extends ConsumerWidget {
  const FavoriteCard({
    super.key,
    required this.source,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final MapSource? source;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = this.source;
    final preview = source == null ? null : ref.watch(mapPreviewProvider(source)).value;
    final asset = source?.thumbnailAsset;
    final ImageProvider? image = preview != null ? FileImage(preview) : (asset != null ? AssetImage(asset) : null);
    return Material(
      color: const Color(0xFFE0E0E0),
      elevation: 1,
      shape: RoundedRectangleBorder(
        side: selected ? const BorderSide(color: Color(0xFF757575), width: 3) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: image == null
            ? null
            : BoxDecoration(image: DecorationImage(image: image, fit: BoxFit.cover, onError: (_, _) {})),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            children: [
              if (image == null) const Center(child: Icon(Icons.map_outlined, color: Color(0xFF9E9E9E))),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: const Color(0xB3F5F5F5),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: Color(0xFF212121)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Меню избранной карты: показать, убрать из избранных.
class FavoriteMapMenu extends ConsumerWidget {
  const FavoriteMapMenu({super.key, required this.source, this.onApplied});

  final MapSource source;
  final VoidCallback? onApplied;

  static Future<void> show(BuildContext context, MapSource source, {VoidCallback? onApplied}) =>
      HomeNavScope.showSheet(context, (_) => FavoriteMapMenu(source: source, onApplied: onApplied));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator.of(context);
    final under = navigator.context;
    final notifier = ref.read(mapLayersProvider.notifier);
    return SheetMenu(
      title: source.name,
      children: [
        SheetMenuItem(
          key: const Key('favorite_map_show'),
          icon: Icons.visibility,
          color: SheetMenuColors.accent,
          label: 'Показать',
          onTap: () {
            navigator.pop();
            runLayerChange(under, () => notifier.setBase(source));
            onApplied?.call();
          },
        ),
        SheetMenuItem(
          key: const Key('favorite_map_remove'),
          icon: Icons.bookmark_remove_outlined,
          color: SheetMenuColors.edit,
          label: 'Убрать из избранных',
          onTap: () {
            navigator.pop();
            notifier.toggleFavorite(source.id);
          },
        ),
        SheetMenuCancel(onPressed: () => navigator.pop()),
      ],
    );
  }
}

/// Меню набора: применить, переименовать, удалить.
class FavoriteSetContextMenu extends ConsumerWidget {
  const FavoriteSetContextMenu({super.key, required this.preset, this.onApplied});

  final MapPreset preset;
  final VoidCallback? onApplied;

  static Future<void> show(BuildContext context, MapPreset preset, {VoidCallback? onApplied}) =>
      HomeNavScope.showSheet(context, (_) => FavoriteSetContextMenu(preset: preset, onApplied: onApplied));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator.of(context);
    final under = navigator.context;
    final notifier = ref.read(mapLayersProvider.notifier);
    return SheetMenu(
      title: preset.name,
      children: [
        SheetMenuItem(
          key: const Key('favorite_menu_apply'),
          icon: Icons.check,
          color: SheetMenuColors.accent,
          label: 'Применить',
          onTap: () {
            navigator.pop();
            applyFavoriteSet(under, ref, preset);
            onApplied?.call();
          },
        ),
        SheetMenuItem(
          key: const Key('favorite_menu_rename'),
          icon: Icons.edit_outlined,
          color: SheetMenuColors.edit,
          label: 'Переименовать',
          onTap: () async {
            navigator.pop();
            final name = await FavoriteSetNameDialog.ask(under, title: 'Переименовать', initialName: preset.name);
            if (name != null) await notifier.renamePreset(preset.id, name);
          },
        ),
        SheetMenuItem(
          key: const Key('favorite_menu_delete'),
          icon: Icons.delete_outline,
          color: SheetMenuColors.edit,
          label: 'Удалить',
          onTap: () async {
            navigator.pop();
            if (await showConfirmDialog(under, title: 'Удалить «${preset.name}»?')) {
              await notifier.deletePreset(preset.id);
            }
          },
        ),
        SheetMenuCancel(onPressed: () => navigator.pop()),
      ],
    );
  }
}

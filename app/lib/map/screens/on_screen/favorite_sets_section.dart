import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dialogs/confirm_dialog.dart';
import '../../../explorer/sheet_menu.dart';
import '../../models/map_models.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';
import 'favorite_set_save_dialog.dart';

const Color _ink = Color(0xFF333333);
const Color _secondary = Color(0xFF757575);

/// «ИЗБРАННЫЕ КАРТЫ И НАБОРЫ КАРТ» в меню «Карты»: сохранённые наборы
/// (базовая карта + слои + их вид). Тап применяет набор и вызывает
/// [onApplied] (меню закрывается).
class FavoriteSetsSection extends ConsumerWidget {
  const FavoriteSetsSection({super.key, this.onApplied});

  final VoidCallback? onApplied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(mapLayersProvider.select((s) => s.presets));
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
                tooltip: 'Сохранить в избранное',
                icon: const Icon(Icons.bookmark_add_outlined, size: 20, color: _secondary),
                onPressed: () => FavoriteSetSaveDialog.show(context),
              ),
            ],
          ),
          if (presets.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 12),
              child: Text(
                'Избранные карты и наборы карт не созданы',
                style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: _secondary),
              ),
            )
          else
            for (final preset in presets) FavoriteSetTile(preset: preset, onApplied: onApplied),
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

class FavoriteSetTile extends ConsumerWidget {
  const FavoriteSetTile({super.key, required this.preset, this.onApplied});

  final MapPreset preset;
  final VoidCallback? onApplied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void apply() {
      applyFavoriteSet(context, ref, preset);
      onApplied?.call();
    }

    return InkWell(
      key: Key('favorite_set_${preset.id}'),
      onTap: apply,
      onLongPress: () => FavoriteSetContextMenu.show(context, preset, onApplied: onApplied),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.bookmark_outline, size: 22, color: _ink),
            const SizedBox(width: 12),
            Expanded(child: Text(preset.name, style: const TextStyle(fontSize: 15, color: Color(0xFF212121)))),
            IconButton(
              key: Key('favorite_set_menu_${preset.id}'),
              icon: const Icon(Icons.more_vert, size: 20, color: _ink),
              onPressed: () => FavoriteSetContextMenu.show(context, preset, onApplied: onApplied),
            ),
          ],
        ),
      ),
    );
  }
}

/// Меню набора: применить, переименовать, удалить.
class FavoriteSetContextMenu extends ConsumerWidget {
  const FavoriteSetContextMenu({super.key, required this.preset, this.onApplied});

  final MapPreset preset;
  final VoidCallback? onApplied;

  static Future<void> show(BuildContext context, MapPreset preset, {VoidCallback? onApplied}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FavoriteSetContextMenu(preset: preset, onApplied: onApplied),
      );

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

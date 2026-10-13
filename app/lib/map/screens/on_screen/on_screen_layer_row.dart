import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/map_models.dart';
import '../../services/map_previews.dart';

const Color _ink = Color(0xFF333333);
const double _handleWidth = 36;
const Color _accent = Color(0xFF00A38E);
const TextStyle _titleStyle = TextStyle(fontSize: 16, color: Color(0xFF212121));
const TextStyle _subtitleStyle = TextStyle(fontSize: 12, color: Color(0xFF757575));

/// Карточка строки слоя с промежутком снизу: картинка карты [source]
/// (та же, что в «Доступных картах») бледной подложкой; без картинки —
/// белый фон.
class LayerRowBackground extends ConsumerWidget {
  const LayerRowBackground({super.key, required this.source, required this.child});

  /// Сила картинки: видна карта, но текст читается.
  static const double previewOpacity = 0.35;

  /// Промежуток между строками.
  static const double gap = 8;

  final MapSource? source;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = this.source;
    final preview = source == null ? null : ref.watch(mapPreviewProvider(source)).value;
    final asset = source?.thumbnailAsset;
    final image = preview != null ? FileImage(preview) : (asset != null ? AssetImage(asset) : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: gap),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: image == null
              ? null
              : BoxDecoration(
                  image: DecorationImage(
                    image: image as ImageProvider,
                    fit: BoxFit.cover,
                    opacity: previewOpacity,
                    onError: (_, _) {},
                  ),
                ),
          child: child,
        ),
      ),
    );
  }
}

/// «N % непрозрачн.»
String opacityLabel(double opacity) => '${(opacity * 100).round()} % непрозрачн.';

/// Строка наложенного слоя: ручка перетаскивания, глазик, имя и
/// непрозрачность, кнопки непрозрачности и меню. Тап по строке —
/// непрозрачность, долгий тап — меню.
class OnScreenLayerRow extends StatelessWidget {
  const OnScreenLayerRow({
    super.key,
    this.index,
    required this.layer,
    required this.name,
    this.source,
    required this.onVisible,
    required this.onOpacity,
    required this.onMenu,
  });

  /// Место в [ReorderableListView] — для ручки перетаскивания; null —
  /// строку не перетащить (ортофотопланы).
  final int? index;
  final ActiveLayer layer;
  final String name;
  final MapSource? source;
  final ValueChanged<bool> onVisible;
  final VoidCallback onOpacity;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => LayerRowBackground(
    source: source,
    child: InkWell(
      onTap: onOpacity,
      onLongPress: onMenu,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (index case final index?)
              ReorderableDragStartListener(
                key: Key('layer_drag_${layer.sourceId}'),
                index: index,
                child: const SizedBox(
                  width: _handleWidth,
                  height: 48,
                  child: Icon(Icons.drag_handle, size: 22, color: _ink),
                ),
              )
            else
              const SizedBox(width: _handleWidth),
            IconButton(
              key: Key('layer_visible_${layer.sourceId}'),
              icon: Icon(layer.visible ? Icons.visibility : Icons.visibility_off, size: 22, color: _accent),
              onPressed: () => onVisible(!layer.visible),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: _titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(opacityLabel(layer.opacity), style: _subtitleStyle),
                ],
              ),
            ),
            IconButton(
              key: Key('layer_opacity_${layer.sourceId}'),
              tooltip: 'Непрозрачность',
              icon: const Icon(Icons.layers_outlined, size: 22, color: _ink),
              onPressed: onOpacity,
            ),
            IconButton(
              key: Key('layer_menu_${layer.sourceId}'),
              icon: const Icon(Icons.more_vert, size: 22, color: _ink),
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Строка базовой карты — всегда последняя; без глазика и непрозрачности:
/// базовую карту не убрать, только сменить (тап по строке).
class OnScreenLayerBaseRow extends StatelessWidget {
  const OnScreenLayerBaseRow({super.key, required this.name, this.source, required this.onTap, required this.onMenu});

  final String name;
  final MapSource? source;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => LayerRowBackground(
    key: const Key('layer_base_row'),
    source: source,
    child: InkWell(
      onTap: onTap,
      onLongPress: onMenu,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: _handleWidth + 48 + 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Базовая карта', style: _titleStyle),
                  Text(name, style: _subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              key: const Key('layer_menu_base'),
              icon: const Icon(Icons.more_vert, size: 22, color: _ink),
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    ),
  );
}

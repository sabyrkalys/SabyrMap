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
  const LayerRowBackground({super.key, required this.source, this.image, required this.child});

  /// Своя картинка вместо картинки карты [source].
  final ImageProvider? image;

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
    final image =
        this.image ?? (preview != null ? FileImage(preview) : (asset != null ? AssetImage(asset) : null));
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
                    image: image,
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
    this.erasing = false,
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

  /// У слоя включено «Удалить цвет» — красная строка-статус.
  final bool erasing;
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
                  if (erasing)
                    const Text(
                      'Удалить цвет',
                      key: Key('layer_status_erase'),
                      style: TextStyle(fontSize: 11, color: Color(0xFFD32F2F)),
                    ),
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

/// Нижние строки без глазика и ручки: выбранная карта (тап — сменить её)
/// и встроенная «Базовая карта» под ней (тап — непрозрачность).
class OnScreenLayerBaseRow extends StatelessWidget {
  const OnScreenLayerBaseRow({
    super.key,
    required this.rowKey,
    required this.menuKey,
    required this.title,
    required this.subtitle,
    this.source,
    this.image,
    this.visible,
    this.visibleKey,
    this.onVisible,
    required this.onTap,
    required this.onMenu,
  });

  /// Картинка подложки вместо картинки карты [source].
  final ImageProvider? image;

  /// Глазик: null — без него.
  final bool? visible;
  final Key? visibleKey;
  final ValueChanged<bool>? onVisible;

  final Key rowKey;
  final Key menuKey;
  final String title;
  final String subtitle;
  final MapSource? source;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => LayerRowBackground(
    key: rowKey,
    source: source,
    image: image,
    child: InkWell(
      onTap: onTap,
      onLongPress: onMenu,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: _handleWidth),
            if (visible case final visible?)
              IconButton(
                key: visibleKey,
                icon: Icon(visible ? Icons.visibility : Icons.visibility_off, size: 22, color: _accent),
                onPressed: () => onVisible?.call(!visible),
              )
            else
              const SizedBox(width: 48),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(subtitle, style: _subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              key: menuKey,
              icon: const Icon(Icons.more_vert, size: 22, color: _ink),
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    ),
  );
}

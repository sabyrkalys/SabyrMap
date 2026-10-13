import 'package:flutter/material.dart';

import '../../models/map_models.dart';

const Color _ink = Color(0xFF333333);
const Color _accent = Color(0xFF00A38E);
const TextStyle _titleStyle = TextStyle(fontSize: 16, color: Color(0xFF212121));
const TextStyle _subtitleStyle = TextStyle(fontSize: 12, color: Color(0xFF757575));

/// «N % непрозрачн.»
String opacityLabel(double opacity) => '${(opacity * 100).round()} % непрозрачн.';

/// Строка наложенного слоя: глазик, имя и непрозрачность, кнопки
/// непрозрачности и меню. Тап по строке — непрозрачность.
class OnScreenLayerRow extends StatelessWidget {
  const OnScreenLayerRow({
    super.key,
    required this.layer,
    required this.name,
    required this.onVisible,
    required this.onOpacity,
    required this.onMenu,
  });

  final ActiveLayer layer;
  final String name;
  final ValueChanged<bool> onVisible;
  final VoidCallback onOpacity;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: InkWell(
          onTap: onOpacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
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
  const OnScreenLayerBaseRow({super.key, required this.name, required this.onTap, required this.onMenu});

  final String name;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Material(
        key: const Key('layer_base_row'),
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const SizedBox(width: 48),
                const SizedBox(width: 8),
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

import 'package:flutter/material.dart';

import 'models/map_models.dart';

/// Attributions of every visible layer (base + overlays), without repeats:
/// «© OpenFreeMap · © OpenStreetMap contributors». Providers require it, so
/// it is always one tap away ([AttributionButton]).
String attributionText(MapSource? base, List<MapSource> visibleOverlays) {
  final parts = <String>[];
  for (final source in [if (base != null) base, ...visibleOverlays]) {
    for (final part in (source.attribution ?? '').split('·')) {
      final text = part.trim();
      if (text.isNotEmpty && !parts.contains(text)) parts.add(text);
    }
  }
  return parts.join(' · ');
}

/// A small half-transparent round (i) in the top right corner: the
/// attributions open in a dialog instead of a bar over the map. Replaces
/// MapLibre's own (i), which lists only attributions written as HTML links
/// (ours are plain text). Drawn [size] across, it takes taps in a larger
/// invisible square ([hitSize]) so it can still be hit with a finger.
class AttributionButton extends StatelessWidget {
  const AttributionButton({super.key, required this.text});

  /// Visible circle, dp.
  static const double size = 18;

  /// Tap area around it, dp.
  static const double hitSize = 32;

  final String text;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('attribution_button'),
      customBorder: const CircleBorder(),
      onTap: () => showDialog<void>(
          context: context,
        builder: (context) => AlertDialog(
          title: const Text('Источники карт'),
          content: Text(text.isEmpty ? 'Нет данных об авторах карты' : text.split(' · ').join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
        ),
      ),
      child: SizedBox(
        width: hitSize,
        height: hitSize,
        child: Center(
          child: Container(
            key: const Key('attribution_dot'),
            width: size,
            height: size,
            // Same see-through look as the bottom nav panel.
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), shape: BoxShape.circle),
            child: const Icon(Icons.info_outline, size: 14, color: Color(0xB316181A)),
          ),
        ),
      ),
    );
  }
}
